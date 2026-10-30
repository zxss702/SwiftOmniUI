// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIGTK

/// An outline over a size as GSK's rounded rectangle: a rectangle, one with rounded corners, an ellipse, a
/// capsule, or a circle in the middle.
extension ContainerShape {
    /// The outline over `bounds`, each corner fitted to the room (`BoxArithmetic.fitted`). A circle answers
    /// the rounded rectangle of the square in `bounds`' middle, as wide as its shorter side.
    func rounded(_ bounds: graphene_rect_t) -> GskRoundedRect {
        var bounds = bounds
        let (width, height) = (Double(bounds.size.width), Double(bounds.size.height))
        if self == .circle {
            let side = Float(min(width, height))
            bounds.origin.x += Float((width - Double(side)) / 2)
            bounds.origin.y += Float((height - Double(side)) / 2)
            bounds.size.width = side
            bounds.size.height = side
        }
        let (roomWidth, roomHeight) = (Double(bounds.size.width), Double(bounds.size.height))
        if case .unevenRoundedRectangle(let cornerRadius) = self {
            let radii: (Double, Double, Double, Double)
            switch cornerRadius {
            case .uniform(let radius): radii = (radius, radius, radius, radius)
            case .corners(let tl, let tr, let bl, let br): radii = (tl, tr, bl, br)
            }
            let bound = min(roomWidth, roomHeight) / 2
            func corner(_ radius: Double) -> graphene_size_t {
                let fitted = min(radius, bound)
                return graphene_size_t(width: Float(fitted), height: Float(fitted))
            }
            // GSK's order: top left, top right, bottom right, bottom left.
            return GTKOutline.rounded(
                bounds, corners: [corner(radii.0), corner(radii.1), corner(radii.3), corner(radii.2)])
        }
        let fitted: (width: Double, height: Double) = switch self {
        case .rectangle: (0, 0)
        case .roundedRectangle(let radius): BoxArithmetic.fitted(radius, width: roomWidth, height: roomHeight)
        case .unevenRoundedRectangle: (0, 0)
        case .ellipse, .circle: (roomWidth / 2, roomHeight / 2)
        case .capsule: (min(roomWidth, roomHeight) / 2, min(roomWidth, roomHeight) / 2)
        }
        let corner = graphene_size_t(width: Float(fitted.width), height: Float(fitted.height))
        return GTKOutline.rounded(bounds, corners: [corner, corner, corner, corner])
    }

    /// Whether `point` - in the bounds' own frame - stands within the outline:
    /// a `.contentShape`'s test of what input counts.
    func contains(_ point: Point, in bounds: Rect) -> Bool {
        var rect = graphene_rect_t()
        graphene_rect_init(
            &rect, Float(bounds.x), Float(bounds.y), Float(bounds.width), Float(bounds.height))
        var rounded = self.rounded(rect)
        var at = graphene_point_t(x: Float(point.x), y: Float(point.y))
        return gsk_rounded_rect_contains_point(&rounded, &at) != 0
    }
}

/// GSK's rounded rectangle.
enum GTKOutline {
    /// `bounds` with its corners - top left, top right, bottom right, bottom left - rounded each by its own size.
    static func rounded(_ bounds: graphene_rect_t, corners: [graphene_size_t]) -> GskRoundedRect {
        var rounded = GskRoundedRect()
        var bounds = bounds
        var (topLeft, topRight, bottomRight, bottomLeft) = (corners[0], corners[1], corners[2], corners[3])
        gsk_rounded_rect_init(&rounded, &bounds, &topLeft, &topRight, &bottomRight, &bottomLeft)
        return rounded
    }
}

