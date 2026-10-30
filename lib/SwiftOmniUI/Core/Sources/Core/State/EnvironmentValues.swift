// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The keyed environment: values an ancestor hands down by name, written with
// `.environment(\.key, value)` and read below with `@Environment(\.key)` -
// beside the object environment, which resolves by type alone.
// Design: docs/design/core/state.md#the-environment

/// A key of `EnvironmentValues`: one named slot, declared as a type so the
/// value it holds and its default live beside its name.
///
///     struct PageTintKey: EnvironmentKey {
///         static let defaultValue: Color = .accent
///     }
///
///     extension EnvironmentValues {
///         var pageTint: Color {
///             get { self[PageTintKey.self] }
///             set { self[PageTintKey.self] = newValue }
///         }
///     }
public protocol EnvironmentKey {
    /// What the slot holds.
    associatedtype Value

    /// What a view reads where no ancestor wrote the slot.
    static var defaultValue: Value { get }
}

/// The keyed values the tree hands down: a write on an ancestor reaches its
/// whole subtree, and the nearer write is the one read.
///
/// A custom entry is a computed property on this type - get reads its key,
/// set writes it - and the property being settable is what makes
/// `.environment(\.name, value)` able to write it.
public struct EnvironmentValues {
    /// What ancestors wrote, under each key's own type.
    private var entries: [ObjectIdentifier: Any] = [:]

    /// An empty bag - everything reads its key's default.
    public init() {}

    /// One slot, by its key - what an ancestor wrote for it, or the key's own
    /// default where nothing did.
    public subscript<Key: EnvironmentKey>(key: Key.Type) -> Key.Value {
        get { entries[ObjectIdentifier(Key.self)] as? Key.Value ?? Key.defaultValue }
        set { entries[ObjectIdentifier(Key.self)] = newValue }
    }

    /// This bag with `written`'s entries on top - the nearer write wins.
    func overlaid(with written: EnvironmentValues) -> EnvironmentValues {
        var merged = self
        for (key, value) in written.entries {
            merged.entries[key] = value
        }
        return merged
    }
}
