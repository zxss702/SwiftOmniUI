// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// Two or more views standing together, made by a `ViewBuilder` block of more
/// than one statement - never written by hand.
///
/// A tuple view keeps no element of its own: the differ splices its children
/// into the parent element's list, so `VStack { A(); B() }` is three siblings
/// whether the two views were written in the stack or in a body's own braces.
///
/// The statements are kept as they were written, not just as the nodes they
/// make: a `ForEach` among them stays a `LazyRows`, so a lazy container the
/// tuple lands in still names its rows before any is built.
public struct TupleView: View {
    /// The statements' views, in written order, where they were kept.
    let elements: [Element]?

    /// The node for one made from a node already - a tagged copy carries its
    /// elements where it has them, its node where it does not.
    private var stored: Node?

    /// A transparent fragment that keeps its statements until a container asks for them.
    public var node: Node {
        if let stored { return stored }
        let elements = elements ?? []
        var node = Node(type: .fragment)
        node.lazyContent = .elements(elements)
        node.producer = { elements.flatMap { $0.node.asChildren } }
        return node
    }

    /// A tuple view of the statements' own views.
    init(_ elements: [Element]) {
        self.elements = elements
    }

    /// A tuple view over an already-fragmented node.
    init(node: Node) {
        elements = nil
        stored = node
    }

    /// `element` under `segment`'s path, its laziness kept.
    static func keyed(_ segment: String, _ element: Element) -> Element {
        if let rows = element as? any LazyRows { return LazyKeyed(segment: segment, rows: rows) }
        let node = element.node
        if let elements = node.lazyElements {
            return TupleView(elements.map { keyed(segment, $0) })
        }
        return Keyed(segment: segment, raw: element, described: node)
    }

    /// One more segment on each child's path: the differ knows the child by
    /// where it was written, not by where the group lands.
    func tagged(_ segment: String) -> TupleView {
        if let elements {
            return TupleView(elements.map { Self.keyed(segment, $0) })
        }

        var tagged = node
        if let elements = tagged.lazyElements {
            return TupleView(elements.map { Self.keyed(segment, $0) })
        }
        tagged.materialize()
        tagged.children = tagged.children.map { child in
            var child = child
            child.key = child.key.map { "\(segment).\($0)" } ?? segment
            return child
        }
        return TupleView(node: tagged)
    }

    /// The kept statements - what a lazy container reads to find the rows
    /// among them; nil for a tuple made of a node.
    var lazyElements: [Element]? { elements }
}

/// Several views named as one, for factoring a fixed group out of a layout.
///
///     var body: some View {
///         Group {
///             Text(title)
///             Text(subtitle).foregroundStyle(.secondary)
///         }
///         .contentPadding(12)
///     }
///
/// A group keeps no element of its own - its children stand in its parent's
/// list as though written there, and a modifier on the group is written on
/// each of them.
public struct Group<Content: View>: View {
    /// The children, each a node.
    public var node: Node

    /// The group's views.
    public init(@ViewBuilder content: () -> Content) {
        let content = content().node
        node = content.type == .fragment ? content : Node(type: .fragment, children: [content])
    }
}

/// A view that shows nothing: the empty case of an `if` with no `else`.
public struct EmptyView: View {
    /// An empty fragment - no children, nothing to splice.
    public var node: Node { Node(type: .fragment) }

    /// Makes one.
    public init() {}
}

/// A view whose type is hidden behind `AnyView`, for a value that can hold a
/// view of more than one kind.
///
///     let icon: AnyView = isFolder ? AnyView(FolderIcon()) : AnyView(FileIcon())
///
/// The wrapped view keeps its own identity in the tree; `AnyView` itself adds
/// none.
public struct AnyView: View {
    /// The wrapped view's node, as written.
    public var node: Node

    /// Wraps `content` without changing what it is.
    public init(_ content: any View) {
        node = content.node
    }
}

/// A view marked safe to build again only when its value has moved - what
/// `.equatable()` makes.
///
/// SwiftOmniUI reads a view's stored properties as its inputs and rebuilds it
/// where they differ; an `Equatable` view's inputs already compare by value,
/// which is what the wrapper declares.
public struct EquatableView<Content: View & Equatable>: View, Equatable {
    /// The wrapped view.
    public var content: Content

    /// The wrapped view's node, as written.
    public var node: Node { content.node }

    /// Wraps `content`, declared `Equatable`.
    public init(content: Content) {
        self.content = content
    }
}

extension View where Self: Equatable {
    /// Marks this view safe to build again only when its value has moved:
    ///
    ///     Row(item: item)
    ///         .equatable()
    ///
    /// The view's `Equatable` conformance - often synthesized - is what the
    /// differ compares it by.
    public func equatable() -> EquatableView<Self> {
        EquatableView(content: self)
    }
}
