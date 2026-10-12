// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// A page, or a container like it: its one child within its padding.
@MainActor
class GTKSingleChildView: GTKLayoutView {
    /// The room inside the view's own edge.
    var padding = EdgeInsets(0) {
        didSet { if padding != oldValue { invalidateMeasurements() } }
    }

    /// Whether items beyond the first stand elsewhere: a page's stack merged into an enclosing one.
    var holdsOnlyFirstItem = false

    override func heldViews() -> [GTKView] {
        holdsOnlyFirstItem ? items.prefix(1).map(\.view) : super.heldViews()
    }

    override func contentSize(width: Double?) -> LayoutSize {
        SingleChildArithmetic.size(of: items.first, padding: padding, width: width)
    }

    override func arrange(in bounds: Rect) {
        guard let item = items.first, item.isShown else { return }

        let context = layoutSafeArea(in: bounds)
        let room = item.element?.isSafeAreaBoundary == true ? bounds : context.safe
        item.view.layout(SingleChildArithmetic.place(of: item, in: room, padding: padding, direction: direction))
    }
}
