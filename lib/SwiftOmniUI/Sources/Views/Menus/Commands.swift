// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// Something that can stand in a `.commands` block - a group spliced into the
/// platform's own menus, or a menu of its own - the way a `View` is something
/// that can stand in a layout. A composition of commands is a `Commands`
/// whose `body` lists them:
///
///     struct EditorCommands: Commands {
///         var body: some Commands {
///             CommandMenu("Run") {
///                 Button("Build") { build() }
///                     .keyboardShortcut("B", modifiers: .command)
///             }
///         }
///     }
///
/// and it stands in `.commands { … }` the way the menus themselves do. Inside
/// a group or menu the entries are views: a `Button` stands as a menu item,
/// its caption and icon read off its label, its `.keyboardShortcut` shown
/// beside it; a `Divider` a separator; a `Menu` a submenu.
@preconcurrency @MainActor public protocol Commands {
    /// What this commands value is made of, read each time it is built. A
    /// content that is itself an entry - a `CommandGroup`, a `CommandMenu` -
    /// has no body and declares none; its `Body` is `Never`.
    associatedtype Body = Never

    /// The commands this one is made of.
    @CommandsBuilder var body: Body { get }
}

extension Commands where Body == Never {
    /// An entry stands for itself; it is never read as a composition.
    public var body: Never { fatalError("\(Self.self) is commands itself - it has no body") }
}

/// A commands entry - a leaf producing menu nodes directly: a group, a menu,
/// a composition's entries. What `commandNodes` recognizes a leaf by, where
/// `body` is `Never`.
@MainActor protocol CommandsEntry {
    /// The menu nodes this entry stands for.
    var commandNodes: [Node] { get }
}

extension Commands {
    /// The menu nodes this content stands for - a leaf's own menu node, a
    /// composition's body's nodes, spliced in where the content is written so
    /// the differ keys every menu by where it stood.
    var commandNodes: [Node] {
        if let entry = self as? CommandsEntry { return entry.commandNodes }
        guard Body.self != Never.self else { return [] }
        return (body as? any Commands)?.commandNodes ?? []
    }
}

/// The entries a `CommandsBuilder` block of more than one statement makes -
/// never written by hand. Its nodes carry their written keys, and a
/// `.commands` block splices them into the window's menus.
public struct TupleCommands: Commands, CommandsEntry {
    /// The nodes, as written.
    var commandNodes: [Node] { nodes }

    /// The statements' nodes, each keyed by where it was written.
    let nodes: [Node]

    /// A tuple commands over already-keyed nodes.
    init(nodes: [Node]) {
        self.nodes = nodes
    }

    /// One more segment on each child's path: the differ knows the child by
    /// where it was written, not by where the commands land.
    func tagged(_ segment: String) -> TupleCommands {
        TupleCommands(nodes: nodes.map { child in
            var child = child
            child.key = child.key.map { "\(segment).\($0)" } ?? segment
            return child
        })
    }
}

// The result builder behind `.commands { … }`. As `ToolbarContentBuilder` does
// for toolbar entries, every method records where each menu was written - a
// path such as "1.else.0" that `Node.key` carries to the differ.

/// Collects the commands written as consecutive statements into one
/// `Commands` - a `TupleCommands` for more than one.
///
/// `if`, `if/else`, `switch` and `for`/`in` work inside one.
@resultBuilder
public enum CommandsBuilder {
    /// A single commands value written as a statement.
    public static func buildExpression<Content: Commands>(_ expression: Content) -> Content {
        expression
    }

    /// The statements' menus, in the order they are written, each keyed by
    /// its statement's number whatever the others produce.
    public static func buildBlock(_ components: (any Commands)...) -> TupleCommands {
        let components = Carry(components)
        return onMain {
            TupleCommands(nodes: components.value.enumerated().flatMap { at($0.offset, $0.element) })
        }
    }

    /// Nothing written: empty commands.
    public static func buildBlock() -> TupleCommands {
        onMain { TupleCommands(nodes: []) }
    }

    /// An `if` without an `else`; what it builds is keyed apart from the
    /// statement after it.
    public static func buildOptional(_ component: TupleCommands?) -> TupleCommands {
        let component = Carry(component)
        return onMain { component.value?.tagged("some") ?? TupleCommands(nodes: []) }
    }

    /// The `if` branch of an if/else.
    public static func buildEither(first component: TupleCommands) -> TupleCommands {
        let component = Carry(component)
        return onMain { component.value.tagged("if") }
    }

    /// The `else` branch. Its menus are keyed apart from the `if` branch's,
    /// so switching branches replaces the menus rather than editing them.
    public static func buildEither(second component: TupleCommands) -> TupleCommands {
        let component = Carry(component)
        return onMain { component.value.tagged("else") }
    }

    /// A `for` statement's turns, each keyed by its turn number.
    public static func buildArray(_ components: [TupleCommands]) -> TupleCommands {
        let components = Carry(components)
        return onMain { TupleCommands(nodes: components.value.enumerated().flatMap { turn in
            turn.element.nodes.map { node in
                var node = node
                node.key = node.key.map { "\(turn.offset).\($0)" } ?? String(turn.offset)
                return node
            }
        }) }
    }

    /// A `TupleCommands` where the call already produced one.
    public static func buildFinalResult(_ component: TupleCommands) -> TupleCommands {
        component
    }

    /// A statement's own type through, so a leaf's `Body` names it.
    public static func buildFinalResult<Content: Commands>(_ component: Content) -> Content {
        component
    }

    /// What an `if #available(…)` block builds, keyed like every other branch.
    public static func buildLimitedAvailability(_ component: TupleCommands) -> TupleCommands {
        let component = Carry(component)
        return onMain { component.value.tagged("available") }
    }

    /// The menus written under one statement, keyed by the statement's
    /// number - several, where one statement stands for more than one menu.
    private static func at(_ index: Int, _ content: any Commands) -> [Node] {
        // Builders run where the body that wrote them stood - the UI thread.
        let nodes = MainActor.assumeIsolated { Carry(content.commandNodes) }.value
        return nodes.enumerated().map { offset, child in
            var child = child
            let segment = nodes.count > 1 ? "\(index).\(offset)" : String(index)
            child.key = child.key.map { "\(segment).\($0)" } ?? segment
            return child
        }
    }
}

/// Entries replacing the platform's own at a region of its menus:
///
///     .commands {
///         CommandGroup(replacing: .appInfo) {
///             Button("About Editor") { showAbout() }
///             Divider()
///             Button("Settings") { openSettings() }
///                 .keyboardShortcut(",", modifiers: .command)
///         }
///     }
///
/// On macOS the entries stand in the application's menu in place of what the
/// region holds; on the platforms that keep an application menu on the
/// window's icon they stand there. A `Button` is a menu item, its caption
/// and icon read off its label, its `.keyboardShortcut` shown beside it; a
/// `Divider` is a separator.
public struct CommandGroup<Content: View>: Commands, CommandsEntry {
    /// The group's node - a menu element carrying its region instead of a
    /// caption, its entries the content's.
    var node: Node

    /// The node, as written.
    var commandNodes: [Node] { [node] }

    /// A group whose entries stand in `placement`'s region instead of what
    /// the platform put there.
    public init(replacing placement: CommandGroupPlacement, @ViewBuilder content: () -> Content) {
        node = Node(contract: MenuContract.self, children: content().environment(\.isMenuContent, true).labelStyle(.titleAndIcon).node.asChildren)
        node.write(MenuContract.placement, placement)
    }
}

/// A menu of the application's own on the menu surface:
///
///     .commands {
///         CommandMenu("Run") {
///             Button("Build") { build() }
///                 .keyboardShortcut("B", modifiers: .command)
///         }
///     }
///
/// Where a page's `menuBar` menus are the visible page's, a `CommandMenu` is
/// the scene's: it stands whichever page shows. The entries are views, as a
/// `CommandGroup`'s are.
public struct CommandMenu<Content: View>: Commands, CommandsEntry {
    /// The menu's node.
    var node: Node

    /// The node, as written.
    var commandNodes: [Node] { [node] }

    /// A menu captioned `title`, holding whatever the closure lists.
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {
        node = Node(contract: MenuContract.self, children: content().environment(\.isMenuContent, true).labelStyle(.titleAndIcon).node.asChildren)
        node.write(MenuContract.text, String(title))
    }

    /// A menu captioned what `key` looks up.
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        node = Node(contract: MenuContract.self, children: content().environment(\.isMenuContent, true).labelStyle(.titleAndIcon).node.asChildren)
        node.write(MenuContract.text, titleKey.displayString)
        node.write(MenuContract.textKey, titleKey)
    }
}

extension Scene {
    /// The commands the scene's windows share - menus of the application's
    /// own and entries spliced into the platform's, whichever page shows:
    ///
    ///     var body: some Scene {
    ///         DocumentScene()
    ///             .commands { EditorCommands() }
    ///     }
    public func commands<Content: Commands>(@CommandsBuilder _ content: () -> Content) -> some Scene {
        CommandsScene(base: self, commands: content())
    }
}

/// A scene with commands offered to its windows.
struct CommandsScene<Content: Commands>: Scene {
    /// The scene the commands are offered to.
    let base: any Scene

    /// The commands.
    let commands: Content

    /// The scene's windows, its commands added to what they offer.
    var windows: Windows {
        var windows = base.windows
        windows.commands.append(commands)
        return windows
    }
}

extension Windows {
    /// The commands the scene's windows share, as `.commands` on a scene
    /// gives them:
    ///
    ///     Windows { … } main: { MainWindow() }
    ///         .commands { EditorCommands() }
    public func commands<Content: Commands>(@CommandsBuilder _ content: () -> Content) -> Windows {
        var copy = self
        copy.commands.append(content())
        return copy
    }
}

extension WindowGroup {
    /// The commands the group's windows offer - menus of the application's
    /// own and entries spliced into the platform's, standing whichever page
    /// shows:
    ///
    ///     WindowGroup(.document, for: Document.ID.self) { $id in DocumentWindow(id: id) }
    ///         .commands {
    ///             CommandGroup(replacing: .appInfo) {
    ///                 Button("About") { showAbout() }
    ///             }
    ///         }
    public func commands<Content: Commands>(@CommandsBuilder _ content: () -> Content) -> WindowGroup {
        var copy = self
        copy.commands.append(content())
        return copy
    }
}
