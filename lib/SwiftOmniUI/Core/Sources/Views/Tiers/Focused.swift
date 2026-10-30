// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The keyboard focus as a two-way binding: heard off the element and asked of it.
// Design: docs/design/core/acts.md#focus-and-the-keyboard

extension View {
    /// Whether this view holds the keyboard focus, both ways.
    ///
    ///     @State private var editing = false
    ///
    ///     TextField($name)
    ///         .focused($editing)
    ///
    /// The platform's move of the focus writes `editing`, and writing it asks
    /// the platform to move the focus here - or off it - through the `focus`
    /// and `unfocus` acts. A write that changes nothing asks for nothing, and
    /// asking the focus of a view no longer on screen is dropped rather than
    /// reported: by the time the ask lands, the answer would be stale anyway.
    ///
    /// An `.aim` of the author's wins where the two are written on one view:
    /// the binding still reports, but a write cannot be aimed after the aim
    /// was given to somebody else.
    public func focused(_ condition: Binding<Bool>) -> ModifiedContent {
        let aim = AimBox()
        return revised { $0.aim = $0.aim ?? aim }
            .hearing(VisualElementContract.isFocusedChanged) { focused in
                condition.wrappedValue = focused
            }
            .onChange(of: condition.wrappedValue) { _, focused in
                guard let target = try? aim.target else { return }
                do {
                    if focused {
                        _ = try await Renderer.shared.call(VisualElementContract.focus.token, [target])
                    } else {
                        _ = try await Renderer.shared.call(VisualElementContract.unfocus.token, [target])
                    }
                } catch {}
            }
    }
}

extension View {
    /// Whether this view holds the keyboard focus, of several that can -
    /// the state's value where this view is the focused one:
    ///
    ///     @FocusState private var field: Field?
    ///
    ///     TextField("Name", text: $name)
    ///         .focused($field, equals: .name)
    ///
    /// The platform's move writes `field`, and writing it moves the focus -
    /// to this view for `.name`, off it for another value or `nil`.
    public func focused<Value: Hashable>(
        _ condition: Binding<Value?>, equals value: Value
    ) -> ModifiedContent {
        focused(Binding<Bool>(
            get: { condition.wrappedValue == value },
            set: { focused in
                if focused {
                    condition.wrappedValue = value
                } else if condition.wrappedValue == value {
                    condition.wrappedValue = nil
                }
            }))
    }
}

/// How urgent a `defaultFocus` ask is - SwiftUI's `FocusPriority`.
public enum FocusPriority: Sendable {
    /// The ordinary ask.
    case automatic

    /// The user's own ask.
    case userInitiated

    /// The scene's fallback, behind any other ask.
    case sceneDefault
}

extension View {
    /// The view the scene's keyboard focus opens on: the binding's value where
    /// the focus stands unclaimed when this element first stands.
    ///
    ///     @FocusState private var editing = false
    ///
    ///     Editor()
    ///         .focused($editing)
    ///         .defaultFocus($editing, true)
    ///
    /// A claim standing already - the user having focused something first -
    /// keeps it. Where several views ask, the last to stand wins.
    ///
    /// - Parameters:
    ///   - condition: the focus as `FocusState`'s binding.
    ///   - value: the value this view holds it by.
    ///   - priority: how urgent the ask is; every priority asks alike where
    ///     the focus stands unclaimed.
    public func defaultFocus<Value: Hashable>(
        _ condition: Binding<Value>, _ value: Value,
        priority: FocusPriority = .automatic
    ) -> ModifiedContent {
        onAppear {
            if condition.wrappedValue != value {
                condition.wrappedValue = value
            }
        }
    }
}

extension View {
    /// Publishes `value` under `keyPath` while this view or one below it
    /// holds the keyboard focus - the SwiftUI `.focusedValue`:
    ///
    ///     Editor(document: document)
    ///         .focusedValue(\.runAction) { document.run() }
    ///
    /// Every `@FocusedValue(\.runAction)` in the scene answers the nearest
    /// publisher's value on the chain above the focused element, and follows
    /// as the focus moves - so a command menu reads the focused pane's
    /// actions rather than one fixed view's.
    ///
    /// The write is carried on the element's node and never crosses the
    /// wire: what a host sees is the focus report it already sends, what a
    /// reader sees is the value folded out of the rendered tree.
    ///
    /// - Parameters:
    ///   - keyPath: the `FocusedValues` property to write.
    ///   - value: what it publishes while the focus is here.
    /// - Returns: the view, publishing.
    public func focusedValue<Value>(
        _ keyPath: WritableKeyPath<FocusedValues, Value?>, _ value: Value
    ) -> ModifiedContent {
        revised { $0.focusedValues[keyPath: keyPath] = value }
    }

    /// Publishes `value` under `keyPath` to the whole scene this view stands
    /// in - the SwiftUI `View.focusedSceneValue`:
    ///
    ///     DocumentView(document: document)
    ///         .focusedSceneValue(\.document, document)
    ///
    /// An `@FocusedSceneValue` anywhere in the scene reads it wherever it
    /// stands, and an `@FocusedValue` answers it beneath the focus chain's
    /// own writes.
    ///
    /// - Parameters:
    ///   - keyPath: the `FocusedValues` property to write.
    ///   - value: what it publishes to the scene.
    /// - Returns: the view, publishing.
    public func focusedSceneValue<Value>(
        _ keyPath: WritableKeyPath<FocusedValues, Value?>, _ value: Value
    ) -> ModifiedContent {
        revised { $0.sceneFocusedValues[keyPath: keyPath] = value }
    }
}

extension Scene {
    /// Publishes `value` under `keyPath` to every view of this scene -
    /// the SwiftUI `Scene.focusedSceneValue`:
    ///
    ///     WindowGroup { DocumentWindow() }
    ///         .focusedSceneValue(\.document, document)
    ///
    /// The write rides to the scene's root as an environment offer - one bag
    /// collects repeated calls, so `.focusedSceneValue(\.a, a)` beside
    /// `.focusedSceneValue(\.b, b)` publishes both.
    ///
    /// - Parameters:
    ///   - keyPath: the `FocusedValues` property to write.
    ///   - value: what it publishes to the scene's views.
    /// - Returns: the scene, publishing.
    public func focusedSceneValue<Value>(
        _ keyPath: WritableKeyPath<FocusedValues, Value?>, _ value: Value
    ) -> Scene {
        let key = ObjectIdentifier(FocusedSceneBag.self)

        if let offering = self as? OfferingScene, offering.key == key,
            let bag = offering.object as? FocusedSceneBag {
            bag.values[keyPath: keyPath] = value
            return offering
        }

        let bag = FocusedSceneBag()
        bag.values[keyPath: keyPath] = value
        return OfferingScene(base: self, key: key, object: bag)
    }
}
