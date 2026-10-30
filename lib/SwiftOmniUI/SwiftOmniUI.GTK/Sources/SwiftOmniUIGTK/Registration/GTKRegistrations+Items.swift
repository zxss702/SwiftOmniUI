// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

extension GTKRegistrations {
    /// An List: GTK's own list view or grid view, which the host makes itself - its rows ask the tree for what
    /// they hold (`ItemsCells`). Its entries, layout and choice; the user's choosing, activating and reaching the
    /// end; and the cells it holds.
    static func items(_ registry: Registry<GTKView>) {
        registry.add(ListContract.self, madeByHost: GTKItemsView.self) { list in
            list.applies([
                ListContract.items, ListContract.itemsLayout, ListContract.listStyle,
                ListContract.selectionMode,
                ListContract.selectedItems, ListContract.endReachedWithin,
            ]) { view, values in
                view.apply(
                    layout: values[ListContract.itemsLayout] ?? .list(),
                    style: values[ListContract.listStyle] ?? .automatic,
                    mode: values[ListContract.selectionMode] ?? .none)
            }
            list.raises(ListContract.selectionChanged)
            list.raises(ListContract.itemActivated)
            list.raises(ListContract.endReached)
            list.raises(ListContract.realizedChanged)
        }
    }
}
