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

    @discardableResult
    override func setItems(_ items: [WinUILayoutItem]) -> Bool {
        let surviving = Set(items.map { ObjectIdentifier($0.view) })
        for previous in self.items where !surviving.contains(ObjectIdentifier(previous.view)) {
            release(previous.view)
        }
        let changed = super.setItems(items)
        for item in items {
            let page = item.view
            // Frame/Page owns the native page's proposal and placement. Keeping
            // a Swift placing parent makes its MeasureOverride return zero and
            // allows two different widths to be arranged onto the same page.
            page.placingLayout = nil
            guard page.nativeLayoutOwner !== self else { continue }
            page.nativeLayoutOwner = self
            page.rootSafeAreaContext = { [weak self, weak page] bounds in
                guard let self, let page else { return SafeAreaContext(bounds: bounds) }
                // The native page fills this frame's current proposal. Using
                // its previous allocation clips a first or resized Measure to
                // old bounds and invents unsafe strips along otherwise safe edges.
                return self.layoutSafeArea(in: bounds).child(
                    in: bounds, preservingOutsets: page.sourceElement?.observesSafeArea == true)
            }
            page.safeAreaContext = nil
        }
        return changed
    }

    override func holdNativeChildren(_ handles: [SwiftOmniUIObjectRef?]) {
        swiftomniui_winui_navigation_set(handle, boxView?.presentationHandle, items.last?.view.presentationHandle,
                                         depth > 0, items.count < depth)
        depth = items.count
    }

    override func heldViews() -> [WinUIView] {
        items.last.map { [$0.view] } ?? []
    }

    override func contentSize(width: Double?) -> LayoutSize {
        Self.querySize { SingleChildArithmetic.size(of: items.last, padding: EdgeInsets(0), width: width) }
    }

    override func safeAreaChanged() {
        super.safeAreaChanged()
        if let page = items.last?.view {
            if isReceivingLayoutContext { page.withLayoutContext { page.safeAreaChanged() } }
            else { page.safeAreaChanged() }
        }
    }

    private func release(_ page: WinUIView) {
        guard page.nativeLayoutOwner === self else { return }
        page.nativeLayoutOwner = nil
        page.rootSafeAreaContext = nil
        page.safeAreaContext = nil
    }

    override func detach() {
        for item in items { release(item.view) }
        super.detach()
        swiftomniui_winui_navigation_clear(handle)
    }
}
