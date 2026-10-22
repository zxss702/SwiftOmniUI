// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// One child as its GTK layout places it: its view, and what the layout reads of it.
@MainActor
struct GTKLayoutItem: LayoutChild {
    let view: GTKView

    /// What the layout reads of the child.
    var values = LayoutValues()
    weak var element: MountedElement?

    /// Whether the child is shown; a hidden child takes no room.
    var isShown = true

    /// The mounted element whose place its layout animates; 0 for none.
    var mount: UInt64 = 0

    /// The element id a child's `.layoutValue` tags ride under; nil for a view no element presents.
    var codeId: ElementId?

    /// Fades the view in as it joins a standing layout; nil for a view that simply appears.
    var fadeIn: ((Animation, Rect) -> Void)?

    /// Whether the view animates out where it stood: kept in the subviews, taking no room.
    var departing = false

    /// The view's size for the width offered it, margin taken out (`LayoutValues.offer`, `sized`).
    func size(offered width: Double?) -> LayoutSize {
        values.sized(view.measure(width: values.offer(width), height: nil), offered: width)
    }

    /// Custom layouts propose both axes, including a Canvas's drawing height.
    func size(offered proposal: ProposedViewSize) -> LayoutSize {
        let height = values.height.map { values.boundedHeight($0, available: proposal.height) }
            ?? [proposal.height, values.maximumHeight].compactMap { $0 }.min()
        var sized = values.sized(view.measure(width: values.offer(proposal.width), height: height),
                                 offered: proposal.width)
        if values.height == nil, let height = proposal.height, height.isFinite {
            let expands = values.expandingAxes == .vertical || values.expandingAxes == .both
            let scrolls = values.scrollAxes == .vertical || values.scrollAxes == .both
            if expands || scrolls || values.minimumHeight != nil || values.maximumHeight != nil {
                sized.height = values.boundedHeight(height)
            }
        }
        return sized
    }

    func arranges(like other: GTKLayoutItem) -> Bool {
        view === other.view && values == other.values && isShown == other.isShown && departing == other.departing
    }
}
