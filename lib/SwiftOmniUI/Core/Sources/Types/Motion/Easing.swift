// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// Easing curves: a closed vocabulary, numbered by SwiftOmniUI.
// Design: docs/design/types/animation.md#easing-curves

/// The curve an animation follows; with a duration, it makes an eased animation.
@_spi(Host) public enum Easing: Int32, Sendable {
    /// The same speed from beginning to end.
    case linear = 0

    /// Slow at the end, following a sine curve.
    case sineOut = 1

    /// Slow at the start, following a sine curve.
    case sineIn = 2

    /// Slow at both ends, following a sine curve.
    case sineInOut = 3

    /// Slow at the start, more pronounced than `.sineIn`.
    case cubicIn = 4

    /// Slow at the end, more pronounced than `.sineOut`: the usual choice for
    /// something appearing.
    case cubicOut = 5

    /// Slow at both ends, more pronounced than `.sineInOut`.
    case cubicInOut = 6

    /// Overshoots at the end and settles back.
    case bounceOut = 7

    /// Bounces before it sets off.
    case bounceIn = 8

    /// Pulls back before it sets off, the way a spring loads.
    case springIn = 9

    /// Overshoots the target and comes back to it.
    case springOut = 10

    var propValue: PropValue { .enumeration(rawValue) }
}
