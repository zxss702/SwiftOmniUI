// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIGTK

/// A `GtkLabel` and its inline pictures, using the label's single Pango layout for wrapping and hit testing.
/// Design: docs/design/platforms/gtk/controls.md#words
@MainActor
class GTKTextView: GTKPanelView {
    private let label: GTKWidget = gtk_label_new(nil)!
    override func firstTextBaseline(in size: LayoutSize) -> Double? {
        guard size.width.isFinite, size.width >= 0 else { return nil }
        var natural: Int32 = 0, baseline: Int32 = -1
        gtk_widget_measure(label, GTK_ORIENTATION_VERTICAL,
                           Int32(min(size.width.rounded(.down), Double(Int32.max))),
                           nil, &natural, nil, &baseline)
        if baseline >= 0 {
            let extra = max(0, size.height - Double(natural))
            return Double(baseline) + extra * Double(gtk_label_get_yalign(label.opaque))
        }
        guard let layout = gtk_label_get_layout(label.opaque) else { return nil }
        var logical = PangoRectangle()
        pango_layout_get_pixel_extents(layout, nil, &logical)
        let extra = max(0, size.height - Double(logical.height))
        let shift = extra * Double(gtk_label_get_yalign(label.opaque))
        return Double(pango_layout_get_baseline(layout)) / Double(PANGO_SCALE) + shift
    }

    private struct InlineImage {
        let source: ImageSource
        let byte: UInt32
        let size: Size
        let baseline: Double
        let color: HostValue?
        let paintable: OpaquePointer
    }
    private var inlineImages: [InlineImage] = []
    private var inlineImageScale: Int32 = 0
    private var imageLayout: OpaquePointer?
    private var imageBaselineSerial: UInt32?
    private var imageBaselines: [Double] = []
    isolated deinit { for image in inlineImages { g_object_unref(UnsafeMutableRawPointer(image.paintable)) } }

    override func measure(across: Bool, forSize: Int32) -> Double {
        var minimum: Int32 = 0, natural: Int32 = 0
        gtk_widget_measure(label, across ? GTK_ORIENTATION_HORIZONTAL : GTK_ORIENTATION_VERTICAL,
                           forSize, &minimum, &natural, nil, nil)
        return Double(natural)
    }
    override func allocate(width: Double, height: Double) {
        gtk_widget_allocate(label, Int32(width.rounded(.down)), Int32(height.rounded(.down)), -1, nil)
        if !inlineImages.isEmpty, inlineImageScale != max(gtk_widget_get_scale_factor(widget), 1) {
            rebuildInlineImages()
            writeLook()
        }
        publishTextLayout()
    }
    override func draw(_ snapshot: OpaquePointer, width: Double, height: Double) {
        gtk_widget_snapshot_child(widget, label, snapshot)
        guard !inlineImages.isEmpty, let layout = gtk_label_get_layout(label.opaque) else { return }
        let serial = pango_layout_get_serial(layout)
        if imageLayout != layout || imageBaselineSerial != serial {
            guard let iterator = pango_layout_get_iter(layout) else { return }
            defer { pango_layout_iter_free(iterator) }
            imageBaselines.removeAll(keepingCapacity: true)
            repeat { imageBaselines.append(Double(pango_layout_iter_get_baseline(iterator)) / Double(PANGO_SCALE)) }
            while pango_layout_iter_next_line(iterator) != 0
            imageLayout = layout
            imageBaselineSerial = serial
        }
        var ox: Int32 = 0, oy: Int32 = 0; gtk_label_get_layout_offsets(label.opaque, &ox, &oy)
        for image in inlineImages {
            var rect = PangoRectangle(), line: Int32 = 0, x: Int32 = 0
            pango_layout_index_to_pos(layout, Int32(image.byte), &rect)
            pango_layout_index_to_line_x(layout, Int32(image.byte), 0, &line, &x)
            guard imageBaselines.indices.contains(Int(line)) else { continue }
            var origin = graphene_point_t(x: Float(Double(ox) + Double(min(rect.x, rect.x + rect.width)) / Double(PANGO_SCALE)),
                y: Float(Double(oy) + imageBaselines[Int(line)] - image.size.height - image.baseline))
            gtk_snapshot_save(snapshot); gtk_snapshot_translate(snapshot, &origin)
            if image.source.symbol != nil {
                var tint = GdkRGBA()
                gtk_widget_get_color(label, &tint)
                if let own = image.color.flatMap(GTKBrush.rgba) { tint = own }
                let colors = [tint, tint, tint, tint]
                colors.withUnsafeBufferPointer {
                    gtk_symbolic_paintable_snapshot_symbolic(image.paintable, snapshot, image.size.width, image.size.height,
                                                             $0.baseAddress, gsize($0.count))
                }
            } else {
                gdk_paintable_snapshot(image.paintable, snapshot, image.size.width, image.size.height)
            }
            gtk_snapshot_restore(snapshot)
        }
    }
    private func rebuildInlineImages() {
        let previous = inlineImages; inlineImages = []
        let previousByByte = Dictionary(uniqueKeysWithValues: previous.map { ($0.byte, $0) })
        let scale = max(gtk_widget_get_scale_factor(widget), 1)
        let previousScale = inlineImageScale
        inlineImageScale = scale
        defer { for image in previous { g_object_unref(UnsafeMutableRawPointer(image.paintable)) } }
        var byte: UInt32 = 0
        for run in runs ?? [] {
            defer { byte += UInt32((run.image == nil ? run.text : "\u{FFFC}").utf8.count) }
            guard let source = run.image else { continue }
            let runLook = run.look.over(look)
            let baseline = runLook.baselineOffset ?? 0
            let points = source.symbol == nil ? 0 : runLook.symbolPointSize
            if let old = previousByByte[byte], old.source == source,
               source.symbol == nil || (previousScale == scale && old.size.height == points) {
                _ = g_object_ref(UnsafeMutableRawPointer(old.paintable))
                inlineImages.append(.init(source: source, byte: byte, size: old.size,
                                          baseline: baseline, color: runLook.color, paintable: old.paintable))
                continue
            }
            let paintable: OpaquePointer?
            let size: Size
            if let bitmap = source.bitmap { paintable = GTKMemoryImages.texture(bitmap); size = bitmap.size }
            else if let symbol = source.symbol {
                paintable = GTKSymbols.paintable(of: symbol, size: Int32(points.rounded(.up)), scale: scale)
                if let paintable, gdk_paintable_get_intrinsic_height(paintable) > 0 {
                    let intrinsic = LayoutSize(width: Double(gdk_paintable_get_intrinsic_width(paintable)),
                                               height: Double(gdk_paintable_get_intrinsic_height(paintable)))
                    let measured = PictureArithmetic.glyph(intrinsic, height: points)
                    size = Size(measured.width, measured.height)
                } else { size = Size(points, points) }
            } else if let pixels = GTKPictures.pixels(of: source.file), let bitmap = BitmapImage(pixels: pixels) {
                paintable = GTKMemoryImages.texture(bitmap); size = bitmap.size
            } else { continue }
            if let paintable {
                inlineImages.append(.init(source: source, byte: byte, size: size,
                                          baseline: baseline, color: runLook.color, paintable: paintable))
            }
        }
    }

    /// How the words look.
    private(set) var look = TextLook()

    /// The label's own words, and the runs shown in their place; nil while none are.
    private var ownText = ""
    private var runs: [TextRun]?
    private var fillClass: String?

    /// Where the label's place travels: its words stand at that size meanwhile.
    /// Design: docs/design/host/animation.md#words-at-their-destination
    private var bound: Rect?

    override init() {
        super.init()
        gtk_widget_set_parent(label, widget)
        setLines(breaking: .wordWrap, maximum: nil)
        gtk_label_set_xalign(label.opaque, 0)
        gtk_label_set_yalign(label.opaque, 0)
    }

    /// The label's own words, shown while it shows no runs.
    func setText(_ text: String) {
        guard ownText != text else { return }
        ownText = text
        lastLayoutSerial = nil
        if runs == nil { gtk_label_set_text(label.opaque, text) }
        shownWordsChanged()
    }

    /// Runs of words shown in place of the label's own, each in its own look; nil shows its own words again.
    /// Design: docs/design/platforms/gtk/controls.md#runs-of-words
    func setRuns(_ runs: [TextRun]?) {
        guard self.runs != runs else { return }
        self.runs = runs
        gtk_label_set_text(label.opaque, runs.map { $0.map { $0.image == nil ? $0.text : "\u{FFFC}" }.joined() } ?? ownText)
        rebuildInlineImages()
        writeLook()
        shownWordsChanged()
    }

    override var shownWords: String? { text }

    /// The words the label shows now, read back from GTK.
    var text: String {
        String(cString: gtk_label_get_text(label.opaque))
    }

    /// Changes how the words look.
    func setLook(_ change: (inout TextLook) -> Void) {
        let previous = look
        change(&look)
        guard look != previous else { return }
        if runs?.contains(where: { $0.image != nil }) == true { rebuildInlineImages() }
        writeLook()
    }

    /// Writes the look on the words: the label's over all of them, or each run's over its own bytes.
    private func writeLook() {
        imageBaselineSerial = nil
        lastLayoutSerial = nil
        let list = pango_attr_list_new()!
        if let runs {
            let imagesByByte = Dictionary(uniqueKeysWithValues: inlineImages.map { ($0.byte, $0) })
            var start: UInt32 = 0
            for run in runs {
                let end = start + UInt32((run.image == nil ? run.text : "\u{FFFC}").utf8.count)
                var runLook = run.look.over(look)
                // An image's shape already includes its baseline offset. Applying
                // Pango's rise as well would displace the native line metrics twice.
                if run.image != nil { runLook.baselineOffset = nil }
                runLook.insert(into: list, from: start, to: end)
                if let image = imagesByByte[start] {
                    let scale = Double(PANGO_SCALE)
                    var rect = PangoRectangle(x: 0, y: Int32(((-image.size.height - image.baseline) * scale).rounded()),
                        width: Int32((image.size.width * scale).rounded()), height: Int32((image.size.height * scale).rounded()))
                    if let shape = pango_attr_shape_new(&rect, &rect) {
                        shape.pointee.start_index = start; shape.pointee.end_index = end; pango_attr_list_insert(list, shape)
                    }
                }
                start = end
            }
        } else {
            look.insert(into: list)
        }
        gtk_label_set_attributes(label.opaque, list)
        pango_attr_list_unref(list)
        if let layout = gtk_label_get_layout(label.opaque) {
            let spacing = Int32((look.lineSpacing * Double(PANGO_SCALE)).rounded())
            if pango_layout_get_spacing(layout) != spacing {
                pango_layout_set_spacing(layout, spacing)
                gtk_widget_queue_resize(widget)
            }
        }
    }

    /// How words too long for the width break, and how many lines show before they are cut (`LineBreak.lines`): a
    /// break that cuts them short keeps one line; wrapped words keep to `maximum` - nil or less than one for no
    /// limit - the last cut at its end.
    /// Design: docs/design/platforms/gtk/controls.md#words
    func setLines(breaking: LineBreak, maximum: Int?) {
        imageBaselineSerial = nil
        lastLayoutSerial = nil
        let label = self.label.opaque
        let lines = breaking.lines(maximum: maximum)
        let cut: PangoEllipsizeMode = switch breaking {
        case .noWrap: PANGO_ELLIPSIZE_NONE
        case .wordWrap, .characterWrap: lines == nil ? PANGO_ELLIPSIZE_NONE : PANGO_ELLIPSIZE_END
        case .headTruncation: PANGO_ELLIPSIZE_START
        case .middleTruncation: PANGO_ELLIPSIZE_MIDDLE
        case .tailTruncation: PANGO_ELLIPSIZE_END
        }
        gtk_label_set_wrap(label, breaking.wraps ? 1 : 0)
        gtk_label_set_wrap_mode(label, breaking == .characterWrap ? PANGO_WRAP_CHAR : PANGO_WRAP_WORD_CHAR)
        gtk_label_set_ellipsize(label, cut)
        gtk_label_set_lines(label, breaking.wraps ? Int32(lines ?? -1) : -1)
    }

    /// Whether the user drags a range out of the words and copies it.
    func setSelectable(_ selectable: Bool) {
        gtk_label_set_selectable(label.opaque, selectable ? 1 : 0)
    }

    var onTextLayout: ((TextLayoutReport) -> Void)? {
        didSet {
            lastLayoutSerial = nil
            if onTextLayout != nil { publishTextLayout() }
        }
    }
    private static var pendingTextLayouts: [GTKTextView] = []
    private var textLayoutPending = false
    private var lastLayoutSerial: UInt32?
    private var lastLayout: OpaquePointer?
    private var lastLayoutOrigin: Point?

    func publishTextLayout() {
        guard onTextLayout != nil, !textLayoutPending else { return }
        textLayoutPending = true
        Self.pendingTextLayouts.append(self)
        guard Self.pendingTextLayouts.count == 1 else { return }
        GTKDoorbell.afterLayout {
            let labels = Self.pendingTextLayouts
            Self.pendingTextLayouts = []
            let publish = {
                for label in labels {
                    label.textLayoutPending = false
                    label.reportTextLayout()
                }
            }
            if let runtime = GTKRenderer.shared?.runtime { runtime.performUserTransaction(publish) }
            else { publish() }
        }
    }

    private func reportTextLayout() {
        guard let onTextLayout, gtk_widget_get_width(widget) > 0,
              gtk_widget_get_height(widget) > 0,
              let layout = gtk_label_get_layout(label.opaque) else { return }
        var originX: Int32 = 0, originY: Int32 = 0
        gtk_label_get_layout_offsets(label.opaque, &originX, &originY)
        let serial = pango_layout_get_serial(layout)
        let origin = Point(Double(originX), Double(originY))
        guard layout != lastLayout || serial != lastLayoutSerial || origin != lastLayoutOrigin else { return }
        lastLayout = layout
        lastLayoutSerial = serial
        lastLayoutOrigin = origin
        var byteOffset: Int32 = 0
        var glyphs: [NativeTextLayout.Glyph] = []
        for character in text {
            let string = String(character)
            var native = PangoRectangle()
            pango_layout_index_to_pos(layout, byteOffset, &native)
            var line: Int32 = 0, x: Int32 = 0
            pango_layout_index_to_line_x(layout, byteOffset, 0, &line, &x)
            let scale = Double(PANGO_SCALE)
            let rect = Rect(Double(originX) + Double(min(native.x, native.x + native.width)) / scale,
                            Double(originY) + Double(native.y) / scale,
                            Double(abs(native.width)) / scale, Double(native.height) / scale)
            glyphs.append(.init(text: string, rect: rect, line: Int(line),
                                direction: native.width < 0 ? .rightToLeft : .leftToRight))
            byteOffset += Int32(string.utf8.count)
        }
        onTextLayout(NativeTextLayout.report(glyphs))
    }

    /// Where the lines stand across the label: from its leading edge, in its middle, or at its trailing edge.
    func setAlignment(horizontal: TextAlignment) {
        let (share, justification): (Float, GtkJustification) = switch horizontal {
        case .start: (0, GTK_JUSTIFY_LEFT)
        case .center: (0.5, GTK_JUSTIFY_CENTER)
        case .end: (1, GTK_JUSTIFY_RIGHT)
        }
        gtk_label_set_xalign(label.opaque, share)
        gtk_label_set_justify(label.opaque, justification)
    }

    /// Where the words stand down the label's height.
    func setAlignment(vertical: TextAlignment) {
        gtk_label_set_yalign(label.opaque, vertical == .start ? 0 : vertical == .center ? 0.5 : 1)
    }

    /// Where the label's contents stand inside the bounds its `frame` gave it, across.
    func setContentAlignment(horizontal: AxisAlignment) {
        gtk_label_set_xalign(label.opaque, horizontal == .start ? 0 : horizontal == .end ? 1 : 0.5)
    }

    /// Where the label's contents stand inside the bounds its `frame` gave it, down.
    func setContentAlignment(vertical: AxisAlignment) {
        gtk_label_set_yalign(label.opaque, vertical == .start ? 0 : vertical == .end ? 1 : 0.5)
    }

    override func travels(to destination: Rect?) {
        bound = destination
    }

    override var wordsRoom: Rect? { bound }

    /// What fills the label's box: a colour, or a brush's first colour; nil for nothing.
    func setBackground(_ value: HostValue?) {
        swapClass(&fillClass, to: GTKBrush(value).firstColor.map(GTKStyleSheet.fill))
    }
}
