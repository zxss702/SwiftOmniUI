// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIGTK

/// A `GtkLabel`: its words, wrapped at the width it is given, from its leading edge, in the look the tree gives them.
/// Design: docs/design/platforms/gtk/controls.md#words
@MainActor
class GTKTextView: GTKView {
    /// How the words look.
    private(set) var look = TextLook()

    /// The label's own words, and the runs shown in their place; nil while none are.
    private var ownText = ""
    private var runs: [TextRun]?
    private var fillClass: String?

    /// Where the label's place travels: its words stand at that size meanwhile.
    /// Design: docs/design/host/animation.md#words-at-their-destination
    private var bound: Rect?

    init() {
        super.init { _ in gtk_label_new(nil) }
        setLines(breaking: .wordWrap, maximum: nil)
        gtk_label_set_xalign(widget.opaque, 0)
        gtk_label_set_yalign(widget.opaque, 0)
    }

    /// The label's own words, shown while it shows no runs.
    func setText(_ text: String) {
        ownText = text
        if runs == nil { gtk_label_set_text(widget.opaque, text) }
        shownWordsChanged()
    }

    /// Runs of words shown in place of the label's own, each in its own look; nil shows its own words again.
    /// Design: docs/design/platforms/gtk/controls.md#runs-of-words
    func setRuns(_ runs: [TextRun]?) {
        self.runs = runs
        gtk_label_set_text(widget.opaque, runs.map { $0.map(\.text).joined() } ?? ownText)
        writeLook()
        shownWordsChanged()
    }

    override var shownWords: String? { text }

    /// The words the label shows now, read back from GTK.
    var text: String {
        String(cString: gtk_label_get_text(widget.opaque))
    }

    /// Changes how the words look.
    func setLook(_ change: (inout TextLook) -> Void) {
        change(&look)
        writeLook()
    }

    /// Writes the look on the words: the label's over all of them, or each run's over its own bytes.
    private func writeLook() {
        let list = pango_attr_list_new()!
        if let runs {
            var start: UInt32 = 0
            for run in runs {
                let end = start + UInt32(run.text.utf8.count)
                run.look.over(look).insert(into: list, from: start, to: end)
                start = end
            }
        } else {
            look.insert(into: list)
        }
        gtk_label_set_attributes(widget.opaque, list)
        pango_attr_list_unref(list)
    }

    /// How words too long for the width break, and how many lines show before they are cut (`LineBreak.lines`): a
    /// break that cuts them short keeps one line; wrapped words keep to `maximum` - nil or less than one for no
    /// limit - the last cut at its end.
    /// Design: docs/design/platforms/gtk/controls.md#words
    func setLines(breaking: LineBreak, maximum: Int?) {
        let label = widget.opaque
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
        gtk_label_set_selectable(widget.opaque, selectable ? 1 : 0)
    }

    var onTextLayout: ((TextLayoutReport) -> Void)? {
        didSet { if onTextLayout != nil { publishTextLayout() } }
    }
    private var textLayoutPending = false
    private var lastLayoutSerial: UInt32?
    private var lastLayoutOrigin: Point?

    func publishTextLayout() {
        guard onTextLayout != nil, !textLayoutPending else { return }
        textLayoutPending = true
        GTKDoorbell.afterLayout { [weak self] in
            guard let self else { return }
            self.textLayoutPending = false
            self.reportTextLayout()
        }
    }

    private func reportTextLayout() {
        guard let onTextLayout, let layout = gtk_label_get_layout(widget.opaque) else { return }
        var originX: Int32 = 0, originY: Int32 = 0
        gtk_label_get_layout_offsets(widget.opaque, &originX, &originY)
        let serial = pango_layout_get_serial(layout)
        let origin = Point(Double(originX), Double(originY))
        guard serial != lastLayoutSerial || origin != lastLayoutOrigin else { return }
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
        gtk_label_set_xalign(widget.opaque, share)
        gtk_label_set_justify(widget.opaque, justification)
    }

    /// Where the words stand down the label's height.
    func setAlignment(vertical: TextAlignment) {
        gtk_label_set_yalign(widget.opaque, vertical == .start ? 0 : vertical == .center ? 0.5 : 1)
    }

    /// Where the label's contents stand inside the bounds its `frame` gave it, across.
    func setContentAlignment(horizontal: AxisAlignment) {
        gtk_label_set_xalign(widget.opaque, horizontal == .start ? 0 : horizontal == .end ? 1 : 0.5)
    }

    /// Where the label's contents stand inside the bounds its `frame` gave it, down.
    func setContentAlignment(vertical: AxisAlignment) {
        gtk_label_set_yalign(widget.opaque, vertical == .start ? 0 : vertical == .end ? 1 : 0.5)
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
