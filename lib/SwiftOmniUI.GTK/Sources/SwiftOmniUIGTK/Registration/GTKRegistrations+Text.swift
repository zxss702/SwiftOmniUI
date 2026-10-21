// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

extension GTKRegistrations {
    /// A Text: a `GtkLabel` - its words, how they break and stand across and down it, the space between the
    /// letters and the lines, and what fills its box.
    static func text(_ registry: Registry<GTKView>) {
        registry.add(TextContract.self, create: { _ in GTKLabelView() }) { label in
            label.applies(TextMembers.members) { view, values in applyText(view, values) }
            label.applies([TextContract.lineBreak, TextContract.lineLimit]) { view, values in
                view.setLines(
                    breaking: values[TextContract.lineBreak] ?? .wordWrap,
                    maximum: values[TextContract.lineLimit])
            }
            label.property(TextContract.selectable) { view, selectable in
                view.setSelectable(selectable ?? false)
            }
            label.property(TextAlignmentElementContract.multilineTextAlignment) { view, alignment in
                view.setAlignment(horizontal: alignment ?? .start)
            }
            label.property(TextAlignmentElementContract.verticalTextAlignment) { view, alignment in
                view.setAlignment(vertical: alignment ?? .start)
            }
            label.property(ViewContract.horizontalContentAlignment) { view, alignment in
                if let alignment { view.setContentAlignment(horizontal: alignment) }
            }
            label.property(ViewContract.verticalContentAlignment) { view, alignment in
                if let alignment { view.setContentAlignment(vertical: alignment) }
            }
            label.property(VisualElementContract.background) { view, background in
                view.setBackground(background?.propValue)
            }
            label.property(TextStyleElementContract.characterSpacing) { view, spacing in
                view.setLook { $0.letterSpacing = spacing ?? 0 }
            }
            label.property(LineHeightElementContract.lineHeight) { view, height in
                view.setLook { $0.lineHeight = height }
            }
            label.property(LineHeightElementContract.lineSpacing) { view, spacing in
                view.setLook { $0.lineSpacing = spacing ?? 0 }
            }
            label.property(DecorableTextElementContract.textDecorations) { view, decorations in
                view.setLook { $0.decorations = decorations ?? .none }
            }
        }
    }

    /// Puts the text tiers' members (`TextMembers`) on a label, a button or a radio button: the words in their case,
    /// the font and the colour, and the room around them.
    static func applyText<Realized: ElementContract>(_ view: any GTKWordsView, _ values: ElementValues<Realized>) {
        if let words = TextMembers.words(values) { view.setText(words) }
        if let look = TextMembers.look(values) {
            view.setLook { shown in
                shown.size = look.size
                shown.attributes = look.attributes
                shown.family = look.family
                shown.textStyle = look.textStyle
                shown.weight = look.weight
                shown.design = look.design
                shown.color = look.color
            }
        }
        if values.changed(PaddingElementContract.contentPadding) {
            view.setPadding(values[PaddingElementContract.contentPadding])
        }
    }
}
