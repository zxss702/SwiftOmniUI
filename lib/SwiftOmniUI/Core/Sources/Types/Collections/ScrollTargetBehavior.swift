// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// How a scroll view settles when the hand leaves it: on a target's edge, or
/// one page at a time.
///
///     ScrollView { … }.scrollTargetBehavior(.viewAligned(anchor: .bottom))
public struct ScrollTargetBehavior: Equatable, Sendable {
    /// What settles the scroll, numbered as SwiftOmniUI's vocabularies are.
    let kind: Int32

    /// Where on a target the alignment takes, fractions across and down.
    let anchor: UnitPoint

    /// Settles on the nearest target's edge, `anchor` naming where on it -
    /// `.center` for the middle.
    public static func viewAligned(anchor: UnitPoint = .center) -> ScrollTargetBehavior {
        ScrollTargetBehavior(kind: 0, anchor: anchor)
    }

    /// Settles one page on, the way a pager does.
    public static var paging: ScrollTargetBehavior {
        ScrollTargetBehavior(kind: 1, anchor: .center)
    }
}

extension ScrollTargetBehavior: HostRepresentable {
    /// The kind, then the anchor's two fractions.
    public var propValue: PropValue { .numbers([Double(kind), anchor.x, anchor.y]) }

    /// The behavior back, or nil where what crossed is not one.
    /// - Parameter propValue: what the host sent.
    public init?(propValue: PropValue) {
        guard let numbers = propValue.numbers, numbers.count == 3 else { return nil }
        kind = Int32(numbers[0])
        anchor = UnitPoint(x: numbers[1], y: numbers[2])
    }
}

extension ScrollTargetBehavior: StateValue {
    /// Kind, then the anchor's two fractions.
    public var carried: StateCarried { .lanes([Double(kind), anchor.x, anchor.y]) }

    /// The behavior those lanes stand for.
    /// - Parameter carried: what the state holds.
    public init?(carried: StateCarried) {
        guard case .lanes(let lanes) = carried, lanes.count == 3 else { return nil }
        kind = Int32(lanes[0])
        anchor = UnitPoint(x: lanes[1], y: lanes[2])
    }

    /// Three.
    public static var lanes: Int { 3 }
}
