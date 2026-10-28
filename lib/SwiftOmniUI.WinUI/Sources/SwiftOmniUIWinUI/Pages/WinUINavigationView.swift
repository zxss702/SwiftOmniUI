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
                // Frame/Page now receive the extended native viewport. Convert
                // the original proposal once; resizing that already-expanded
                // proposal before conversion would add the chrome twice.
                let inherited = self.layoutSafeArea(in: bounds).bounds
                let top = max(0, bounds.y - inherited.y)
                let bottom = max(0, inherited.y + inherited.height - bounds.y - bounds.height)
                let proposal = Rect(0, 0, bounds.width, max(0, bounds.height - top - bottom))
                let frame = Rect(0, -top, bounds.width, bounds.height)
                return self.layoutSafeArea(in: proposal)
                    .child(in: frame, preservingOutsets: page.carriesSafeAreaOutsets)
                    .resizedLayout(to: bounds)
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

    override func contentSize(proposal: ProposedViewSize) -> LayoutSize {
        updateViewport(in: Rect(0, 0, proposal.width ?? 0, proposal.height ?? 0))
        return contentSize(width: proposal.width)
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

    override func arrange(in bounds: Rect) {
        updateViewport(in: bounds)
    }

    private func updateViewport(in bounds: Rect) {
        // Preserve the horizontal column clip while admitting ScrollView ink
        // beneath inherited native chrome above/below the page allocation.
        let context = layoutSafeArea(in: bounds)
        let whole = context.bounds
        let top = max(0, bounds.y - whole.y)
        let bottom = max(0, whole.y + whole.height - bounds.y - bounds.height)
        swiftomniui_winui_navigation_set_vertical_outsets(handle, top, bottom)
    }

    override func detach() {
        for item in items { release(item.view) }
        super.detach()
        swiftomniui_winui_navigation_clear(handle)
    }
}
