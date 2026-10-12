// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIGTK

/// The widget: made, and given the element's properties.
extension GTKElement {
    func makeView() -> GTKView? {
        if element.isLayoutDivider {
            let axis = element.dividerAxis
            return GTKView { _ in
                gtk_separator_new(axis == .vertical ? GTK_ORIENTATION_VERTICAL : GTK_ORIENTATION_HORIZONTAL)
            }
        }
        if type == .list, let host { return GTKItemsView(cells: ItemsCells(element, in: host.runtime)) }
        if type == .lazyVStack || type == .lazyHStack, let host {
            return GTKLazyStackView(
                axis: type == .lazyVStack ? .vertical : .horizontal,
                cells: LazyCells(element, in: host.runtime))
        }
        if type == .lazyVGrid || type == .lazyHGrid, let host {
            return GTKLazyGridView(
                axis: type == .lazyVGrid ? .vertical : .horizontal,
                cells: LazyCells(element, in: host.runtime))
        }
        // A child its parent's view draws - a map's marker - has no view of its own.
        if element.isDrawnByParent(in: GTKRegistrations.registry) { return nil }
        if let registered = GTKRegistrations.registry.makeView(
            for: type,
            sending: { [weak self] event, values in self?.send(event, values) },
            reporting: { [weak self] property, event, value in self?.report(property, event, value) }
        ) {
            if let scroll = registered as? GTKScrollView { follow(scroll) }
            if let popover = registered as? GTKPopoverView { popover.anchor = { [weak self] in self?.popoverAnchor } }
            return registered
        }

        guard !NodeType.viewlessTypes.contains(type) else { return nil }

        switch type {
        case .page: return GTKSingleChildView()
        case .overlay:
            let overlay = GTKSingleChildView()
            overlay.passesBeside = true
            return overlay
        case .navigationStack:
            guard element.parent?.enclosing(type: .page)?.enclosing(type: .navigationStack) != nil
            else { return GTKNavigationView() }
            let stack = GTKSingleChildView()
            stack.holdsOnlyFirstItem = true
            return stack
        case .navigationSplitView: return GTKSplitView()
        case .tabView: return GTKTabbedView()
        default: return GTKUnsupportedView(type)
        }
    }

    /// Whether the host shows an entry as unsupported: no registration makes it, and it is no page's, no part of
    /// another view and no structure.
    static func showsUnsupported(_ type: NodeType) -> Bool {
        !GTKRegistrations.registry.realization.elements.contains(type.name) && !NodeType.viewlessTypes.contains(type)
            && !NodeType.pageTypes.contains(type) && type != .overlay
    }

    /// Puts the changed properties on the widget - a patch's or a frame's, the program's write either way: its
    /// registration's first, then what every element takes.
    /// Design: docs/design/host/patches.md#program-write
    func applyProperties(changed: Set<Prop>) {
        guard let view else {
            if !changed.isDisjoint(with: MountedElement.arrangedProperties) { parent?.invalidateMeasurements() }
            return
        }

        let taken = GTKRegistrations.registry.apply(
            changed, to: view, of: type,
            reading: { [element] in element.value($0) },
            carriedIn: { [element] in element.driven[$0]?.mode == .in })

        let own = changed.subtracting(taken)
        for property in own {
            switch property {
            case .opacity: view.setOpacity(value(.opacity)?.number ?? 1)
            case .isEnabled: view.setEnabled(value(.isEnabled)?.bool ?? true)
            case .isVisible: view.setShown(isShown)
            case .hint:
                value(.hint)?.string?.withCString { gtk_widget_set_tooltip_text(view.widget, $0) }
                    ?? gtk_widget_set_tooltip_text(view.widget, nil)
            case .background: (view as? GTKLayoutView)?.setBackground(value(.background))
            case .contentPadding where type == .page:
                (view as? GTKSingleChildView)?.padding = element.insets(.contentPadding)
            default: break
            }
        }
        if !own.isDisjoint(with: MountedElement.transformProperties) { view.setTransform(element.drawingTransform) }
        if !own.isDisjoint(with: MountedElement.accessibilityProperties) {
            view.setAccessibility(element.accessibilityWords)
        }
        if let layers = view as? GTKZStackView { layers.placement = element.placement }
        if own.contains(.allowDrop) || view.drop != nil { configureDropTarget(for: view) }

        if !changed.subtracting(element.ownPlacementRun).isSubset(of: MountedElement.unmeasuredProperties) {
            invalidateMeasurements()
        }
    }

    /// Forgets the sizes kept by this element's layout and every one above it, and asks GTK to measure again.
    func invalidateMeasurements() {
        var element: GTKElement? = self
        while let each = element {
            // An entry of an List is measured by its cell; the list's own size never follows its items.
            if let items = each.parent?.view as? GTKItemsView {
                items.remeasure(each.element)
                break
            }
            (each.view as? GTKLayoutView)?.forgetMeasurements()
            each.view?.invalidateMeasure()
            // A popover is its own room: nothing its content asks reaches the layout its anchor stands in.
            if each.type == .popover { break }
            element = each.parent
        }

    }

    /// Hears the scroller's movement on the display's frames: where it went, and that it came to rest.
    private func follow(_ scroll: GTKScrollView) {
        scroll.onOffsetChanged = { [weak self] old, new in self?.scrolled(from: old, to: new) }
        scroll.onScrollStopped = { [weak self] in self?.send(.scrollStopped, []) }
        scroll.onFramesWanted = { [weak self, weak scroll] in
            if let scroll { self?.host?.runtime.frames.serve(scroll, order: scroll.number) }
        }
    }

    /// The view of this element or the nearest one above it.
    var nearestView: GTKView? {
        view ?? parent?.nearestView
    }

    /// The view a popover stands beside: what the element it hangs off shows - that element's view, else the first
    /// view of its content, else the nearest view above it.
    var popoverAnchor: GTKView? {
        guard let parent else { return nil }
        if let view = parent.view { return view }
        return parent.element.arrangedChildren.lazy.compactMap(\.presentingElement).first?.gtk.view
            ?? parent.nearestView
    }
}
