// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// A NavigationStack: its top page across its whole frame. The pages below are kept by their elements and held by
/// no view, so each keeps what it showed for when the user comes back to it. The stack's furniture - the top page's
/// title, the way back and the page's actions - is the window's chrome, which the window composes from the visible
/// arrangement, so WinUI is given no second navigation model to reconcile with SwiftOmniUI's path.
/// Design: docs/design/platforms/winui/pages.md#a-navigation-stack
@MainActor
final class WinUINavigationView: WinUILayoutView {
    private var depth = 0

    override init() {
        super.init { swiftomniui_winui_navigation_make($0) }
    }

    override func holdNativeChildren(_ handles: [SwiftOmniUIObjectRef?]) {
        swiftomniui_winui_navigation_set(handle, boxView?.handle, items.last?.view.handle,
                                         depth > 0, items.count < depth)
        depth = items.count
    }

    override func heldViews() -> [WinUIView] {
        items.last.map { [$0.view] } ?? []
    }

    override func contentSize(width: Double?) -> LayoutSize {
        SingleChildArithmetic.size(of: items.last, padding: EdgeInsets(0), width: width)
    }

    override func arrange(in bounds: Rect) {
        guard let page = items.last else { return }
        page.view.layout(SingleChildArithmetic.place(of: page, in: bounds, padding: EdgeInsets(0), direction: direction))
    }

    override func detach() {
        super.detach()
        swiftomniui_winui_navigation_clear(handle)
    }
}
