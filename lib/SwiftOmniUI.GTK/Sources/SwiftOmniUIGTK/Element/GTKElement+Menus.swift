// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// A view's context menu on GTK: the menu its element declares, offered again as its entries change.
/// Design: docs/design/platforms/gtk/pages.md#menus
extension GTKElement {
    /// Offers the menu a context menu declares on the view it stands on: the view this element is, or the one a menu
    /// or an entry of it stands under. A menu of no entries is none.
    func offerContextMenu() {
        guard let view else { return }
        let declared = element.children.first { $0.type == .contextMenu }
        guard contextMenuChanged || (view.contextMenu != nil && declared == nil) else { return }
        contextMenuChanged = false
        let menu = declared.map { GTKMenu(MenuEntry.entries(of: $0)) }
        guard let menu, !menu.isEmpty else {
            view.contextMenu = nil
            return
        }
        if let shown = view.contextMenu {
            if !menu.stands(like: shown.menu) { shown.show(menu) }
        } else {
            view.contextMenu = GTKContextMenu(menu, on: view.widget)
        }
    }
}

extension NodeType {
    /// The elements a menu is made of.
    static let menuTypes: Set<NodeType> = [.contextMenu, .menu, .menuItem, .divider]
}
