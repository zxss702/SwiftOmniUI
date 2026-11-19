// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// A type-erased list of data representing the content of a navigation stack -
/// SwiftUI's `NavigationPath`.
public struct NavigationPath: Equatable {
    var elements: [AnyHashable] = []

    /// Creates an empty navigation path.
    public init() {}

    /// Creates a new navigation path from a sequence of hashable elements.
    public init<S: Sequence>(_ elements: S) where S.Element: Hashable {
        self.elements = elements.map { AnyHashable($0) }
    }

    /// Creates a new navigation path from a sequence of codable, hashable elements.
    public init<S: Sequence>(_ elements: S) where S.Element: Decodable, S.Element: Encodable, S.Element: Hashable {
        self.elements = elements.map { AnyHashable($0) }
    }

    /// The number of elements in this path.
    public var count: Int { elements.count }

    /// A Boolean that indicates whether this path is empty.
    public var isEmpty: Bool { elements.isEmpty }

    /// Appends a new hashable value to the end of this path.
    public mutating func append<V: Hashable>(_ value: V) {
        elements.append(AnyHashable(value))
    }

    /// Removes the specified number of elements from the end of this path.
    public mutating func removeLast(_ k: Int = 1) {
        elements.removeLast(k)
    }
}
