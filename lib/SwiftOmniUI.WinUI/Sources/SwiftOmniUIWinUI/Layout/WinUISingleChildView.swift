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
        SingleChildArithmetic.size(of: items.first, padding: padding, width: width)
    }

    override func prepareChildren(width: Double) {
        guard let item = items.first, item.isShown else { return }
        let size = naturalSize(width: width.isFinite ? width : nil)
        let room = Rect(0, 0, width.isFinite ? width : size.width, size.height)
        prepareChild(item, at: SingleChildArithmetic.place(of: item, in: room, padding: padding, direction: direction))
    }

    override func arrange(in bounds: Rect) {
        guard let item = items.first, item.isShown else { return }

        let context = layoutSafeArea(in: bounds)
        let room = item.element?.preservesSafeAreaProposal == true ? bounds : context.safe
        item.view.layout(SingleChildArithmetic.place(of: item, in: room, padding: padding, direction: direction))
    }
}
