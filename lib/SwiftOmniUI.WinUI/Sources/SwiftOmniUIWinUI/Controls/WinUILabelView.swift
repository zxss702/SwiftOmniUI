// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// A Text: a native `TextBlock`, or a `RichTextBlock` paragraph when it contains inline images/baseline offsets,
/// standing in a `Border` which supplies its background and vertical alignment.
/// Design: docs/design/platforms/winui/controls.md#runs-of-words
@MainActor
final class WinUILabelView: WinUITextView {
    /// The label's own words, and the runs shown in their place; nil while it shows its own.
    private var ownText = ""
    private var runs: [TextRun]?
    private var runsLook: TextLook?

    override func setText(_ text: String) {
        ownText = text
        if runs == nil { super.setText(text) }
    }

    override var text: String {
        runs.map { $0.map { $0.image == nil ? $0.text : "\u{FFFC}" }.joined() } ?? ownText
    }

    /// What the label is drawn over: a colour, a gradient, or nothing.
    func setBackground(_ value: HostValue?) {
        let brush = WinUIBrush(value)
        paint("background", followsSize: brush.followsSize) { [handle] size in
            brush.withRelayBrush(over: size) { swiftomniui_winui_text_set_background(handle, $0) }
        }
    }

    /// Where the words stand across the label's height.
    func setVerticalAlignment(_ alignment: TextAlignment) {
        swiftomniui_winui_text_set_vertical(handle, alignment.rawValue)
    }

    /// Runs of words shown in place of the label's own (`MountedElement.textRuns`), each in its own look over the
    /// label's; nil shows its own words again.
    func setRuns(_ runs: [TextRun]?) {
        let lookChanged = runsLook != look
        guard self.runs != runs || (runs != nil && lookChanged) else { return }
        let paintOnly = !lookChanged && Self.onlyRunPaintChanged(from: self.runs, to: runs)
        self.runs = runs
        invalidateTextLayout()
        runsLook = look
        guard let runs else {
            super.setText(ownText)
            invalidateMeasure()
            return
        }

        var repainted = false
        WinUIStrings.withCStrings(runs.map(\.text)) { texts in
            WinUIStrings.withCStrings(runs.map { $0.look.winUIFontFamily ?? "" }) { families in
                WinUIStrings.withCStrings(runs.map { run in
                    guard let source = run.image, source.symbol == nil else { return "" }
                    if source.bitmap != nil { return "@memory" }
                    return PictureArithmetic.files(for: source.file).joined(separator: "\n")
                }) { images in
                    WinUIStrings.withCStrings(runs.map { $0.image?.symbol ?? "" }) { glyphs in
                    let words = runs.indices.map { index in
                        let run = runs[index]
                        let look = run.look
                        let color = look.color?.argb
                        let background = look.background?.argb
                        // The space between the letters in ems of the run's own size, its label's where it says none.
                        let shown = look.over(self.look)
                        let spacing = shown.letterSpacing(inEmsOf: shown.size ?? Self.platformFontSize)
                        return SwiftOmniUIWordsRun(
                            text: texts[index], color: color ?? 0, background: background ?? 0, size: look.size ?? 0,
                            hasColor: color != nil, hasBackground: background != nil,
                            bold: look.attributes.contains(.bold), italic: look.attributes.contains(.italic),
                            underline: look.decorations.contains(.underline),
                            strikethrough: look.decorations.contains(.strikethrough), family: families[index],
                            spacing: Int32((spacing * 1000).rounded()),
                            baseline: look.baselineOffset ?? 0, image: images[index],
                            glyph: glyphs[index])
                    }
                    if paintOnly {
                        repainted = swiftomniui_winui_text_recolor_runs(handle, words, Int32(words.count))
                    }
                    if !repainted { swiftomniui_winui_text_set_runs(handle, words, Int32(words.count)) }
                    }
                }
            }
        }
        if !repainted {
            for (index, run) in runs.enumerated() {
                guard let bitmap = run.image?.bitmap else { continue }
                swiftomniui_winui_text_set_run_pixels(handle, Int32(index), bitmap.pixels.rgba,
                    Int32(bitmap.pixels.width), Int32(bitmap.pixels.height), bitmap.size.width, bitmap.size.height)
            }
            invalidateMeasure()
        }
    }

    /// Native Run objects can retain their text layout when just their paint
    /// changes. A different image, baseline, font or spacing takes the full path.
    private static func onlyRunPaintChanged(from previous: [TextRun]?, to next: [TextRun]?) -> Bool {
        guard let previous, let next, previous.count == next.count else { return false }
        return zip(previous, next).allSatisfy { before, after in
            guard before.text == after.text, before.image == after.image else { return false }
            var old = before.look, new = after.look
            old.color = nil; new.color = nil
            old.background = nil; new.background = nil
            return old == new
        }
    }
}
