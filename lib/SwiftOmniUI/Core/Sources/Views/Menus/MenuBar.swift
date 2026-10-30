// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The desktop menu bar: a page writes its menus into its session, and the
// platform puts them where it puts menus. A phone shows none of it.

/// A menu: a caption and the entries it opens - on the menu bar, or one level
/// down inside another menu.
///
///     page.menuBar = [
///         Menu("File") {
///             MenuItem("New").onClicked { create() }
///             Menu("Recent") {
///                 ForEach(recent) { file in
///                     MenuItem(file).onClicked { open(file) }
///                 }
///             }
///             Divider()
///             MenuItem("Close").onClicked { close() }
///         },
///     ]
///
/// Not a view: a menu belongs to a page, written into the page's session.
public struct Menu: View, ModifiableElement {
    /// The node this menu describes.
    public var node: Node

    /// A menu captioned `text`, holding whatever the closure lists.
    ///
    /// What goes inside is a `MenuItem`, a `Menu` or a `Divider`, with an
    /// `if` or a `ForEach` among them.
    ///
    /// - Parameter text: the caption - "File", "Edit", "View" on the bar, or the
    ///   row that opens it inside another menu.
    /// - Parameter items: the entries, in the order they are written.
    @_disfavoredOverload public init<S: StringProtocol>(_ text: S, @ViewBuilder items: () -> any View) {
        node = Node(contract: MenuContract.self, children: items().environment(\.isMenuContent, true).labelStyle(.titleAndIcon).node.asChildren)
        node.write(MenuContract.text, String(text))
    }

    /// A menu captioned what `key` looks up - `Menu("File")` looks "File" up,
    /// as SwiftUI's does.
    public init(_ key: LocalizedStringKey, @ViewBuilder items: () -> any View) {
        node = Node(contract: MenuContract.self, children: items().environment(\.isMenuContent, true).labelStyle(.titleAndIcon).node.asChildren)
        node.write(MenuContract.text, key.displayString)
        node.write(MenuContract.textKey, key)
    }

    /// The node, as every element answers it.

    /// Who this menu is among the page's others, so it stays matched to itself
    /// when the menus around it come and go; without one it is matched by
    /// position.
    public func id(_ value: some Hashable) -> Self {
        var copy = self
        copy.node.id = String(describing: value)
        return copy
    }

    /// Whether the menu opens at all.
    public func disabled(_ value: Bool) -> Self {
        var copy = self
        copy.node.disable(value)
        return copy
    }

    /// A menu that lives in the view: a button whose label opens `content`'s
    /// entries - `MenuItem`s, `Divider`s and nested `Menu`s:
    ///
    ///     Menu {
    ///         ForEach(providers) { MenuItem($0.name).onClicked { pick($0) } }
    ///     } label: {
    ///         Text(chosen.name)
    ///     }
    ///     .menuStyle(.borderlessButton)
    ///
    /// The label is the trigger the menu opens from; the entries are a slot
    /// child, as a context menu's are, never laid out.
    ///
    /// - Parameters:
    ///   - content: the entries, in the order they are shown.
    ///   - label: the trigger shown in the view.
    public init(@ViewBuilder content: @escaping () -> any View, @ViewBuilder label: () -> any View) {
        node = Node(contract: MenuButtonContract.self)
        node.children = label().node.asChildren
        node.children.append(RequestedMenuContent(content: content).node)
    }

    /// A menu button captioned `text`.
    ///
    /// The label is spelled out rather than inferred: `Menu("x") { ... }`
    /// alone names the menu-bar menu, so the button form keeps its own
    /// signature.
    @_disfavoredOverload public init<S: StringProtocol>(title text: S, @ViewBuilder content: @escaping () -> any View) {
        self.init(content: content) { Text(text) }
    }

    /// The same, the trigger's words looked up.
    public init(title key: LocalizedStringKey, @ViewBuilder content: @escaping () -> any View) {
        self.init(content: content) { Text(key) }
    }
}

/// Retain a menu level after its first native request, while unopened submenus remain unbuilt.
/// A closed trigger must not start the content's onAppear/tasks (for example, recursive directory listings).
private struct RequestedMenuContent: View {
    @State private var requested = false
    let content: () -> any View

    var body: some View {
        let supported = HostRealizations.current.members.contains {
            $0.owner == MenuButtonContract.name && $0.member == MenuButtonContract.contentRequested.name
        }
        var slot = Node(contract: ContextMenuContract.self)
        if supported {
            let request = _requested
            slot.addHandler(ContextMenuContract.contentRequested.token) {
                if !request.wrappedValue { request.wrappedValue = true }
            }
        }
        slot.children = requested || !supported
            ? content().environment(\.isMenuContent, true).labelStyle(.titleAndIcon).node.asChildren
            : Text("…").node.asChildren
        return ModifiedContent(node: slot)
    }
}

extension Menu {
    /// How the trigger draws - `.borderlessButton` for a bare label that opens
    /// its menu, `.bordered` for the desktop's ordinary menu button:
    ///
    ///     Menu { MenuItem("One").onClicked { pick(1) } } label: { Text("Pick") }
    ///         .menuStyle(.borderlessButton)
    public func menuStyle(_ style: some MenuStyle) -> Self {
        var copy = self
        copy.node.write(MenuButtonContract.menuStyle, style.menuStyleToken)
        return copy
    }

    /// Whether the trigger shows the mark that says it opens a menu.
    public func menuIndicator(_ visibility: MenuIndicatorVisibility) -> Self {
        var copy = self
        copy.node.write(MenuButtonContract.menuIndicator, visibility)
        return copy
    }
}

/// One entry in a menu.
///
///     MenuItem("Save") { save() }
public struct MenuItem: View, MenuItemElement {
    /// The node this entry describes.
    public var node: Node

    /// An entry captioned `text`. Give it an `.onClicked`: an entry that does
    /// nothing is one that looks broken.
    @_disfavoredOverload public init<S: StringProtocol>(_ text: S) {
        node = Node(contract: MenuItemContract.self)
        node.write(MenuItemElementContract.text, String(text))
    }

    /// An entry captioned what `key` looks up - `MenuItem("Save")` looks
    /// "Save" up, as SwiftUI's does.
    public init(_ key: LocalizedStringKey) {
        node = Node(contract: MenuItemContract.self)
        node.write(MenuItemElementContract.text, key.displayString)
        node.write(MenuItemElementContract.textKey, key)
    }

    /// An entry captioned `title`, running `action` when chosen - the SwiftUI
    /// spelling of `MenuItem(title).onClicked(action)`.
    ///
    ///     MenuItem("Save") { save() }
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, action: @escaping EventHandler) {
        self = MenuItem(title).onClicked(action)
    }

    /// An entry captioned what `key` looks up, running `action` when chosen.
    public init(_ key: LocalizedStringKey, action: @escaping EventHandler) {
        self = MenuItem(key).onClicked(action)
    }

    /// The same, marked as a destructive action where the platform marks one.
    public init(_ key: LocalizedStringKey, role: ButtonRole, action: @escaping EventHandler) {
        self = MenuItem(key).onClicked(action).isDestructive(role == .destructive)
    }

    /// The node, as every element answers it.

    /// Who this entry is among the menu's others, so it stays matched to itself
    /// when the entries around it come and go; without one it is matched by
    /// position.
    public func id(_ value: some Hashable) -> Self {
        modified { $0.id = String(describing: value) }
    }
}

/// A line between entries, grouping the ones above it apart from the ones
/// below.
///
///     Menu("File") {
///         MenuItem("New") { create() }
///         Divider()
///         MenuItem("Close") { close() }
///     }
///
/// It has no caption and nothing to click; the platform draws whatever a
/// separator looks like there.
public struct Divider: View {
    /// The node this separator describes.
    public var node: Node

    /// A line.
    public init() {
        node = Node(contract: DividerContract.self)
    }

    /// The node, as every element answers it.

    /// Who this separator is, among the menu's others - worth giving one when
    /// entries come and go around it.
    public func id(_ value: some Hashable) -> Self {
        var copy = self
        copy.node.id = String(describing: value)
        return copy
    }
}

