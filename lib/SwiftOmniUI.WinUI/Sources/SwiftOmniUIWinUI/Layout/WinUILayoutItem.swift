// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// One child as its WinUI layout places it: its view, and what the layout reads of it.
@MainActor
struct WinUILayoutItem: LayoutChild {
    /// The child's view.
    let view: WinUIView

    /// What the layout reads of the child.
    var values = LayoutValues()
    weak var element: MountedElement?

    /// Whether the child is shown; a hidden child takes no room.
    var isShown = true

    /// The mounted element the view presents, whose place its layout animates; 0 for none.
    var mount: UInt64 = 0

    /// The element id a child's `.layoutValue` tags ride under; nil for a view no element presents.
    var codeId: ElementId?

    /// Fades the view in as it joins a standing layout; nil for a view that simply appears.
    var fadeIn: ((Animation, Rect) -> Void)?

    /// Whether the view animates out where it stood: kept in the subviews, taking no room.
    var departing = false

    /// The view's size for the width offered it, margin taken out (`LayoutValues.offer`, `sized`).
    func size(offered width: Double?) -> LayoutSize {
        size(offered: ProposedViewSize(width: width))
    }

    func size(offered proposal: ProposedViewSize) -> LayoutSize {
        // Intrinsic probes cannot change either axis of an explicit frame.
        // Querying every nested image/text here only throws away its answer
        // and changes XAML's active Measure constraint. The parent's native
        // plan still prepares this subtree at its actual allocation.
        if WinUILayoutView.queryingSize > 0,
           let width = values.width, width.isFinite,
           let height = values.height, height.isFinite {
            return values.sized(.zero, offered: proposal.width)
        }
        let offer = values.offer(proposal.width)
        let height: Double?
        if let stated = values.height {
            height = values.boundedHeight(stated, available: proposal.height)
        } else {
            height = [proposal.height, values.maximumHeight].compactMap { $0 }.min()
        }
        let offered = ProposedViewSize(width: offer, height: height)
        var measured: LayoutSize
        if let layout = view as? WinUILayoutView {
            measured = height == nil ? layout.naturalSize(width: offer) : layout.naturalSize(proposal: offered)
            if WinUILayoutView.queryingSize == 0 {
                let expands = values.flex != nil || values.expandingAxes == .horizontal || values.expandingAxes == .both
                let allocated = Extent.of(option: expands ? 3 : values.horizontal, stated: values.width,
                                          natural: measured.width, available: proposal.width ?? measured.width,
                                          minimum: values.minimumWidth, maximum: values.maximumWidth)
                layout.prepareMeasure(width: allocated, height: height)
                measured = height == nil ? layout.naturalSize(width: offer) : layout.naturalSize(proposal: offered)
            }
        } else {
            measured = view.measure(width: offer, height: height)
        }
        var sized = values.sized(measured, offered: proposal.width)
        if values.height == nil, let height = proposal.height, height.isFinite {
            let expands = values.expandingAxes == .vertical || values.expandingAxes == .both
            let scrolls = values.scrollAxes == .vertical || values.scrollAxes == .both
            if expands || scrolls || values.minimumHeight != nil || values.maximumHeight != nil {
                sized.height = values.boundedHeight(height)
            }
        }
        return sized
    }

    /// Whether a parent would place this item as it places `other`.
    func arranges(like other: WinUILayoutItem) -> Bool {
        view === other.view && values == other.values && isShown == other.isShown && departing == other.departing
    }
}
