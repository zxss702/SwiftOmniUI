// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

extension WinUIRegistrations {
    /// A Text: a `TextBlock` in a `Border` - its words, how they break and stand across it and down it, the space
    /// between the letters and the lines, and what it is drawn over.
    static func text(_ registry: Registry<WinUIView>) {
        registry.add(TextContract.self, create: { _ in WinUILabelView() }) { label in
            label.applies(TextMembers.members) { view, values in applyText(view, values) }
            label.property(TextContract.selectable) { view, selectable in
                view.setSelectable(selectable ?? false)
            }
            label.applies([TextContract.lineBreak, TextContract.lineLimit]) { view, values in
                view.setLines(
                    breaking: values[TextContract.lineBreak] ?? .wordWrap,
                    maximum: values[TextContract.lineLimit])
            }
            label.property(TextAlignmentElementContract.multilineTextAlignment) { view, alignment in
                view.setAlignment(horizontal: alignment ?? .start)
            }
            label.property(TextAlignmentElementContract.verticalTextAlignment) { view, alignment in
                view.setVerticalAlignment(alignment ?? .start)
            }
            label.property(ViewContract.horizontalContentAlignment) { view, alignment in
                if let alignment { view.setAlignment(horizontal: .init(rawValue: alignment.rawValue) ?? .center) }
            }
            label.property(ViewContract.verticalContentAlignment) { view, alignment in
                if let alignment { view.setVerticalAlignment(.init(rawValue: alignment.rawValue) ?? .center) }
            }
            label.property(VisualElementContract.background) { view, background in
                view.setBackground(background?.propValue)
            }
            label.property(TextStyleElementContract.characterSpacing) { view, spacing in
                view.setLetterSpacing(spacing ?? 0)
            }
            label.property(LineHeightElementContract.lineHeight) { view, height in view.setLineHeight(height) }
            label.property(LineHeightElementContract.lineSpacing) { view, spacing in view.setLineSpacing(spacing ?? 0) }
            label.property(DecorableTextElementContract.textDecorations) { view, decorations in
                view.setDecorations(decorations)
            }
        }
    }

    /// Puts the text tiers' members (`TextMembers`) on a label, a button or a radio button: the words in their case,
    /// the font and the colour, and the room around them.
    static func applyText<Realized: ElementContract>(_ view: WinUIView, _ values: ElementValues<Realized>) {
        if let words = TextMembers.words(values) { (view as? WinUIWordsView)?.setText(words) }
        let fontChanged = values.changed(FontElementContract.fontSize)
            || values.changed(FontElementContract.fontAttributes)
            || values.changed(FontElementContract.fontFamily)
            || values.changed(FontElementContract.fontTextStyle)
            || values.changed(FontElementContract.fontWeight)
            || values.changed(FontElementContract.fontDesign)
        if fontChanged {
            let look = TextMembers.look(of: values)
            if let text = view as? WinUITextView {
                text.setTextFont(look)
            } else {
                view.setFont(size: look.size, attributes: look.attributes, family: look.winUIFontFamily,
                             textStyle: look.textStyle, weight: look.weight)
            }
        }
        if values.changed(TextStyleElementContract.foregroundStyle) {
            view.setForeground(values[TextStyleElementContract.foregroundStyle]?.propValue)
        }
        if values.changed(PaddingElementContract.contentPadding) {
            view.setPadding(values[PaddingElementContract.contentPadding])
        }
    }
}
