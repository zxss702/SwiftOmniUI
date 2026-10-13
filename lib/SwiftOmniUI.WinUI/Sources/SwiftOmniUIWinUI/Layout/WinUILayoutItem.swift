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
        let offer = values.offer(width)
        // A layout of SwiftOmniUI's is measured at the width it stands at; its size for any width is the arithmetic's.
        // Design: docs/design/platforms/winui/layout.md#measured-every-pass
        let measured: LayoutSize
        if let layout = view as? WinUILayoutView {
            measured = layout.naturalSize(width: offer)
            if WinUIView.arranging == 0 {
                let expands = values.flex != nil || values.expandingAxes == .horizontal || values.expandingAxes == .both
                let allocated = Extent.of(option: expands ? 3 : values.horizontal, stated: values.width,
                                          natural: measured.width, available: width ?? measured.width,
                                          minimum: values.minimumWidth, maximum: values.maximumWidth)
                layout.prepareMeasure(width: allocated)
            }
        } else {
            measured = view.measure(width: offer, height: nil)
        }

        return values.sized(measured, offered: width)
    }

    /// Whether a parent would place this item as it places `other`.
    func arranges(like other: WinUILayoutItem) -> Bool {
        view === other.view && values == other.values && isShown == other.isShown && departing == other.departing
    }
}
