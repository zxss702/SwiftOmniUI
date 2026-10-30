// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// An outline - a rectangle, one with rounded corners, or an ellipse (`BoxArithmetic.outline`) - as the relay takes
/// it.
extension ContainerShape {
    /// The outline's kind, and a rounded rectangle's radius.
    var relay: (outline: SwiftOmniUIOutline, radius: Double) {
        switch self {
        case .rectangle: (SwiftOmniUIOutlineRectangle, 0)
        case .roundedRectangle(let radius): (SwiftOmniUIOutlineRounded, radius)
        case .unevenRoundedRectangle(let cornerRadius):
            // A WinUI clip is a RectangleGeometry - uniform radii only; the
            // largest corner stands in until a Composition path lands.
            switch cornerRadius {
            case .uniform(let radius): (SwiftOmniUIOutlineRounded, radius)
            case .corners(let tl, let tr, let bl, let br):
                (SwiftOmniUIOutlineRounded, max(tl, tr, bl, br))
            }
        case .ellipse: (SwiftOmniUIOutlineEllipse, 0)
        case .capsule: (SwiftOmniUIOutlineCapsule, 0)
        case .circle: (SwiftOmniUIOutlineCircle, 0)
        }
    }
}
