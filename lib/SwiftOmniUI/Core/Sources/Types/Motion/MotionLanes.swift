// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// Which parts of a child's placement animate when a layout moves it.
///
/// Not written directly: `.animation(_:_:)` on a layout naming `.place`, `.width`
/// or `.height` becomes this, carried in `HostLayoutMotion`.
///
/// Design: docs/design/types/animation.md#layout-lanes
public struct AnimationLanes: OptionSet, Sendable {
    /// The lane bits carried by `HostLayoutMotion`.
    public let rawValue: UInt8

    /// A set from its members' bits.
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    /// How far along it sits.
    public static let x = AnimationLanes(rawValue: 1 << 0)

    /// How far down it sits.
    public static let y = AnimationLanes(rawValue: 1 << 1)

    /// How wide the layout made it.
    public static let width = AnimationLanes(rawValue: 1 << 2)

    /// How tall the layout made it.
    public static let height = AnimationLanes(rawValue: 1 << 3)

    /// Where it sits - both halves of the corner it is placed at.
    public static let place: AnimationLanes = [.x, .y]

    /// Everything about a place, which is what a layout says unless it says
    /// otherwise.
    public static let all: AnimationLanes = [.x, .y, .width, .height]
}
