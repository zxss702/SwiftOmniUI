// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// A closed vocabulary, numbered by SwiftOmniUI: append a case, never insert one.
// Design: docs/design/types/vocabularies.md#written-out-and-appended

/// Which ways a `ScrollView` scrolls.
public enum Axis: Int32, Sendable {
    /// Up and down. The default.
    case vertical = 0

    /// Sideways.
    case horizontal = 1

    /// Both at once.
    case both = 2

    /// Neither - which is how a ScrollView is stopped from scrolling without
    /// being replaced.
    case neither = 3
}

extension Axis {
    /// A set of axes - what `.scrollIndicators(_:axes:)` takes.
    public struct Set: OptionSet, Sendable {
        /// The flag bits.
        public let rawValue: Int32

        /// From the raw bits.
        public init(rawValue: Int32) {
            self.rawValue = rawValue
        }

        /// The sideways axis.
        public static let horizontal = Set(rawValue: 1 << 0)

        /// The up-and-down axis.
        public static let vertical = Set(rawValue: 1 << 1)

        /// Both.
        public static let all: Set = [.horizontal, .vertical]
    }
}

extension Axis: HostRepresentable {}
extension Axis: StateChoice {}
extension Axis.Set: HostRepresentable {}
