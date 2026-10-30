// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The focus as a piece of state: which view holds it, read and written.
// `@FocusState` pairs with `.focused(_:)` - a Bool for one view, an optional
// for one of several.
// Design: docs/design/core/acts.md#focus-and-the-keyboard

/// Whether a view holds the keyboard focus, kept as state - writing it asks
/// the platform to move the focus, the platform's move writes it.
///
///     @FocusState private var focused: Bool
///
///     TextField($name)
///         .focused($focused)
///
/// The state reads the focus and writes it; `.focused` is what carries the
/// writes to the element.
@propertyWrapper
public struct FocusState<Value: Hashable> {
    /// The focus, as state.
    @State private var value: Value

    /// Whether the view holds the focus - or which of several does, for an
    /// optional `Value`.
    public var wrappedValue: Value {
        get { value }
        nonmutating set { value = newValue }
    }

    /// The binding `.focused(_:)` takes: `$focused`.
    public var projectedValue: Binding<Value> { $value }

    /// Whether this one view holds the focus - `@FocusState var focused: Bool`.
    public init() where Value == Bool {
        _value = State(wrappedValue: false)
    }

    /// Which of several views holds it - `@FocusState var field: Field?`, nil
    /// while none does.
    public init<T>() where Value == T? {
        _value = State(wrappedValue: nil)
    }
}
