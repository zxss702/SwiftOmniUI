// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The values a focused branch publishes: the key one names them by, the bag
// they collect in, and the serial that tells two bags of incomparable values
// apart.

/// A key identifying a focused value - what a view declares so the value the
/// focused branch publishes is read under its own name:
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
public protocol FocusedValueKey {
    /// What the key reads and writes.
    associatedtype Value
}

/// The values the focused view and the scene around it publish, read by the
/// `FocusedValueKey` each names - the bag `@FocusedValue` reads and
/// `.focusedValue` writes under the SwiftUI spellings.
public struct FocusedValues {
    /// The published values, each by its key.
    private var values: [ObjectIdentifier: Any] = [:]

    /// The serial each entry was written under - what `same` compares for a
    /// value that cannot say itself whether it moved.
    private var stamps: [ObjectIdentifier: UInt64] = [:]

    /// An empty bag - nothing published.
    public init() {}

    /// What `key` publishes; nil where nothing wrote under it.
    public subscript<Key: FocusedValueKey>(key: Key.Type) -> Key.Value? {
        get { values[ObjectIdentifier(key)] as? Key.Value }
        set {
            values[ObjectIdentifier(key)] = newValue
            stamps[ObjectIdentifier(key)] = FocusedValuesClock.next()
        }
    }
}

extension FocusedValues {
    /// Whether nothing is published - what a folded bag answers at rest.
    var isEmpty: Bool { values.isEmpty }

    /// This bag with `written`'s entries on top - the nearer write wins, the
    /// way `EnvironmentValues.overlaid` answers for its own.
    func overlaid(with written: FocusedValues) -> FocusedValues {
        var merged = self

        for (key, value) in written.values {
            merged.values[key] = value
            merged.stamps[key] = written.stamps[key]
        }

        return merged
    }

    /// Whether `other` publishes the same keys to the same values - a value
    /// compared where it can say so, by identity where it is an object, and
    /// by its write's serial where it can say neither. A republished value
    /// reads as moved, which rebuilds a reader rather than leaving it stale.
    func same(as other: FocusedValues) -> Bool {
        guard Set(values.keys) == Set(other.values.keys) else { return false }

        for (key, value) in values {
            guard let theirs = other.values[key],
                FocusedValues.same(
                    value, written: stamps[key],
                    as: theirs, written: other.stamps[key])
            else { return false }
        }

        return true
    }

    /// One entry's sameness - the serials stand in for what the values
    /// themselves cannot compare.
    private static func same(
        _ a: Any, written stampA: UInt64?,
        as b: Any, written stampB: UInt64?
    ) -> Bool {
        if let equatable = a as? any Equatable {
            func open<T: Equatable>(_ a: T) -> Bool { (b as? T).map { $0 == a } ?? false }
            return open(equatable)
        }

        if let a = a as? AnyObject, let b = b as? AnyObject {
            return a === b
        }

        return stampA == stampB
    }
}

/// The serial each `.focusedValue` write takes - how `FocusedValues.same`
/// tells a republished value from the one it replaces when the value itself
/// cannot say. Writes happen on the UI thread, in a build.
enum FocusedValuesClock {
    /// The last serial handed out.
    private nonisolated(unsafe) static var serial: UInt64 = 0

    /// The next serial, never one already taken.
    static func next() -> UInt64 {
        serial += 1
        return serial
    }
}
