// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// Something that can stand in a `.toolbar` block - an item, a group of items,
/// or a spacer between them - the way a `View` is something that can stand in
/// a layout. A composition of toolbar entries is a `ToolbarContent` whose
/// `body` lists them:
///
///     struct EditorActions: ToolbarContent {
///         var body: some ToolbarContent {
///             ToolbarItem(placement: .primaryAction) {
///                 Button("Save") { save() }
///             }
///             ToolbarSpacer()
///             ToolbarItemGroup(placement: .navigation) {
///                 Button(action: undo) { Image(systemName: "arrow.uturn.left") }
///                 Button(action: redo) { Image(systemName: "arrow.uturn.right") }
///             }
///         }
///     }
///
/// and it stands in `.toolbar { … }` the way the items themselves do.
@preconcurrency @MainActor public protocol ToolbarContent {
    /// What this toolbar content is made of, read each time it is built. A
    /// content that is itself an entry - a `ToolbarItem`, a `ToolbarSpacer` -
    /// has no body and declares none; its `Body` is `Never`.
    associatedtype Body = Never

    /// The toolbar content this one is made of.
    @ToolbarContentBuilder var body: Body { get }
}

extension ToolbarContent where Body == Never {
    /// An entry draws itself; it is never read as a composition.
    public var body: Never { fatalError("\(Self.self) is toolbar content itself - it has no body") }
}

/// A toolbar entry - a leaf producing toolbar nodes directly: an item, a
/// spacer, a group's items, a block's entries. What `toolbarNodes` recognizes
/// a leaf by, where `body` is `Never`.
@MainActor protocol ToolbarEntry {
    /// The toolbar nodes this entry stands for.
    var toolbarNodes: [Node] { get }
}

extension ToolbarContent {
    /// The toolbar nodes this content stands for - a leaf's own item or spacer
    /// node, a composition's body's nodes, spliced in where the content is
    /// written so the differ keys every entry by where it stood.
    var toolbarNodes: [Node] {
        if let entry = self as? ToolbarEntry { return entry.toolbarNodes }
        guard Body.self != Never.self else { return [] }
        return (body as? any ToolbarContent)?.toolbarNodes ?? []
    }
}

/// The entries a `ToolbarContentBuilder` block of more than one statement
/// makes - never written by hand. Its nodes carry their written keys, and a
/// `.toolbar` block splices them into the page's toolbar slot.
public struct TupleToolbarContent: ToolbarContent, ToolbarEntry {
    /// The nodes, as written.
    var toolbarNodes: [Node] { nodes }

    /// The statements' nodes, each keyed by where it was written.
    let nodes: [Node]

    /// A tuple content over already-keyed nodes.
    init(nodes: [Node]) {
        self.nodes = nodes
    }

    /// One more segment on each child's path: the differ knows the child by
    /// where it was written, not by where the group lands.
    func tagged(_ segment: String) -> TupleToolbarContent {
        TupleToolbarContent(nodes: nodes.map { child in
            var child = child
            child.key = child.key.map { "\(segment).\($0)" } ?? segment
            return child
        })
    }
}

// The result builder behind `.toolbar { … }`. As `ViewBuilder` does for views,
// every method records where each entry was written - a path such as
// "1.else.0" that `Node.key` carries to the differ as the entry's key.

/// Collects the toolbar entries written as consecutive statements into one
/// `ToolbarContent` - a `TupleToolbarContent` for more than one.
///
/// `if`, `if/else`, `switch` and `for`/`in` work inside one:
///
///     .toolbar {
///         ToolbarItem(placement: .confirmationAction) {
///             Button("Done") { done() }
///         }
///         if canUndo {
///             ToolbarItem(placement: .navigation) {
///                 Button(action: undo) { Image(systemName: "arrow.uturn.left") }
///             }
///         }
///     }
@resultBuilder
public enum ToolbarContentBuilder {
    /// A single toolbar content written as a statement.
    public static func buildExpression<Content: ToolbarContent>(_ expression: Content) -> Content {
        expression
    }

    /// The statements' entries, in the order they are written, each keyed by
    /// its statement's number whatever the others produce.
    public static func buildBlock(_ components: (any ToolbarContent)...) -> TupleToolbarContent {
        let components = Carry(components)
        return onMain {
            TupleToolbarContent(nodes: components.value.enumerated().flatMap { at($0.offset, $0.element) })
        }
    }

    /// Nothing written: an empty group.
    public static func buildBlock() -> TupleToolbarContent {
        onMain { TupleToolbarContent(nodes: []) }
    }

    /// An `if` without an `else`; what it builds is keyed apart from the
    /// statement after it.
    public static func buildOptional(_ component: TupleToolbarContent?) -> TupleToolbarContent {
        let component = Carry(component)
        return onMain { component.value?.tagged("some") ?? TupleToolbarContent(nodes: []) }
    }

    /// The `if` branch of an if/else.
    public static func buildEither(first component: TupleToolbarContent) -> TupleToolbarContent {
        let component = Carry(component)
        return onMain { component.value.tagged("if") }
    }

    /// The `else` branch. Its entries are keyed apart from the `if` branch's,
    /// so switching branches replaces the entries rather than editing them.
    public static func buildEither(second component: TupleToolbarContent) -> TupleToolbarContent {
        let component = Carry(component)
        return onMain { component.value.tagged("else") }
    }

    /// A `for` statement's turns, each keyed by its turn number.
    public static func buildArray(_ components: [TupleToolbarContent]) -> TupleToolbarContent {
        let components = Carry(components)
        return onMain { TupleToolbarContent(nodes: components.value.enumerated().flatMap { turn in
            turn.element.nodes.map { node in
                var node = node
                node.key = node.key.map { "\(turn.offset).\($0)" } ?? String(turn.offset)
                return node
            }
        }) }
    }

    /// A `TupleToolbarContent` where the call already produced one.
    public static func buildFinalResult(_ component: TupleToolbarContent) -> TupleToolbarContent {
        component
    }

    /// A statement's own type through, so a leaf's `Body` names it: a body of
    /// one expression is that expression's type, not a `TupleToolbarContent`.
    public static func buildFinalResult<Content: ToolbarContent>(_ component: Content) -> Content {
        component
    }

    /// What an `if #available(…)` block builds, keyed like every other branch.
    public static func buildLimitedAvailability(_ component: TupleToolbarContent) -> TupleToolbarContent {
        let component = Carry(component)
        return onMain { component.value.tagged("available") }
    }

    /// The entries written under one statement, keyed by the statement's
    /// number - several, where one statement stands for more than one entry.
    private static func at(_ index: Int, _ content: any ToolbarContent) -> [Node] {
        // Builders run where the body that wrote them stood - the UI thread.
        let nodes = MainActor.assumeIsolated { Carry(content.toolbarNodes) }.value
        return nodes.enumerated().map { offset, child in
            var child = child
            let segment = nodes.count > 1 ? "\(index).\(offset)" : String(index)
            child.key = child.key.map { "\(segment).\($0)" } ?? segment
            return child
        }
    }
}

extension View {
    /// The items the page holding this view offers on its toolbar - on a
    /// navigation bar, in a window's toolbar, wherever the platform keeps a
    /// page's actions:
    ///
    ///     EditorView()
    ///         .toolbar {
    ///             ToolbarItem(placement: .confirmationAction) {
    ///                 Button("Done") { done() }
    ///             }
    ///         }
    ///
    /// Written anywhere in a page's content, the entries land on the page's
    /// own chrome - a nested arrangement, a `NavigationStack` or `TabView`
    /// inside, keeps its own. The same collection `page.toolbarItems` sets
    /// from inside the page.
    public func toolbar<Content: ToolbarContent>(
        @ToolbarContentBuilder _ content: () -> Content
    ) -> ModifiedContent {
        revised {
            // After the view's own children; the host finds it by type.
            // Design: docs/design/views/modifiers.md#slot-children
            $0.children.append(Node(contract: ToolbarItemsContract.self, children: content().toolbarNodes))
        }
    }
}

/// Views grouped on the toolbar, each standing as an item of its own, written
/// together where their neighbours are - the undo and redo of an editor's bar:
///
///     .toolbar {
///         ToolbarItemGroup(placement: .navigation) {
///             Button(action: undo) { Image(systemName: "arrow.uturn.left") }
///             Button(action: redo) { Image(systemName: "arrow.uturn.right") }
///         }
///     }
///
/// Each view is an item in `placement`, adjoining its fellows the way SwiftUI
/// draws a group.
public struct ToolbarItemGroup<Content: View>: ToolbarContent, ToolbarEntry {
    /// The nodes, as written.
    var toolbarNodes: [Node] { nodes }

    /// The group's item nodes - one over each written view, keyed by where it
    /// was written.
    let nodes: [Node]

    /// A group of the views `content` writes, each standing as an item in
    /// `placement`.
    public init(
        placement: ToolbarItemPlacement = .automatic,
        @ViewBuilder content: () -> Content
    ) {
        nodes = content().environment(\.isToolbarContent, true).labelStyle(.iconOnly).node.asChildren.map { view in
            var item = Node(contract: ToolbarItemContract.self, children: [view])
            item.write(ToolbarItemContract.placement, placement)
            item.key = view.key
            return item
        }
    }
}

/// Room between a toolbar's entries - all of it, pushing the entries either
/// side to the bar's ends, or the platform's gap:
///
///     .toolbar {
///         ToolbarItem(placement: .primaryAction) { Button("Back") { back() } }
///         ToolbarSpacer(.fixed)
///         ToolbarItem(placement: .primaryAction) { Button("Forward") { forward() } }
///         ToolbarSpacer()
///         ToolbarItem(placement: .primaryAction) { Button("Done") { done() } }
///     }
public struct ToolbarSpacer: ToolbarContent, ToolbarEntry {
    /// The spacer's node.
    public var node: Node

    /// The node, as written.
    var toolbarNodes: [Node] { [node] }

    /// A spacer taking `variant`'s room in `placement`.
    ///
    /// - Parameters:
    ///   - variant: `.flexible` takes all the room it can; `.fixed`, the
    ///     platform's ordinary gap between two entries.
    ///   - placement: where it stands among the bar's groups.
    public init(_ variant: ToolbarSpacerVariant = .flexible, placement: ToolbarItemPlacement = .automatic) {
        node = Node(contract: ToolbarSpacerContract.self)
        node.write(ToolbarSpacerContract.variant, variant)
        node.write(ToolbarSpacerContract.placement, placement)
    }

    /// A spacer taking `value`'s room instead.
    @_spi(Host) public func variant(_ value: ToolbarSpacerVariant) -> Self {
        var copy = self
        copy.node.write(ToolbarSpacerContract.variant, value)
        return copy
    }
}

extension ToolbarSpacer: PropertyContainer {}
