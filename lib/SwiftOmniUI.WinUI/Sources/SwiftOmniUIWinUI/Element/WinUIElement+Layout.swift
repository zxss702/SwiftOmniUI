// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// Children placed: the layout item each child gives its parent.
extension WinUIElement {
    /// The view lays out, and its control writes, in the element's direction.
    func directionChanged() {
        view?.setDirection(element.layoutDirection)
    }

    /// Hands a layout its children's items, in order - a page's slots furnish it and stand in none of its room - and
    /// a label the runs of its spans.
    func arrangeChildren() {
        if let items = view as? WinUIItemsView { return items.childrenChanged() }
        if let lazy = view as? WinUILazyView {
            if lazy.cells.takeItems() {
                lazy.measured = [:]
                lazy.invalidateMeasurements()
            }
            lazy.direction = element.layoutDirection
            lazy.setItems(element.arrangedChildren.compactMap { child in
                guard case .manual(let identity) = child.id, let item = child.winUI.layoutItem
                else { return nil }
                return (child.lazyIdentity ?? identity, item)
            })
            return
        }
        if let label = view as? WinUILabelView {
            return arrangeRuns(of: label)
        }
        let arranged = (type == .navigationStack ? element.stackedChildren : element.arrangedChildren).map(\.winUI)

        if let button = view as? WinUIButtonView, let face = arranged.first?.view {
            swiftomniui_winui_button_set_face(button.handle, face.handle)
            return
        }

        if let menu = view as? WinUIMenuButtonView {
            // The menu is a slot's - the layout never places it, so it is read among the element's own children.
            menu.setFace(arranged.first?.view)
            menu.show(WinUIMenu(element.children.first { $0.type == .contextMenu }?.winUI))
            return
        }
        if let split = view as? WinUISplitView {
            split.detailWidthBounds = arranged.count > 2
                ? arranged.last?.element.pageValue(.preferredColumnWidth)?.numbers : nil
            split.sidebarPaneLength = arranged.first?.element.pageValue(.preferredColumnWidth)?.numbers
            split.contentPaneLength = arranged.count > 2
                ? arranged[1].element.pageValue(.preferredColumnWidth)?.numbers
                : nil
        }
        if let custom = view as? WinUICustomLayoutView {
            custom.direction = element.layoutDirection
            custom.setItems(
                arranged.compactMap(\.layoutItem),
                layout: CoreLink().customLayout(for: element.id))
            return
        }
        let layout = view as? WinUILayoutView
        layout?.direction = element.layoutDirection
        layout?.setItems(arranged.compactMap(\.layoutItem))
    }

    /// A label's spans as runs of its words (`MountedElement.textRuns`); without spans, its own words, once the runs
    /// are gone.
    private func arrangeRuns(of label: WinUILabelView) {
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
    var layoutItem: WinUILayoutItem? {
        guard let view else { return children.lazy.compactMap(\.layoutItem).first }

        var item = WinUILayoutItem(view: view, values: element.layoutValues, isShown: isShown)
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
    var layoutParent: WinUIElement? {
        guard let parent else { return nil }
        return parent.view != nil ? parent : parent.layoutParent
    }
}
