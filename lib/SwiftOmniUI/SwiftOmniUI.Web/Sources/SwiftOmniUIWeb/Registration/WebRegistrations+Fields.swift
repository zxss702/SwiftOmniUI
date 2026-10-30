// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

extension WebRegistrations {
    /// A TextField, a SearchField and a TextEditor: their words are `TextElementContract.text` and the change they
    /// report is `InputViewContract.textChanged`. Each member reaches the view only where the tree changed it, which
    /// keeps the user's typing and caret their own.
    static func fields(_ registry: Registry<WebDOMView>) {
        registry.add(TextFieldContract.self, create: { reports in
            let field = WebTextInputView(.field)
            hearInput(field, reports)
            field.onSubmitted = { reports.raise(TextFieldContract.submitted) }
            return field
        }, members: { field in
            field.applies(inputMembers) { view, values in applyInput(view, values) }
            field.property(TextFieldContract.isPassword) { view, hidden in view.setPassword(hidden ?? false) }
            field.property(TextFieldContract.submitLabel) { view, label in
                view.setSubmitLabel(InputTraits.submitLabel(label, searching: false))
            }
            field.raises(InputViewContract.textChanged)
            field.raises(TextFieldContract.submitted)
        })
        registry.add(SearchFieldContract.self, create: { reports in
            let search = WebTextInputView(.search)
            hearInput(search, reports)
            search.onSubmitted = { reports.raise(SearchFieldContract.submitted) }
            search.setSubmitLabel(InputTraits.submitLabel(nil, searching: true))
            return search
        }, members: { search in
            search.applies(inputMembers) { view, values in applyInput(view, values) }
            search.property(SearchFieldContract.submitLabel) { view, label in
                view.setSubmitLabel(InputTraits.submitLabel(label, searching: true))
            }
            search.raises(InputViewContract.textChanged)
            search.raises(SearchFieldContract.submitted)
        })
        registry.add(TextEditorContract.self, create: { reports in
            let editor = WebTextInputView(.editor)
            hearInput(editor, reports)
            return editor
        }, members: { editor in
            editor.applies(inputMembers) { view, values in applyInput(view, values) }
            editor.property(TextEditorContract.growsWithText) { view, grows in view.setGrowsWithText(grows ?? false) }
            editor.raises(InputViewContract.textChanged)
        })
    }

    private static func hearInput<Realized: ElementContract>(_ view: WebTextInputView, _ reports: Reports<Realized>) {
        view.onTextChanged = { typed in reports.report(TextElementContract.text, typed, as: InputViewContract.textChanged) }
    }

    /// What every view the user types in takes: its words, their bound and what shows while they are none, whether
    /// and how it takes them, their look and where they stand, and the caret and the selection.
    private static let inputMembers: [any ContractMember] = [
        TextElementContract.text, TextElementContract.textCase, InputViewContract.placeholder,
        InputViewContract.maximumLength,
        VisualElementContract.isEnabled, InputViewContract.isReadOnly, InputViewContract.isSpellCheckEnabled,
        InputViewContract.isTextPredictionEnabled, InputViewContract.textContentType, FontElementContract.fontSize,
        FontElementContract.fontAttributes, FontElementContract.fontFamily, TextStyleElementContract.foregroundStyle,
        InputViewContract.placeholderColor, TextAlignmentElementContract.multilineTextAlignment,
        InputViewContract.cursorPosition, InputViewContract.selectionLength,
    ]

    private static func applyInput<Realized: ElementContract>(_ view: WebTextInputView, _ values: ElementValues<Realized>) {
        if values.changed(InputViewContract.maximumLength) {
            view.setMaximumLength(values[InputViewContract.maximumLength].flatMap { $0 > 0 ? $0 : nil })
        }
        if values.changed(TextElementContract.text) || values.changed(TextElementContract.textCase) {
            let textCase = values[TextElementContract.textCase] ?? .none
            view.setText(textCase.applied(to: values[TextElementContract.text] ?? ""))
        }
        if values.changed(InputViewContract.placeholder) { view.setPlaceholder(values[InputViewContract.placeholder]) }
        if values.changed(VisualElementContract.isEnabled) {
            view.setEnabled(values[VisualElementContract.isEnabled] ?? true)
        }
        if values.changed(InputViewContract.isReadOnly) {
            view.setReadOnly(values[InputViewContract.isReadOnly] ?? false)
        }
        if let traits = InputTraits.changed(values) { view.setTraits(traits) }
        if let look = TextMembers.look(values) { view.setLook(look) }
        if values.changed(InputViewContract.placeholderColor) {
            view.setPlaceholderColor(values[InputViewContract.placeholderColor]?.propValue)
        }
        if values.changed(TextAlignmentElementContract.multilineTextAlignment) {
            view.setAlignment(values[TextAlignmentElementContract.multilineTextAlignment] ?? .start)
        }
        if values.changed(InputViewContract.cursorPosition) || values.changed(InputViewContract.selectionLength),
           let caret = values[InputViewContract.cursorPosition] {
            view.select(start: caret, length: values[InputViewContract.selectionLength] ?? 0)
        }
    }
}
