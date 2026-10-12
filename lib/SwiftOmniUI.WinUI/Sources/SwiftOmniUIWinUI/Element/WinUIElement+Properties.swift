// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// The native element: made, and given the element's properties.
extension WinUIElement {
    /// Gives the view its context menu again once the menu changed or went.
    /// Design: docs/design/platforms/winui/pages.md#menus
    func refreshContextMenu() {
        let menu = children.first { $0.type == .contextMenu }
        guard contextMenuChanged || (hadContextMenu && menu == nil), let view else { return }
        contextMenuChanged = false
        hadContextMenu = menu != nil
        view.setContextMenu(WinUIMenu(menu))
    }

    /// Whether the element stands on the window's chrome - under a toolbar's items or a title view - where a
    /// control is the bar's own.
    var standsInToolbar: Bool {
        var ancestor = element.parent
        while let each = ancestor {
            // A popover's card is no part of the bar its anchor stands on.
            if each.type == .popover { return false }
            if each.type == .toolbarItems || each.type == .titleView { return true }
            ancestor = each.parent
        }
        return false
    }

    func makeView() -> WinUIView? {
        if type == .button, standsInToolbar, element.value(.icon) != nil || element.value(.text) != nil {
            // The bar's own button, made here as the list is: the registration's members still reach it. A button
            // with only a view of the author's for a label is the platform's, carried in the bar's container.
            let button = WinUIButtonView(toolbar: true)
            button.onClicked = { [weak self] in self?.send(.clicked, []) }
            button.onToggled = { [weak self] on in self?.report(.isOn, .toggled, .bool(on)) }
            button.onPressed = { [weak self] in self?.send(.pressed, []) }
            button.onReleased = { [weak self] in self?.send(.released, []) }
            return button
        }
        if type == .menuButton, standsInToolbar { return WinUIMenuButtonView(toolbar: true) }
        if element.isLayoutDivider {
            let line = WinUIPathView()
            line.paint(fill: WinUIBrush(Color.gray.opacity(0.3).propValue), stroke: .none,
                       width: 0, outline: 0, dashes: [], dashOffset: 0, cap: .flat, join: .miter, miter: 10)
            return line
        }
        if type == .list, let host {
            return WinUIItemsView(cells: ItemsCells(element, in: host.runtime), reducesMotion: { [weak host] in
                host?.runtime.reducesMotion() ?? false
            })
        }
        if type == .lazyVStack || type == .lazyHStack, let host {
            return WinUILazyStackView(
                axis: type == .lazyVStack ? .vertical : .horizontal,
                cells: LazyCells(element, in: host.runtime))
        }
        if type == .lazyVGrid || type == .lazyHGrid, let host {
            return WinUILazyGridView(
                axis: type == .lazyVGrid ? .vertical : .horizontal,
                cells: LazyCells(element, in: host.runtime))
        }
        // A child its parent's view draws - a map's marker - has no view of its own.
        if element.isDrawnByParent(in: WinUIRegistrations.registry) { return nil }
        if let registered = WinUIRegistrations.registry.makeView(
            for: type,
            sending: { [weak self] event, values in self?.send(event, values) },
            reporting: { [weak self] property, event, value in self?.report(property, event, value) }
        ) {
            if let scroll = registered as? WinUIScrollView { follow(scroll) }
            if let popover = registered as? WinUIPopoverView { popover.anchor = { [weak self] in self?.popoverAnchor } }
            return registered
        }
        guard !NodeType.viewlessTypes.contains(type) else { return nil }

        switch type {
        case .page, .overlay: return WinUISingleChildView()
        case .navigationStack: return WinUINavigationView()
        case .navigationSplitView: return WinUISplitView()
        case .tabView: return WinUITabbedView()
        default: return WinUIUnsupportedView(type)
        }
    }

    /// Whether the host shows an entry as unsupported: no registration makes it, and it is no page's, no part of
    /// another view and no structure.
    static func showsUnsupported(_ type: NodeType) -> Bool {
        !WinUIRegistrations.registry.realization.elements.contains(type.name)
            && !NodeType.viewlessTypes.contains(type) && !NodeType.pageTypes.contains(type) && type != .overlay
    }

    /// Puts the changed properties on the element - a patch's or a frame's, the program's write either way: its
    /// registration's first, then what every element takes.
    /// Design: docs/design/host/patches.md#program-write
    func applyProperties(changed: Set<Prop>) {
        guard let view else {
            if !changed.isDisjoint(with: MountedElement.arrangedProperties) { parent?.invalidateMeasurements() }
            return
        }

        let taken = WinUIRegistrations.registry.apply(
            changed, to: view, of: type,
            reading: { [element] in element.value($0) },
            carriedIn: { [element] in element.driven[$0]?.mode == .in })

        let own = changed.subtracting(taken)
        for property in own {
            switch property {
            case .opacity: view.setOpacity(value(.opacity)?.number ?? 1)
            case .isVisible: view.setShown(isShown)
            // Ignored, the view and all in it are passed over: a click goes to what is under it.
            case .ignoresInput: view.setIgnoresInput(element.bool(.ignoresInput) == true)
            case .hint:
                if let hint = value(.hint)?.string {
                    hint.withCString { swiftomniui_winui_set_tooltip(view.handle, $0) }
                } else {
                    swiftomniui_winui_set_tooltip(view.handle, nil)
                }
            case .background: (view as? WinUILayoutView)?.setBackground(value(.background))
            case .contentPadding where type == .page:
                (view as? WinUISingleChildView)?.padding = element.insets(.contentPadding)
            default: break
            }
        }
        if !own.isDisjoint(with: MountedElement.transformProperties) { view.setTransform(element.drawingTransform) }
        if !own.isDisjoint(with: MountedElement.accessibilityProperties) {
            view.setAccessibility(element.accessibilityWords)
        }
        if let layers = view as? WinUIZStackView { layers.placement = element.placement }

        if !changed.subtracting(element.ownPlacementRun).isSubset(of: MountedElement.unmeasuredProperties) {
            invalidateMeasurements()
        }
    }

    /// Forgets the sizes kept by this element's layout and every one above it, and asks WinUI to measure again.
    func invalidateMeasurements() {
        var invalidated: Set<ObjectIdentifier> = []
        func invalidate(_ view: WinUIView?) {
            guard let view, invalidated.insert(ObjectIdentifier(view)).inserted else { return }
            (view as? WinUILayoutView)?.forgetMeasurements()
            view.invalidateMeasure()
        }
        var element: WinUIElement? = self
        while let each = element {
            // An entry of an List is measured by its cell; the list's own size never follows its items.
            if let items = each.parent?.view as? WinUIItemsView {
                items.remeasure(each.element)
                break
            }
            invalidate(each.view)
            // A popover's card is its own room: nothing its content asks reaches the layout its anchor stands in.
            if each.type == .popover { break }
            element = each.parent
        }

        // Native panels report zero DesiredSize; marking only a changed descendant can skip the
        // placing parents even after their Swift arithmetic was discarded.
        var layout = (view ?? parent?.nearestView)?.placingLayout
        while let parent = layout {
            // Most placing parents are also mounted ancestors. Only the extra
            // native layouts (notably scroll documents) need another invalidation.
            invalidate(parent)
            layout = (parent as? WinUIScrollDocument)?.scrollView ?? parent.placingLayout
        }
    }

    /// Hands the scroller's reports to this element, and its wish for the display's frames to the renderer.
    private func follow(_ scroll: WinUIScrollView) {
        scroll.onOffsetChanged = { [weak self] old, new in self?.scrolled(from: old, to: new) }
        scroll.onScrollStopped = { [weak self] in self?.send(.scrollStopped, []) }
        scroll.onFramesWanted = { [weak self, weak scroll] in
            if let scroll { self?.host?.runtime.frames.serve(scroll, order: scroll.number) }
        }
    }

    /// The view of this element or the nearest one above it.
    var nearestView: WinUIView? {
        view ?? parent?.nearestView
    }

    /// The view a popover's card stands beside: what the element it hangs off shows - that element's view, else
    /// the first view of its content, else the nearest view above it.
    var popoverAnchor: WinUIView? {
        guard let parent else { return nil }
        if let view = parent.view { return view }
        return parent.element.arrangedChildren.lazy.compactMap(\.presentingElement).first?.winUI.view
            ?? parent.nearestView
    }
}
