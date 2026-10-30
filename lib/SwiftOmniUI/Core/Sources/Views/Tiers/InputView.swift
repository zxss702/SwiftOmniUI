// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// What `TextField`, `TextEditor` and `SearchField` share: the placeholder
/// and its colour, the keyboard, the caret and selection, the length cap and
/// read-only.
public protocol InputViewProperties: ViewProperties {}

/// A view the user types into.
public protocol InputView: VisualElement, InputViewProperties {}

extension InputView {
    /// Fires on every edit, with the whole of the new text. Runs after a
    /// binding's write, so the state already holds it.
    @_spi(Host) public func onTextChanged(_ handler: @escaping ValueEventHandler<String>) -> Modified {
        onEvent(InputViewContract.textChanged, handler)
    }
}

extension InputViewProperties {
    /// Where the caret sits, counted in characters from the start.
    ///
    /// Typing moves it by itself; write it to put the caret somewhere else,
    /// such as the end of text just filled in. A position past the end lands
    /// at the end.
    @_spi(Host) public func cursorPosition(_ value: Int) -> Modified {
        setValue(InputViewContract.cursorPosition, value)
    }

    /// How many characters from the caret are selected, 0 being none.
    ///
    ///     TextField($name).cursorPosition(0).selectionLength(name.count)
    ///
    /// selects the lot, for a field filled in for the user to replace.
    @_spi(Host) public func selectionLength(_ value: Int) -> Modified {
        setValue(InputViewContract.selectionLength, value)
    }

    /// Whether the platform underlines what it thinks is misspelt.
    ///
    /// Worth turning off for anything that is not prose - a code, a name, a
    /// serial number.
    @_spi(Host) public func isSpellCheckEnabled(_ value: Bool) -> Modified {
        setValue(InputViewContract.isSpellCheckEnabled, value)
    }

    /// Whether the platform offers the next word as the user types.
    ///
    /// Not the same as the spell check, and usually turned off with it and for
    /// the same fields.
    @_spi(Host) public func isTextPredictionEnabled(_ value: Bool) -> Modified {
        setValue(InputViewContract.isTextPredictionEnabled, value)
    }

    /// What the field says while it is empty.
    @_disfavoredOverload @_spi(Host) public func placeholder(_ value: String) -> Modified {
        setValue(InputViewContract.placeholder, value)
    }

    /// What the field says while it is empty, looked up - the caption's key
    /// beside its `displayString` fallback, which the host's answer stands in
    /// for.
    @_spi(Host) public func placeholder(_ key: LocalizedStringKey) -> Modified {
        modified {
            $0.props[InputViewContract.placeholder.token] = key.displayString.propValue
            $0.props[InputViewContract.placeholderKey.token] = key.propValue
        }
    }

    /// The colour of that text.
    @_spi(Host) public func placeholderColor(_ value: Color) -> Modified {
        setValue(InputViewContract.placeholderColor, value)
    }

    /// Whether the text can be selected and copied but not changed - which is
    /// not the same as disabled.
    @_spi(Host) public func isReadOnly(_ value: Bool) -> Modified {
        setValue(InputViewContract.isReadOnly, value)
    }

    /// What the field is for - an email address, a number, a url and the rest -
    /// which picks the keyboard the platform offers.
    public func textContentType(_ value: InputPurpose) -> Modified {
        setValue(InputViewContract.textContentType, value)
    }

    /// How many characters the field accepts.
    @_spi(Host) public func maximumLength(_ value: Int) -> Modified {
        setValue(InputViewContract.maximumLength, value)
    }
}

extension InputView {
    /// `cursorPosition` from a state, `$x`: the host sets each new value as it
    /// stands, and no view is rebuilt for it.
    @_spi(Host) public func cursorPosition(_ state: Binding<Int>) -> Modified {
        plain(InputViewContract.cursorPosition, by: state)
    }

    /// `isReadOnly` from a state, `$x`: the host sets each new value as it
    /// stands, and no view is rebuilt for it.
    @_spi(Host) public func isReadOnly(_ state: Binding<Bool>) -> Modified {
        plain(InputViewContract.isReadOnly, by: state)
    }

    /// `isSpellCheckEnabled` from a state, `$x`: the host sets each new value
    /// as it stands, and no view is rebuilt for it.
    @_spi(Host) public func isSpellCheckEnabled(_ state: Binding<Bool>) -> Modified {
        plain(InputViewContract.isSpellCheckEnabled, by: state)
    }

    /// `isTextPredictionEnabled` from a state, `$x`: the host sets each new
    /// value as it stands, and no view is rebuilt for it.
    @_spi(Host) public func isTextPredictionEnabled(_ state: Binding<Bool>) -> Modified {
        plain(InputViewContract.isTextPredictionEnabled, by: state)
    }

    /// `textContentType` from a state, `$x`: the host sets each new value as it
    /// stands, and no view is rebuilt for it.
    public func textContentType(_ state: Binding<InputPurpose>) -> Modified {
        plain(InputViewContract.textContentType, by: state)
    }

    /// `maximumLength` from a state, `$x`: the host sets each new value as it
    /// stands, and no view is rebuilt for it.
    @_spi(Host) public func maximumLength(_ state: Binding<Int>) -> Modified {
        plain(InputViewContract.maximumLength, by: state)
    }

    /// `placeholder` from a state, `$x`: the host writes each new text, and no
    /// view is rebuilt for it.
    @_spi(Host) public func placeholder(_ state: Binding<String>) -> Modified {
        words(InputViewContract.placeholder, by: state)
    }

    /// `placeholderColor` from a state, `$x`: the host animates the property to
    /// each new value, and no view is rebuilt for it.
    @_spi(Host) public func placeholderColor(_ state: Binding<Color>) -> Modified {
        journey(InputViewContract.placeholderColor, by: state)
    }

    /// `selectionLength` from a state, `$x`: the host sets each new value as it
    /// stands, and no view is rebuilt for it.
    @_spi(Host) public func selectionLength(_ state: Binding<Int>) -> Modified {
        plain(InputViewContract.selectionLength, by: state)
    }
}
