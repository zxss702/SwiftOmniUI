// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// An action in the page's native navigation or toolbar surface.
///
///     struct NotesPage: View {
///         @Environment private var page: PageSession
///
///         var content: any View {
///             VStack { … }
///                 .onAppear {
///                     page.title = "Notes"
///                     page.toolbarItems = [
///                         ToolbarItem("Save") { save() },
///                         ToolbarItem("Delete", placement: .overflow) { delete() },
///                     ]
///                 }
///         }
///     }
///
/// A toolbar item is page furniture rather than a layout view. It carries a
/// caption, an optional image, presentation policy and a handler, and is
/// written into the page's session whenever that collection changes - or
/// stands in `.toolbar { … }`, which writes the same nodes.
public struct ToolbarItem: Element, MenuItemElement {
    /// The node this item describes.
    public var node: Node

    /// An item captioned `text`. Give it an `.onClicked`: an item that does
    /// nothing is one that looks broken.
    @_disfavoredOverload public init<S: StringProtocol>(_ text: S) {
        node = Node(contract: ToolbarItemContract.self)
        node.write(MenuItemElementContract.text, String(text))
    }

    /// An item captioned what `key` looks up.
    public init(_ key: LocalizedStringKey) {
        node = Node(contract: ToolbarItemContract.self)
        node.write(MenuItemElementContract.text, key.displayString)
        node.write(MenuItemElementContract.textKey, key)
    }

    /// An item captioned `text`, running `action` when it is picked.
    @_disfavoredOverload public init<S: StringProtocol>(_ text: S, action: @escaping EventHandler) {
        self.init(text)
        node.addHandler(MenuItemElementContract.clicked.token, action)
    }

    /// The same, captioned what `key` looks up.
    public init(_ key: LocalizedStringKey, action: @escaping EventHandler) {
        self.init(key)
        node.addHandler(MenuItemElementContract.clicked.token, action)
    }

    /// An item captioned `text`, in `placement`, running `action`.
    @_disfavoredOverload public init<S: StringProtocol>(_ text: S, placement: ToolbarItemPlacement, action: @escaping EventHandler) {
        self.init(text, action: action)
        node.write(ToolbarItemContract.placement, placement)
    }

    /// An icon item running `action`, its caption as the platform's tooltip -
    /// `ToolbarItem("Back", icon: .symbol("chevron.left")) { back() }`.
    @_disfavoredOverload public init<S: StringProtocol>(_ text: S, icon: ImageSource, action: @escaping EventHandler) {
        self.init(text, action: action)
        node.write(MenuItemElementContract.icon, icon)
    }

    /// The same, a system symbol by name - the SwiftUI `systemImage` spelling.
    ///
    ///     ToolbarItem("Home", systemImage: "house") { nav.home() }
    @_disfavoredOverload public init<S: StringProtocol>(_ text: S, systemImage: String, action: @escaping EventHandler) {
        self.init(text, icon: .symbol(systemImage), action: action)
    }

    /// The same, its caption looked up.
    public init(_ key: LocalizedStringKey, systemImage: String, action: @escaping EventHandler) {
        self.init(key, action: action)
        node.write(MenuItemElementContract.icon, .symbol(systemImage))
    }

    /// An icon item in `placement`, running `action`.
    @_disfavoredOverload public init<S: StringProtocol>(_ text: S, systemImage: String, placement: ToolbarItemPlacement, action: @escaping EventHandler) {
        self.init(text, systemImage: systemImage, action: action)
        node.write(ToolbarItemContract.placement, placement)
    }

    /// The same, its caption looked up.
    public init(_ key: LocalizedStringKey, systemImage: String, placement: ToolbarItemPlacement, action: @escaping EventHandler) {
        self.init(key, systemImage: systemImage, action: action)
        node.write(ToolbarItemContract.placement, placement)
    }

    /// An item showing `content` itself on the bar - a `Button`, a `Toggle`,
    /// any view - the SwiftUI spelling:
    ///
    ///     .toolbar {
    ///         ToolbarItem(placement: .confirmationAction) {
    ///             Button("Done") { done() }
    ///         }
    ///     }
    ///
    /// More than one view stands side by side in the item's room, as
    /// SwiftUI's does.
    public init<Content: View>(
        placement: ToolbarItemPlacement = .automatic,
        @ViewBuilder content: () -> Content
    ) {
        node = Node(contract: ToolbarItemContract.self)
        node.write(ToolbarItemContract.placement, placement)
        let views = content().environment(\.isToolbarContent, true).labelStyle(.iconOnly).node.asChildren
        node.children = views.count > 1 ? [Node(contract: HStackContract.self, children: views)] : views
    }

    /// The node this item describes.

    /// Who this item is among the page's others, so an item inserted in the
    /// middle is matched to itself rather than to whichever item stood there.
    ///
    /// - Parameter value: distinct among the page's items, and the same value
    ///   across renders.
    public func id(_ value: some Hashable) -> Self {
        var copy = self
        copy.node.id = String(describing: value)
        return copy
    }

    /// Whether it sits on the bar itself or behind the overflow menu.
    @_spi(Host) public func placement(_ value: ToolbarItemPlacement) -> Self { setValue(ToolbarItemContract.placement, value) }

    /// Where this item sorts among items in the same order group.
    ///
    /// Lower values appear first; items of equal priority keep their order.
    @_spi(Host) public func priority(_ value: Int) -> Self { setValue(ToolbarItemContract.priority, value) }
}

extension ToolbarItem: ToolbarContent, ToolbarEntry {
    /// The item's node - what `.toolbar { … }` collects.
    var toolbarNodes: [Node] { [node] }
}
