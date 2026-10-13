// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// A page, or a container like it: its one child within its padding.
@MainActor
class WinUISingleChildView: WinUILayoutView {
    /// The room inside the view's own edge, in DIPs.
    var padding = EdgeInsets(0) {
        didSet { if padding != oldValue { invalidateMeasurements() } }
    }

    override func contentSize(width: Double?) -> LayoutSize {
        let size = Self.querySize { SingleChildArithmetic.size(of: items.first, padding: padding, width: width) }
        if WinUIView.arranging == 0, Self.queryingSize == 0,
           let item = items.first, item.isShown {
            let room = Rect(x: 0, y: 0, width: width ?? size.width, height: size.height)
            let place = Self.querySize {
                SingleChildArithmetic.place(of: item, in: room, padding: padding, direction: direction)
            }
            item.view.prepareMeasure(width: place.width)
            return Self.querySize { SingleChildArithmetic.size(of: items.first, padding: padding, width: width) }
        }
        return size
    }

    override func arrange(in bounds: Rect) {
        guard let item = items.first, item.isShown else { return }

        let context = layoutSafeArea(in: bounds)
        let room = item.element?.preservesSafeAreaProposal == true ? bounds : context.safe
        item.view.layout(SingleChildArithmetic.place(of: item, in: room, padding: padding, direction: direction))
    }
}
