// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore

/// Which element's view shows an element, and what stands in a slot, the same on every host.
/// Design: docs/design/host/pages.md#slots
extension MountedElement {
    /// A divider drawn in content rather than interpreted by a menu.
    public var isLayoutDivider: Bool {
        type == .divider && parent?.enclosing(type: .menu) == nil
            && parent?.enclosing(type: .menuBar) == nil && parent?.enclosing(type: .contextMenu) == nil
    }

    /// The minor axis of the containing stack; horizontal outside a stack.
    public var dividerAxis: Axis {
        var container = parent
        while let held = container, held.type == .grid { container = held.parent }
        return container?.type == .hStack || container?.type == .lazyHStack ? .vertical : .horizontal
    }

    /// The element whose view shows this one: itself where it presents a view, else the first under it that does.
    public var presentingElement: MountedElement? {
        native.presentsView ? self : children.lazy.compactMap(\.presentingElement).first
    }

    /// The children a layout places: all of them, but the slots, which furnish the chrome and the menus wherever
    /// they are written and stand in no one's room.
    public var arrangedChildren: [MountedElement] {
        guard children.contains(where: { NodeType.slotTypes.contains($0.type) }) else { return children }
        return children.filter { !NodeType.slotTypes.contains($0.type) }
    }

    /// Current content, excluding branches retained only for their removal transition.
    public var currentChildren: [MountedElement] {
        guard children.contains(where: { $0.isDeparting || NodeType.slotTypes.contains($0.type) }) else {
            return children
        }
        return children.filter { !$0.isDeparting && !NodeType.slotTypes.contains($0.type) }
    }

    /// What stands in this element's `slot` - a page's title view, a title bar's content: the first element under
    /// the slot with a view; nil where none.
    public func slotContent(_ slot: NodeType) -> MountedElement? {
        children.first { $0.type == slot }?.children.lazy.compactMap(\.presentingElement).first
    }
}
