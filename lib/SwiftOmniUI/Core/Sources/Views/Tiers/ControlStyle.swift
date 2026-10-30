// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// `.buttonStyle`, `.textFieldStyle`, `.pickerStyle`, `.listStyle`: the logical
// look a control wears, mapped on each platform to its own drawing.
// Design: docs/design/types/styles.md

extension View {
    /// The look every `Button` under this view wears - the platform's own
    /// drawing of the kind:
    ///
    ///     Button("Save", action: save)
    ///         .buttonStyle(.borderedProminent)
    ///
    /// Written on the button it shapes, or above the buttons it shapes; the
    /// member written nearest wins.
    public func buttonStyle(_ style: ButtonStyle) -> ModifiedContent {
        environment(style).setting(ButtonContract.buttonStyle, style.kind)
    }

    /// `buttonStyle` from a state, `$x`: the host applies each new kind as it
    /// stands, and no view is rebuilt for it.
    @_disfavoredOverload
    public func buttonStyle(_ state: Binding<ButtonStyleKind>) -> ModifiedContent {
        revised { $0.drivePlain(ButtonContract.buttonStyle, by: state) }
    }

    /// The look every `TextField` under this view wears - the platform's own
    /// box of the kind, or none:
    ///
    ///     TextField("Host", text: $host)
    ///         .textFieldStyle(.roundedBorder)
    public func textFieldStyle(_ style: TextFieldStyle) -> ModifiedContent {
        environment(style).setting(TextFieldContract.textFieldStyle, style.kind)
    }

    /// `textFieldStyle` from a state, `$x`: the host applies each new kind as
    /// it stands, and no view is rebuilt for it.
    @_disfavoredOverload
    public func textFieldStyle(_ state: Binding<TextFieldStyleKind>) -> ModifiedContent {
        revised { $0.drivePlain(TextFieldContract.textFieldStyle, by: state) }
    }

    /// How every `Picker` under this view presents its choices:
    ///
    ///     Picker("Sort", selection: $sort) { … }
    ///         .pickerStyle(.segmented)
    public func pickerStyle(_ style: PickerStyle) -> ModifiedContent {
        environment(style).setting(PickerContract.pickerStyle, style.kind)
    }

    /// `pickerStyle` from a state, `$x`: the host applies each new kind as it
    /// stands, and no view is rebuilt for it.
    @_disfavoredOverload
    public func pickerStyle(_ state: Binding<PickerStyleKind>) -> ModifiedContent {
        revised { $0.drivePlain(PickerContract.pickerStyle, by: state) }
    }

    /// How every `List` under this view draws its rows:
    ///
    ///     List { … }
    ///         .listStyle(.sidebar)
    public func listStyle(_ style: ListStyle) -> ModifiedContent {
        environment(style).setting(ListContract.listStyle, style.kind)
    }

    /// `listStyle` from a state, `$x`: the host applies each new kind as it
    /// stands, and no view is rebuilt for it.
    @_disfavoredOverload
    public func listStyle(_ state: Binding<ListStyleKind>) -> ModifiedContent {
        revised { $0.drivePlain(ListContract.listStyle, by: state) }
    }
}
