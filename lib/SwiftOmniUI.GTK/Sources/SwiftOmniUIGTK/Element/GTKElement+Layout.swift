// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIGTK

/// Children placed: the layout item each child gives its parent.
extension GTKElement {
    /// The view lays out, and its control writes, in the element's direction.
    func directionChanged() {
        view?.setDirection(element.layoutDirection == .rightToLeft ? GTK_TEXT_DIR_RTL : GTK_TEXT_DIR_LTR)
    }

    /// Hands a layout its children's items, in order - a page's slots furnish its header bar and stand in none of
    /// its room - and a label the runs of its spans.
    func arrangeChildren() {
        if let items = view as? GTKItemsView { return items.childrenChanged() }
        if let lazy = view as? GTKLazyView {
            if lazy.cells.takeItems() {
                lazy.invalidateMeasurements()
            }
            lazy.direction = element.layoutDirection
            lazy.setItems(element.arrangedChildren.compactMap { child in
                guard case .manual(let identity) = child.id, let item = child.gtk.layoutItem
                else { return nil }
                return (child.lazyIdentity ?? identity, item)
            })
            return
        }
        if let label = view as? GTKLabelView {
            return arrangeRuns(of: label)
        }
        let arranged = (type == .navigationStack ? element.stackedChildren : element.arrangedChildren).map(\.gtk)

        if let button = view as? GTKButtonView {
            button.setFace(arranged.lazy.compactMap(\.layoutItem).first?.view)
            return
        }

        if let menu = view as? GTKMenuButtonView {
            // The menu is a slot's - the layout never places it, so it is read among the element's own children.
            let entries = element.children.first { $0.type == .contextMenu }
                .map { MenuEntry.entries(of: $0) } ?? []
            menu.setFace(arranged.lazy.compactMap(\.layoutItem).first?.view)
            menu.setEntries(entries)
            return
        }
        (view as? GTKNavigationView)?.titles = arranged.map { child in
            // A badge stands by its page's title in brackets, the way the
            // platform counts in tab labels.
            let title = child.element.visiblePage?.pageValue(.title)?.string ?? ""
            guard let badge = child.element.visiblePage?.pageValue(.badge)?.string, !badge.isEmpty else { return title }
            return title.isEmpty ? badge : "\(title) (\(badge))"
        }
        (view as? GTKSplitView)?.framedPanes = arranged.map {
            Self.framedTypes.contains($0.type) && !($0.type == .page && $0.element.contentArrangement != nil)
        }
        (view as? GTKSplitView)?.detailWidthBounds = arranged.count > 2
            ? arranged.last?.element.pageValue(.preferredColumnWidth)?.numbers : nil
        (view as? GTKSplitView)?.sidebarWidthBounds = arranged.first?.element.pageValue(.preferredColumnWidth)?.numbers
        (view as? GTKSplitView)?.contentWidthBounds = arranged.count > 2
            ? arranged[1].element.pageValue(.preferredColumnWidth)?.numbers
            : nil
        if let custom = view as? GTKCustomLayoutView {
            custom.direction = element.layoutDirection
            custom.setItems(
                arranged.compactMap(\.layoutItem),
                layout: CoreLink().customLayout(for: element.id))
            return
        }
        let layout = view as? GTKLayoutView
        layout?.direction = element.layoutDirection
        layout?.setItems(arranged.compactMap(\.layoutItem))
    }

    /// A label's spans as runs of its words (`MountedElement.textRuns`); without spans, its own words, once the runs
    /// are gone.
    private func arrangeRuns(of label: GTKLabelView) {
        guard let runs = element.textRuns else {
            if hasRuns {
                hasRuns = false
                label.setRuns(nil)
            }
            return
        }
        hasRuns = true
        label.setRuns(runs)
    }

    /// What this element gives the layout it stands in: its view, or the first view of an element drawn by its parent.
    var layoutItem: GTKLayoutItem? {
        // A popover stands in no layout: its `GtkPopover` holds it.
        guard type != .popover else { return nil }
        guard let view else {
            // What a departing element passes up departs with it.
            guard var item = children.lazy.compactMap(\.layoutItem).first else { return nil }
            if element.isDeparting { item.departing = true; item.isShown = false }
            return item
        }

        // A child riding its removal transition stands where it last stood, outside the layout's room.
        var item = GTKLayoutItem(view: view, values: element.layoutValues, isShown: isShown && !element.isDeparting)
        item.element = element
        item.mount = element.mount
        item.codeId = element.id
        item.departing = element.isDeparting
        if fadesIn {
            item.fadeIn = { [weak self] animation, room in self?.fadeIn(under: animation, room: room) }
        }
        return item
    }

    /// Whether the view is shown: as the tree says, or while it fades out.
    var isShown: Bool {
        element.standsShown
    }

    /// The element whose layout places this one: the nearest above it with a view.
    var layoutParent: GTKElement? {
        guard let parent else { return nil }
        return parent.view != nil ? parent : parent.layoutParent
    }
}
