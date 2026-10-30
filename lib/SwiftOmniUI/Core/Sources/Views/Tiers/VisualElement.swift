// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// A control backed by a node, and drawn - the tier every self-rendering view
/// conforms through.
@preconcurrency @MainActor public protocol VisualElement: ModifiableElement, ViewProperties, View {}

/// The properties every drawn control has: the value half of
/// `VisualElement`, shared by the control and its `Style`.
@preconcurrency @MainActor public protocol VisualElementProperties: PropertyContainer {}

extension VisualElement {
    /// Who this control is among its siblings: its key across renders.
    ///
    /// An `.id()` written on the view wins over the one `ForEach` gives. Any
    /// `Hashable` is a key - a string, a number, a UUID, the author's own enum
    /// or struct - compared as `String(describing:)`: a description that says
    /// less than the value gives two values one key, and a class is keyed by
    /// something it holds (`.id(file.path)`).
    ///
    /// - Parameter value: who this view is - distinct among its siblings and
    ///   the same across renders.
    public func id(_ value: some Hashable) -> Modified {
        modified { $0.id = String(describing: value) }
    }

    /// Puts an aim on this control, which is how an act reaches it.
    ///
    ///     @Aim(TextField.self) private var field
    ///
    ///     TextField($address).aim(field)
    ///     Button("Edit").onClicked { try await field.focus() }
    ///
    /// A model may declare its aims beside its state. An aim is not a key: a
    /// view carrying only an aim is still matched by where it was written, so
    /// rows keep wanting `.id()`, and the two compose - `.id("row-7").aim(row)`.
    /// On a composed view, write it directly on the initializer's result.
    ///
    /// - Parameter aim: the aim the control answers to.
    public func aim(_ aim: Aim<Self>) -> Modified {
        modified { $0.modifyControl { $0.aim = aim.box } }
    }

    /// The keyed style from the application's style sheet that this view wears.
    ///
    ///     Text("Welcome").style("Headline")
    ///
    /// A style without a key applies to every control of its type by itself.
    public func style(_ key: String) -> Modified {
        modified { $0.modifyControl { $0.write(VisualElementContract.style, Name(key)) } }
    }
}

extension View {
    /// Puts an aim on this view, landing on the root of what it is made of -
    /// how an act reaches a composed view.
    ///
    /// - Parameter aim: the aim the view answers to.
    @_disfavoredOverload
    public func aim(_ aim: Aim<Self>) -> ModifiedContent {
        revised { $0.aim = aim.box }
    }
}
