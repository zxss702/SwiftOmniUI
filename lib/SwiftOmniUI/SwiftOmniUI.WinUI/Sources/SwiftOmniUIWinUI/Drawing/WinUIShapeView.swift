// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// A shape filled and outlined: a layout's box, drawn behind its children.
/// Design: docs/design/platforms/winui/drawing.md#a-box-and-its-brush
@MainActor
final class WinUIShapeView: WinUIView {
    /// Whether the shape is an ellipse; a rectangle, rounded or not, is the other element.
    let isEllipse: Bool

    private var painted: (radius: Double, fill: WinUIBrush, stroke: WinUIBrush, width: Double)?

    init(ellipse: Bool) {
        isEllipse = ellipse
        super.init { _ in swiftomniui_winui_shape_make(ellipse ? SwiftOmniUIOutlineEllipse : SwiftOmniUIOutlineRectangle) }
    }

    /// Paints the shape, written only where it differs from what was.
    func paint(radius: Double, fill: WinUIBrush, stroke: WinUIBrush, width: Double) {
        if let painted, painted.radius == radius, painted.fill == fill, painted.stroke == stroke,
           painted.width == width { return }

        painted = (radius, fill, stroke, width)
        paint("shape", followsSize: fill.followsSize || stroke.followsSize) { [handle] size in
            fill.withRelayBrush(over: size) { fill in
                stroke.withRelayBrush(over: size) { stroke in
                    swiftomniui_winui_shape_set(handle, radius, fill, stroke, width)
                }
            }
        }
    }
}
