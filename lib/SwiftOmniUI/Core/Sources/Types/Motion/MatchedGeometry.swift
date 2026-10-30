// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// Matched geometry: the identity that lets one element's frame continue
// another's - the capsule that flies from the tab it left to the tab it joined.
// Design: docs/design/types/animation.md#matched-geometry

/// A namespace `.matchedGeometryEffect` ids mean something inside: views in
/// the same namespace with the same id are one element across a change.
///
///     @Namespace private var selection
///
///     Capsule()
///         .matchedGeometryEffect(id: "pill", in: selection)
///
/// Written as `@Namespace`, the wrapper hands the namespace itself to `in:`.
@propertyWrapper
public struct Namespace: Sendable {
    /// One namespace's identity; each `@Namespace` gets a different one.
    public struct ID: Hashable, Sendable {
        let serial: Int

        fileprivate init(_ serial: Int) {
            self.serial = serial
        }
    }

    /// The namespace.
    public let wrappedValue: ID

    /// A namespace of its own.
    public init() {
        wrappedValue = ID(Self.next())
    }

    /// The next namespace serial; namespaces are numbered, never named, so two
    /// declared beside each other can never alias.
    private static func next() -> Int {
        defer { Namespace.issue += 1 }
        return Namespace.issue
    }

    /// The process-wide issue counter.
    private nonisolated(unsafe) static var issue = 1
}

/// Which parts of a matched element's geometry travel - what
/// `.matchedGeometryEffect` takes in `properties:`.
public struct MatchedGeometryProperties: OptionSet, Equatable, Sendable {
    /// The set as its members' bits.
    public var rawValue: Int32

    /// A set from its members' bits.
    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    /// Position and size together - the default.
    public static let frame = MatchedGeometryProperties(rawValue: 1 << 0 | 1 << 1)

    /// Where the element stands.
    public static let position = MatchedGeometryProperties(rawValue: 1 << 0)

    /// How much room the element takes.
    public static let size = MatchedGeometryProperties(rawValue: 1 << 1)
}
