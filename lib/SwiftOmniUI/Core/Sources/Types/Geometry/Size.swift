// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// A size.
///
/// What a drag has covered, what a view would take, or what a drawing is.
/// Its units belong to the property that reads it.
public struct Size: Equatable, Sendable {
    /// How far across.
    public var width: Double

    /// How far down.
    public var height: Double

    /// A size.
    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    /// The same without labels, for a list where the labels would drown the
    /// numbers.
    public init(_ width: Double, _ height: Double) {
        self.init(width: width, height: height)
    }

    /// Nothing at all: both numbers 0.
    public static let zero = Size(0, 0)
}

extension Size: HostRepresentable {
    /// Across, then down: one pair of numbers.
    public var propValue: PropValue { .numbers([width, height]) }

    /// A size back from its pair - nil for anything else.
    /// - Parameter propValue: what the host sent.
    public init?(propValue: PropValue) {
        guard let pair = propValue.numbers, pair.count == 2 else { return nil }

        self.init(width: pair[0], height: pair[1])
    }
}
