// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The focus chain's readers: `@FocusedValue` for the values a focused branch
// publishes, `@FocusedSceneValue` for the scene's own - both resolved through
// the differ's `FocusedValueStore` the way `@Environment` resolves its scope.
// Design: docs/design/core/state.md#the-environment

/// The value a focused view or one of its ancestors publishes under a
/// `FocusedValues` key - the SwiftUI `@FocusedValue`:
///
///     struct RunActionKey: FocusedValueKey {
///         typealias Value = () -> Void
///     }
///
///     extension FocusedValues {
///         var runAction: (() -> Void)? {
///             get { self[RunActionKey.self] }
///             set { self[RunActionKey.self] = newValue }
///         }
///     }
///
///     @FocusedValue(\.runAction) private var runAction
///
/// What it answers moves with the keyboard focus: the nearest
/// `.focusedValue` write on the chain from the focused element upward wins,
/// over the scene's own `.focusedSceneValue` beneath, and a move of the
/// focus rebuilds every view that reads it. Nil where nothing publishes the
/// key - declaring the property optional is how an author says so.
@propertyWrapper
public final class FocusedValue<Value>: @unchecked Sendable {
    /// The `FocusedValues` property this reads.
    private let keyPath: KeyPath<FocusedValues, Value>

    /// The store the differ resolved for this view's place in the tree - nil
    /// before its first build, and in a structural `.built` there is no
    /// focus to read.
    private var store: FocusedValueStore?

    /// Declares the read - `@FocusedValue(\.runAction)`.
    /// - Parameter keyPath: the `FocusedValues` property to read.
    public init(_ keyPath: KeyPath<FocusedValues, Value>) {
        self.keyPath = keyPath
    }

    /// The nearest `.focusedValue` write on the focus chain, over the scene's
    /// `.focusedSceneValue` - reading it makes this view the focus's reader,
    /// so a move rebuilds it.
    public var wrappedValue: Value {
        guard let store else { return FocusedValues()[keyPath: keyPath] }

        Renderer.shared.stateRead(store)
        return store.values(for: Scenes.shared.building)[keyPath: keyPath]
    }

    /// What `wrappedValue` answers, without recording the read - how
    /// `same(as:)` compares two resolutions without subscribing a question.
    private func peek() -> Value {
        store?.values(for: Scenes.shared.building)[keyPath: keyPath]
            ?? FocusedValues()[keyPath: keyPath]
    }
}

extension FocusedValue: EnvironmentSlot {
    /// The store, as the scope is keyed - the seeded entry every walk offers.
    var wants: ObjectIdentifier { ObjectIdentifier(FocusedValueStore.self) }

    var filled: AnyObject? { store }

    /// Takes the resolved store; a keyless offer resolves nothing here.
    func fill(_ object: AnyObject) {
        store = object as? FocusedValueStore
    }

    /// Keyed environment values are nobody's business here.
    func fill(values: EnvironmentValues) {}

    /// Whether this slot and an earlier render's resolved the same - the
    /// carry's question, answered by the values rather than the store, since
    /// the store outlives the readings it hands out.
    func same(as other: EnvironmentSlot) -> Bool {
        guard let other = other as? FocusedValue<Value> else { return false }

        return FocusedValue.same(peek(), as: other.peek())
    }

    /// Whether one resolution still answers what another did: `Equatable`
    /// where the value offers it, identity where it is an object, nil beside
    /// nil - and different where nothing can say, so the view is built again
    /// rather than carried past a moved write.
    static func same(_ a: Value, as b: Value) -> Bool {
        if FocusedValue.isNil(a), FocusedValue.isNil(b) { return true }

        if let equatable = a as? any Equatable {
            func open<T: Equatable>(_ a: T) -> Bool { (b as? T).map { $0 == a } ?? false }
            return open(equatable)
        }

        if let a = a as? AnyObject, let b = b as? AnyObject {
            return a === b
        }

        return false
    }

    /// Whether the value is an empty optional - the answer most reads carry.
    private static func isNil(_ value: Any) -> Bool {
        let mirror = Mirror(reflecting: value)
        return mirror.displayStyle == .optional && mirror.children.isEmpty
    }
}

/// The value a scene publishes under a `FocusedValues` key, for every view in
/// it - the SwiftUI `@FocusedSceneValue`:
///
///     @FocusedSceneValue(\.document) private var document
///
/// Where `@FocusedValue` follows the keyboard into the focused branch, this
/// reads only what the scene itself publishes with `.focusedSceneValue` -
/// a reader sees the answer wherever in the scene it stands. Nil where the
/// scene publishes nothing under the key.
@propertyWrapper
public final class FocusedSceneValue<Value>: @unchecked Sendable {
    /// The `FocusedValues` property this reads.
    private let keyPath: KeyPath<FocusedValues, Value>

    /// The store the differ resolved for this view's place in the tree.
    private var store: FocusedValueStore?

    /// Declares the read - `@FocusedSceneValue(\.document)`.
    /// - Parameter keyPath: the `FocusedValues` property to read.
    public init(_ keyPath: KeyPath<FocusedValues, Value>) {
        self.keyPath = keyPath
    }

    /// The scene's `.focusedSceneValue` answers, read by this view - a moved
    /// publish rebuilds it.
    public var wrappedValue: Value {
        guard let store else { return FocusedValues()[keyPath: keyPath] }

        Renderer.shared.stateRead(store)
        return store.sceneValues(for: Scenes.shared.building)[keyPath: keyPath]
    }

    /// What `wrappedValue` answers, without recording the read.
    private func peek() -> Value {
        store?.sceneValues(for: Scenes.shared.building)[keyPath: keyPath]
            ?? FocusedValues()[keyPath: keyPath]
    }
}

extension FocusedSceneValue: EnvironmentSlot {
    /// The store, as the scope is keyed - the same seeded store
    /// `@FocusedValue` resolves from.
    var wants: ObjectIdentifier { ObjectIdentifier(FocusedValueStore.self) }

    var filled: AnyObject? { store }

    /// Takes the resolved store.
    func fill(_ object: AnyObject) {
        store = object as? FocusedValueStore
    }

    /// Keyed environment values are nobody's business here.
    func fill(values: EnvironmentValues) {}

    /// Whether this slot and an earlier render's resolved the same scene's
    /// answers - the carry's question, same as `FocusedValue`'s.
    func same(as other: EnvironmentSlot) -> Bool {
        guard let other = other as? FocusedSceneValue<Value> else { return false }

        return FocusedValue.same(peek(), as: other.peek())
    }
}
