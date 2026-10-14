// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// One view per item of a collection, each keyed by its item - never by the
/// position it happened to be built at.
///
///     VStack {
///         ForEach(names) { name in
///             Text(name)
///         }
///     }
///
/// A collection that gains, loses or reorders items moves the views that
/// stayed - text, caret, focus and `@State` riding along - rather than
/// rewriting what every position shows. A view's own `.id()` wins. Items must
/// be distinct within their parent; where they repeat, name the distinct part
/// with `id:`.
///
/// A plain `for` does not compile inside a view builder, so this is where
/// repetition is written.
///
/// The items and the row closure are kept, not run: read eagerly a `ForEach`
/// builds every row's node, but a lazy container asks it as a `LazyRows` -
/// the identities come first, and a row's own view is built only when the
/// row is asked into view.
public struct ForEach<Items: RandomAccessCollection, Id: Hashable, Content: View>: View {
    /// The collection the rows stand for.
    private let items: Items

    /// Which part of an item is its identity.
    private let identity: KeyPath<Items.Element, Id>

    /// The row each item builds, kept and run on asking.
    private let content: (Items.Element) -> Content

    /// A fragment retaining the rows until a container asks for them. Reading the
    /// node to apply a modifier does not execute the row closure.
    public var node: Node {
        var node = Node(type: .fragment)
        node.lazyContent = .rows(self)
        node.producer = { self.lazyChildren }
        return node
    }

    /// One view per item, the item its identity.
    ///
    ///     ForEach(0..<5) { turn in
    ///         Text("Turn \(turn)")
    ///     }
    ///
    /// A range works: its numbers are the items.
    @_disfavoredOverload
    public init(
        _ items: Items,
        @ViewBuilder content: @escaping (Items.Element) -> Content
    ) where Items.Element == Id {
        self.init(items, id: \.self, content: content)
    }

    /// One view per item, identified by the part of it `id` names.
    ///
    ///     ForEach(files, id: \.path) { file in
    ///         Text(file.name)
    ///     }
    ///
    /// For items that are not `Hashable` whole, or that repeat - an enumerated
    /// sequence's offsets being the usual case:
    /// `ForEach(Array(titles.enumerated()), id: \.offset)`.
    ///
    /// Lazy containers compare the Hashable identity itself, independently of
    /// its textual description.
    ///
    /// - Parameter id: which part of an item is its identity - distinct
    ///   across the items, stable while the item means the same row.
    public init(
        _ items: Items,
        id: KeyPath<Items.Element, Id>,
        @ViewBuilder content: @escaping (Items.Element) -> Content
    ) {
        self.items = items
        self.identity = id
        self.content = content
    }
}

extension ForEach where Items.Element: Identifiable, Items.Element.ID == Id {
    /// One view per item, each wearing its own `id` - the `Identifiable`
    /// spelling:
    ///
    ///     ForEach(files) { file in
    ///         Text(file.name)
    ///     }
    public init(
        _ items: Items,
        @ViewBuilder content: @escaping (Items.Element) -> Content
    ) {
        self.init(items, id: \.id, content: content)
    }
}

extension ForEach: LazyRows {
    var lazyChildren: [Node] {
        items.flatMap { item in
            Identified(identity: String(describing: item[keyPath: identity]), element: content(item)).node.asChildren
        }
    }

    var lazyRowCount: Int { items.count }

    func lazyRowIdentity(at index: Int) -> String? {
        String(describing: items[self.items.index(items.startIndex, offsetBy: index)][keyPath: identity])
    }

    func lazyRowID(at index: Int) -> AnyHashable? {
        AnyHashable(items[items.index(items.startIndex, offsetBy: index)][keyPath: identity])
    }

    func hasSameLazyIdentities(as other: any LazyRows) -> Bool {
        guard let other = other as? Self, identity == other.identity else { return false }
        // Comparing whole models is both unnecessary and potentially expensive.
        // Ranges have an O(1) proof; other collections scan only their IDs once.
        if let range = items as? Range<Int>, let old = other.items as? Range<Int> { return range == old }
        if let range = items as? ClosedRange<Int>, let old = other.items as? ClosedRange<Int> { return range == old }
        return false
    }

    func lazyRow(at index: Int) -> any Element {
        let item = items[items.index(items.startIndex, offsetBy: index)]
        return KeyedRow(identity: String(describing: item[keyPath: identity]), element: content(item))
    }
}

/// One turn's view, its item's identity on the key rather than the id - the
/// reading `lazyRow` gives. The identity rides the path so a statement's
/// segment can join it, while an author's `.id()` on the row still names it.
private struct KeyedRow: Element {
    /// The item's identity, for the row's path.
    let identity: String

    /// The view as the author wrote it, modifiers and all.
    let element: Element

    /// The element's own node, the identity on its path - a fragment's on
    /// its children's, since the fragment splices away.
    var node: Node {
        var node = element.node
        if node.type == .fragment { node.materialize() }

        guard node.type == .fragment else {
            if node.id == nil {
                node.key = node.key.map { "\(identity).\($0)" } ?? identity
            }
            return node
        }

        if node.children.count == 1, node.children[0].id == nil {
            node.children[0].key = node.children[0].key.map { "\(identity).\($0)" } ?? identity
            return node
        }

        node.children = node.children.map { child in
            var child = child
            if child.id == nil {
                child.key = child.key.map { "\(identity).\($0)" } ?? identity
            }
            return child
        }
        return node
    }
}

/// One turn's view, wearing its item's identity unless the author wrote an
/// `.id()` of their own.
/// Design: docs/design/views/builders.md#the-path-rides-a-wrapper
struct Identified: Element {
    /// The item's identity, rendered to the id namespace authors write in.
    let identity: String

    /// The view as the author wrote it, modifiers and all.
    let element: Element

    /// The element's own node, identified. A row that is a fragment carries
    /// its identity on its only child - or scopes each child's path by it -
    /// since the fragment itself splices away.
    var node: Node {
        var node = element.node
        if node.type == .fragment { node.materialize() }

        guard node.type == .fragment else {
            if node.id == nil {
                node.id = identity
            }

            return node
        }

        if node.children.count == 1 {
            if node.children[0].id == nil {
                node.children[0].id = identity
            }

            return node
        }

        node.children = node.children.map { child in
            var child = child
            if child.id == nil {
                child.key = child.key.map { "\(identity).\($0)" } ?? identity
            }
            return child
        }
        return node
    }
}
