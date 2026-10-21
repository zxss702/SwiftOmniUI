// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// A WinUI `TextBlock`: its words, how they break and stand, and the space between the letters and the lines.
/// Design: docs/design/platforms/winui/controls.md#words
@MainActor
class WinUITextView: WinUIView {
    override func measure(width: Double?, height: Double?) -> LayoutSize {
        var measured = super.measure(width: width, height: height)
        if measured.width == 0 {
            let whitespace = swiftomniui_winui_text_whitespace_width(handle)
            if whitespace > 0 { measured.width = min(whitespace, width ?? .infinity) }
        }
        return measured
    }

    override func firstTextBaseline(in size: LayoutSize) -> Double? {
        let baseline = swiftomniui_winui_text_baseline(handle, size.height)
        return baseline >= 0 ? baseline : nil
    }

    override var takesDirection: Bool { true }

    /// The font's size, the space between the letters and the height of a line - what the spacing is measured
    /// against, and what it is.
    private(set) var look = TextLook()

    /// Where the view's place is bound while it travels; nil where it stands.
    private var bound: Rect?
    private var loadedMeasurePending = false
    private var attachmentGeneration = 0
    private var measuredAttachmentGeneration = -1
    private static var loadedMeasurements: [WinUITextView] = []
    private static var loadedMeasurementsPending = false

    /// The size WinUI draws body text at, in DIPs.
    static let platformFontSize = 14.0

    /// How much taller than its size a line of Segoe UI stands.
    static let lineHeightOfFont = 4.0 / 3.0

    init() {
        super.init { _ in swiftomniui_winui_text_make() }
        swiftomniui_winui_text_on_loaded(handle, number) { number in
            MainActor.assumeIsolated {
                guard let text = WinUIView.find(number) as? WinUITextView else { return }
                text.nativeTextLoaded()
            }
        }
    }

    /// The pre-attachment measurement can differ once XAML has its root's
    /// resources. Loaded callbacks for one attachment share a pass, while a
    /// later attachment gets a fresh comparison against its current proposals.
    func nativeTextLoaded() {
        invalidateTextLayout()
        attachmentGeneration &+= 1
        guard !loadedMeasurePending else { return }
        loadedMeasurePending = true
        Self.loadedMeasurements.append(self)
        guard !Self.loadedMeasurementsPending else { return }
        Self.loadedMeasurementsPending = true
        WinUIDoorbell.afterPass {
            let labels = Self.loadedMeasurements
            Self.loadedMeasurements = []
            Self.loadedMeasurementsPending = false
            var changedLayouts: [WinUIView] = []
            for label in labels {
                label.loadedMeasurePending = false
                guard !label.isDetached, label.isAttached,
                      label.sourceElement?.isDeparting != true,
                      label.measuredAttachmentGeneration != label.attachmentGeneration else { continue }
                label.measuredAttachmentGeneration = label.attachmentGeneration
                if label.refreshMeasurementsAfterAttachment(),
                   let layout: WinUIView = label.placingLayout ?? label.nativeContentOwner {
                    changedLayouts.append(layout)
                }
            }
            WinUILayoutView.commitAttachedTextMeasurements(changedLayouts)
        }
    }

    var onTextLayout: ((TextLayoutReport) -> Void)? {
        didSet { if onTextLayout != nil { requestTextLayout() } }
    }
    private var textLayoutPending = false
    private var lastTextLayoutSize: LayoutSize?
    private var textLayoutDirty = true
    private var textLayoutAwaitingNative = false

    func invalidateTextLayout() { textLayoutDirty = true; requestTextLayout() }

    override func commitGeometry(in bounds: Rect) {
        super.commitGeometry(in: bounds)
        let size = LayoutSize(width: bounds.width, height: bounds.height)
        if size != lastTextLayoutSize { textLayoutDirty = true }
        requestTextLayout()
    }

    func requestTextLayout() {
        guard onTextLayout != nil, textLayoutDirty, !textLayoutPending else { return }
        textLayoutPending = true
        Self.pendingTextLayouts.append(self)
        guard Self.pendingTextLayouts.count == 1 else { return }
        WinUIDoorbell.afterPass {
            let labels = Self.pendingTextLayouts
            Self.pendingTextLayouts = []
            let publish = {
                for label in labels {
                    label.textLayoutPending = false
                    label.publishTextLayout()
                }
            }
            if let runtime = WinUIRenderer.shared?.runtime { runtime.performUserTransaction(publish) }
            else { publish() }
        }
    }

    private static var pendingTextLayouts: [WinUITextView] = []

    private func publishTextLayout() {
        guard let report = onTextLayout, textLayoutDirty, isAttached else { return }
        let text = self.text
        let count = text.utf16.count
        guard count > 0 else {
            textLayoutDirty = false
            report(TextLayoutReport(lines: [])); return
        }
        var rectangles = [Double](repeating: 0, count: count * 4)
        guard swiftomniui_winui_text_character_rects(handle, &rectangles, Int32(count)) == count,
              stride(from: 3, to: rectangles.count, by: 4).contains(where: { rectangles[$0] > 0 }) else {
            awaitNativeTextLayout()
            return
        }
        textLayoutDirty = false
        lastTextLayoutSize = LayoutSize(width: laidOutFrame.width, height: laidOutFrame.height)
        var offset = 0, line = 0
        var last: Rect?
        var glyphs: [NativeTextLayout.Glyph] = []
        for character in text {
            let string = String(character)
            let start = offset
            let n = string.utf16.count
            offset += n
            var rect = Rect(rectangles[start * 4], rectangles[start * 4 + 1],
                            rectangles[start * 4 + 2], rectangles[start * 4 + 3])
            for index in (start + 1)..<offset {
                let r = Rect(rectangles[index * 4], rectangles[index * 4 + 1],
                             rectangles[index * 4 + 2], rectangles[index * 4 + 3])
                if r.height > 0 { rect = NativeTextLayout.union(rect, r) }
            }
            guard rect.height > 0 else { continue }
            if let previous = last,
               rect.y >= previous.y + previous.height - 0.5 || rect.y + rect.height <= previous.y + 0.5 { line += 1 }
            glyphs.append(.init(text: string, rect: rect, line: line))
            last = rect
        }
        report(NativeTextLayout.report(glyphs))
    }

    private func awaitNativeTextLayout() {
        guard !textLayoutAwaitingNative else { return }
        textLayoutAwaitingNative = true
        swiftomniui_winui_text_after_layout(handle, number) { number in
            MainActor.assumeIsolated {
                guard let text = WinUIView.find(number) as? WinUITextView else { return }
                text.textLayoutAwaitingNative = false
                text.requestTextLayout()
            }
        }
    }

    /// The words shown.
    func setSelectable(_ selectable: Bool) {
        swiftomniui_winui_text_set_selectable(handle, selectable)
    }

    /// The words shown.
    func setText(_ text: String) {
        swiftomniui_winui_text_set_text(handle, text)
        invalidateTextLayout()
    }

    /// The words the element shows now, read back from WinUI.
    var text: String {
        WinUIView.words(of: handle)
    }

    /// The font, remembering its size for the spacing measured against it.
    func setTextFont(size: Double?, attributes: FontAttributes?, family: String?) {
        var font = TextLook()
        font.size = size
        font.attributes = attributes ?? .none
        font.family = family
        setTextFont(font)
    }

    func setTextFont(_ font: TextLook) {
        setFont(size: font.size, attributes: font.attributes, family: font.family,
                textStyle: font.textStyle, weight: font.weight)
        look.size = wordsStyle.size
        look.attributes = font.attributes
        look.family = font.family
        look.textStyle = font.textStyle
        look.weight = font.weight
        look.design = font.design
        writeSpacing()
    }

    /// How the words break - wrapped, on one line, or cut short - and the most lines; nil for any
    /// (`LineBreak.lines`).
    func setLines(breaking: LineBreak, maximum: Int?) {
        let lines = breaking.lines(maximum: maximum)
        // MaxLines alone clips. A bounded wrapped label must also ask XAML
        // to indicate omitted text; an unlimited wrapped label stays untrimmed.
        let trims = breaking.truncates || (breaking.wraps && lines != nil)
        swiftomniui_winui_text_set_lines(
            handle, breaking.wraps, Int32(lines ?? 0), trims)
        invalidateTextLayout()
    }

    /// Where the words stand across the label.
    func setAlignment(horizontal: TextAlignment) {
        swiftomniui_winui_text_set_alignment(handle, horizontal.rawValue)
        invalidateTextLayout()
    }

    /// The space between the letters, in DIPs.
    func setLetterSpacing(_ points: Double) {
        look.letterSpacing = points
        writeSpacing()
    }

    /// The height of a line, as a multiple of the font's own; nil for the font's.
    func setLineHeight(_ multiple: Double?) {
        look.lineHeight = multiple.flatMap { $0 > 0 ? $0 : nil }
        writeSpacing()
    }

    func setLineSpacing(_ spacing: Double) {
        guard look.lineSpacing != spacing else { return }
        look.lineSpacing = spacing
        writeSpacing()
    }

    /// A line under the words, or through them.
    func setDecorations(_ decorations: TextDecorations?) {
        swiftomniui_winui_text_set_decorations(
            handle, decorations?.contains(.underline) == true, decorations?.contains(.strikethrough) == true)
    }

    /// The words stand at the size the place is bound for, whole, while the place travels.
    /// Design: docs/design/host/animation.md#words-at-their-destination
    override func travels(to destination: Rect?) {
        bound = destination
    }

    override var wordsRoom: Rect? { bound }

    /// Animated text wraps at its destination throughout the motion. That is
    /// a text-content proposal, independent of the parent's presentation slot;
    /// native containers do not use this exception to remeasure their subtree.
    override func prepareAllocation(in bounds: Rect) {
        guard let bound else { return }
        prepareMeasure(width: bound.width, height: bound.height)
    }

    /// WinUI spaces letters in thousandths of an em and lines in DIPs: both measured against the font's size.
    private func writeSpacing() {
        let size = look.size ?? Self.platformFontSize
        let thousandths = Int32((look.letterSpacing(inEmsOf: size) * 1000).rounded())
        let natural = look.lineHeight != nil || look.lineSpacing != 0
            ? swiftomniui_winui_text_natural_line_height(handle) : 0
        let line = natural > 0 ? max(0, natural * (look.lineHeight ?? 1) + look.lineSpacing) : 0
        swiftomniui_winui_text_set_spacing(handle, thousandths, line)
        invalidateTextLayout()
    }
}

extension WinUIView {
    /// The words a text block or a button's caption shows now, read back from WinUI.
    static func words(of handle: SwiftOmniUIObjectRef) -> String {
        let length = Int(swiftomniui_winui_text(handle, nil, 0))
        var bytes = [CChar](repeating: 0, count: length + 1)
        _ = swiftomniui_winui_text(handle, &bytes, Int32(bytes.count))
        return String(decoding: bytes.prefix(length).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
