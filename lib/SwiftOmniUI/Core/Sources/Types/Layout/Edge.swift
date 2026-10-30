// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// One edge of a view: what `.padding(_:_:)` and safe-area modifiers name.
public enum Edge: Int8, Sendable {
    /// The top edge.
    case top = 1

    /// The leading edge - the left, left-to-right.
    case leading = 2

    /// The bottom edge.
    case bottom = 4

    /// The trailing edge - the right, left-to-right.
    case trailing = 8

    /// A set of edges: `.all`, `.horizontal`, `.vertical`, or the ones named.
    ///
    ///     Text(title).padding(.horizontal, 16)
    ///     Text(title).padding([.top, .trailing], 8)
    public struct Set: OptionSet, Sendable {
        /// The edges' bits.
        public let rawValue: Int8

        /// A set from its bits - each `Edge`'s number is one.
        public init(rawValue: Int8) {
            self.rawValue = rawValue
        }

        /// The top edge.
        public static let top = Set(rawValue: Edge.top.rawValue)

        /// The leading edge.
        public static let leading = Set(rawValue: Edge.leading.rawValue)

        /// The bottom edge.
        public static let bottom = Set(rawValue: Edge.bottom.rawValue)

        /// The trailing edge.
        public static let trailing = Set(rawValue: Edge.trailing.rawValue)

        /// Leading and trailing.
        public static let horizontal: Set = [.leading, .trailing]

        /// Top and bottom.
        public static let vertical: Set = [.top, .bottom]

        /// All four.
        public static let all: Set = [.top, .leading, .bottom, .trailing]
    }
}

extension Edge: HostRepresentable {
    /// The edge's number.
    public var propValue: PropValue { .enumeration(Int32(rawValue)) }

    /// The edge back, or nil where what crossed is not one.
    /// - Parameter propValue: what the host sent.
    public init?(propValue: PropValue) {
        guard let number = propValue.enumeration, let edge = Edge(rawValue: Int8(number)) else { return nil }

        self = edge
    }
}

/// An edge on the vertical axis: the top, or the bottom - what
/// `.safeAreaInset(edge:)` names.
public enum VerticalEdge: Int8, Sendable {
    /// The top edge.
    case top = 1

    /// The bottom edge.
    case bottom = 4
}

/// An edge on the horizontal axis: the leading, or the trailing.
public enum HorizontalEdge: Int8, Sendable {
    /// The leading edge - the left, left-to-right.
    case leading = 2

    /// The trailing edge - the right, left-to-right.
    case trailing = 8
}
