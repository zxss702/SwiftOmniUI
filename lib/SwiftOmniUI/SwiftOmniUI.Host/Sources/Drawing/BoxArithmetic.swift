// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore

/// A box's outline and corners - a layout's, a button's, a colour box's, a rectangle's - as every host draws them.
/// Design: docs/design/host/layout.md#a-box
@_spi(Host) public enum BoxArithmetic {
    /// The corners' radii, clockwise from the top left - the order toolkits take them in, where SwiftOmniUI names the
    /// bottom left third - each a radius of nothing where it is no number or below nothing.
    public static func clockwise(_ corners: CornerRadius?) -> [Double] {
        let radii: [Double] = switch corners {
        case .uniform(let radius): [radius, radius, radius, radius]
        case .corners(let topLeft, let topRight, let bottomLeft, let bottomRight):
            [topLeft, topRight, bottomRight, bottomLeft]
        case nil: [0, 0, 0, 0]
        }
        return radii.map { $0.isFinite ? max(0, $0) : 0 }
    }

    /// A corner's circular radius in a room `width` by `height`: no more than half its shorter side.
    public static func fitted(_ radius: Double, width: Double, height: Double) -> (width: Double, height: Double) {
        let fitted = min(radius, width / 2, height / 2)
        return (fitted, fitted)
    }

    /// The outline the tree's `value` asks for: a rectangle where it asks none, a rounded one's radius never below
    /// nothing.
    public static func outline(_ value: HostValue?) -> ContainerShape {
        guard let parts = value?.values, let kind = parts.first?.enumeration else { return .rectangle }
        switch kind {
        case 1: return .roundedRectangle(max(0, parts.count > 1 ? parts[1].number ?? 0 : 0))
        case 2: return .ellipse
        case 3: return .capsule
        case 4: return .circle
        case 5:
            guard parts.count > 1 else { return .rectangle }
            if let radius = parts[1].number {
                return .unevenRoundedRectangle(.uniform(max(0, radius)))
            }
            if let radii = parts[1].numbers, radii.count == 4 {
                return .unevenRoundedRectangle(.corners(
                    topLeft: max(0, radii[0]), topRight: max(0, radii[1]),
                    bottomLeft: max(0, radii[2]), bottomRight: max(0, radii[3])))
            }
            return .rectangle
        default: return .rectangle
        }
    }

    /// How wide an outline is drawn: none without a colour to draw it in, else as the tree says - one where it says
    /// nothing - never below nothing.
    public static func outlineWidth(stroke: HostValue?, width: Double?) -> Double {
        guard stroke != nil else { return 0 }
        let width = width ?? 1
        return width.isFinite ? max(0, width) : 0
    }
}
