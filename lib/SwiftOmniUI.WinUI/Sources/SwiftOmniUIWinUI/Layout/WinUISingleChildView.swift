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
        Self.querySize { SingleChildArithmetic.size(of: items.first, padding: padding, width: width) }
    }

    override var hasNativeProposals: Bool { true }
    override var retainsArithmeticOnNativeMeasure: Bool { true }
    override func nativeProposals(width: Double?, size: LayoutSize) -> [NativeProposal] {
        guard let item = items.first, item.isShown else { return [] }
        let place = childPlace(item, in: Rect(0, 0, width ?? size.width, size.height))
        return [NativeProposal(view: item.view, place: place)]
    }

    override func arrange(in bounds: Rect) {
        for proposal in preparedLayoutPlan(in: bounds) { proposal.view?.layout(proposal.place) }
    }

    private func childPlace(_ item: WinUILayoutItem, in bounds: Rect) -> Rect {
        let room = item.element?.preservesSafeAreaProposal == true ? bounds : layoutSafeArea(in: bounds).safe
        return SingleChildArithmetic.place(of: item, in: room, padding: padding, direction: direction)
    }
}
