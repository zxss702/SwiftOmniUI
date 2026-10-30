// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// What a view heard of the user's input, as the relay tells it.
/// Design: docs/design/platforms/winui/input.md
extension HeardInput {
    /// What the relay's callback says - `phase` a tap's place in its run or a gesture's phase, a pinch's `scale`
    /// since its last step - nil for what it does not name.
    init?(_ what: SwiftOmniUIHeard, phase: Int32, x: Double, y: Double, scale: Double) {
        let point = Point(x: x, y: y)
        switch what {
        case SwiftOmniUIHeardTap: self = .tap(run: Int(phase))
        case SwiftOmniUIHeardPointerEntered: self = .pointer(.pointerEntered, point)
        case SwiftOmniUIHeardPointerExited: self = .pointer(.pointerExited, point)
        case SwiftOmniUIHeardPointerMoved: self = .pointer(.pointerMoved, point)
        case SwiftOmniUIHeardPointerPressed: self = .pointer(.pointerPressed, point)
        case SwiftOmniUIHeardPointerReleased: self = .pointer(.pointerReleased, point)
        case SwiftOmniUIHeardPinch:
            guard let phase = GesturePhase(rawValue: phase) else { return nil }
            self = .pinch(phase, scale: scale, at: point)
        default: return nil
        }
    }
}
