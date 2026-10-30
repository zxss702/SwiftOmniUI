// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// Children placed: the layout item each child gives its parent.
extension AndroidElement {
    /// The view lays out, and its control writes, in the element's direction: View's LAYOUT_DIRECTION_LTR or _RTL.
    func directionChanged() {
        guard let view else { return }
        Java.call(view.reference, JavaAPI.setLayoutDirection, .int(element.layoutDirection == .rightToLeft ? 1 : 0))
    }

    /// Hands a layout its children's items, in order, and a label the runs of its spans.
    func arrangeChildren() {
        if let items = view as? AndroidItemsView { return items.childrenChanged() }
        if let lazy = view as? AndroidLazyView {
            if lazy.cells.takeItems() {
                lazy.measured = [:]
                lazy.invalidateMeasurements()
            }
            lazy.direction = element.layoutDirection
            lazy.setItems(element.arrangedChildren.compactMap { child in
                guard case .manual(let identity) = child.id, let item = child.android.layoutItem
                else { return nil }
                return (child.lazyIdentity ?? identity, item)
            })
            return
        }
        if let label = view as? AndroidLabelView {
            return arrangeRuns(of: label)
        }
        let layout = view as? AndroidLayoutView
        layout?.direction = element.layoutDirection
        layout?.setItems(element.arrangedChildren.compactMap { $0.android.layoutItem })
    }

    /// A label's spans as runs of its words, as the host layer reads them; without spans, its own words, once they
    /// are gone.
    private func arrangeRuns(of label: AndroidLabelView) {
        guard let runs = element.textRuns else {
            if hasRuns {
                hasRuns = false
                let textCase = value(.textCase)?.enumeration.flatMap(TextCase.init(rawValue:)) ?? .none
                label.setText(textCase.applied(to: value(.text)?.string ?? ""))
            }
            return
        }

        hasRuns = true
        label.setRuns(runs)
    }

    /// What this element gives the layout it stands in: its view, or the first view of an element drawn by its parent.
    var layoutItem: AndroidLayoutItem? {
        guard let view else { return children.lazy.compactMap(\.layoutItem).first }

        var item = AndroidLayoutItem(view: view, values: element.layoutValues, isShown: isShown)
        item.mount = element.mount
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
    var layoutParent: AndroidElement? {
        guard let parent else { return nil }
        return parent.view != nil ? parent : parent.layoutParent
    }
}
