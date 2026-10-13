// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// A `VStack` built as a scroller shows it: a child's subtree is mounted
/// when the child stands in view or within reach of it, and let go when it
/// leaves - so a column as long as the data asks for keeps the cost of the
/// room on screen, not the length of the data.
///
///     ScrollView {
///         LazyVStack(spacing: 12) {
///             ForEach(messages) { message in
///                 MessageRow(message: message)
///             }
///         }
///     }
///
/// The scroll room is known before the children exist: the host stands the
/// unbuilt ones for by the measure of the ones it holds, and scrolls the
/// whole length at once. Each child names itself the way its writer named
/// it - a `ForEach` item's identity, an `.id()`, else the place it was
/// written at - and only a mounted child holds a view or a state.
public struct LazyVStack: View {
    /// What the stack shows, as the builder described it.
    private let content: () -> any View

    /// Where a child stands across the stack's width.
    private let alignment: HorizontalAlignment

    /// The room between neighbours; nil is the platform's own.
    private let spacing: Double?

    /// The children the host has asked for.
    @State private var realized: [String] = []

    /// The identity index survives parent updates; builders stay current.
    @State private var children = LazyChildren()

    /// A lazy column of whatever the closure describes.
    /// The closure is kept and run when the differ describes the stack.
    public init(@ViewBuilder content: @escaping () -> any View) {
        self.init(alignment: .center, spacing: nil, content: content)
    }

    /// A lazy column whose children stand at `alignment` across its width -
    /// a child that names its own `horizontalAlignment` keeps it.
    ///
    ///     ScrollView {
    ///         LazyVStack(alignment: .leading, spacing: 8) {
    ///             ForEach(messages) { MessageRow(message: $0) }
    ///         }
    ///     }
    public init(
        alignment: HorizontalAlignment,
        spacing: Double?,
        @ViewBuilder content: @escaping () -> any View
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content
    }

    /// The same, with the stack's own spacing - the SwiftUI spelling.
    public init(spacing: Double?, @ViewBuilder content: @escaping () -> any View) {
        self.init(alignment: .center, spacing: spacing, content: content)
    }

    /// The stack's element, built for the window the host last named.
    public var body: some View {
        var element = LazyVStackElement()
        if let spacing { element.node.write(StackBaseContract.spacing, spacing) }
        let held = $realized
        let axis = alignment.axis
        element.node.write(
            LazyVStackContract.items,
            children.take(content(), into: &element.node, realized: held) { child, _ in
                if child.props[.horizontalAlignment] == nil {
                    child.write(ViewContract.horizontalAlignment,
                                child.props[.maximumWidth]?.number == .infinity ? .fill : axis)
                }
            }
        )
        element.node.addHandler(LazyVStackContract.realizedChanged.token) {
            guard let identities = MemberValues.carried(
                EventBuffer.current, by: LazyVStackContract.realizedChanged.name, as: [String].self),
                identities != held.wrappedValue
            else { return }

            held.wrappedValue = identities
        }
        return element
    }
}

/// An `HStack` built as a scroller shows it - `LazyVStack` across.
///
///     ScrollView(.horizontal) {
///         LazyHStack(spacing: 12) { … }
///     }
public struct LazyHStack: View {
    /// What the stack shows, as the builder described it.
    private let content: () -> any View

    /// Where a child stands down the stack's height.
    private let alignment: VerticalAlignment

    /// The room between neighbours; nil is the platform's own.
    private let spacing: Double?

    /// The children the host has asked for.
    @State private var realized: [String] = []

    /// The identity index survives parent updates; builders stay current.
    @State private var children = LazyChildren()

    /// A lazy row of whatever the closure describes.
    public init(@ViewBuilder content: @escaping () -> any View) {
        self.init(alignment: .center, spacing: nil, content: content)
    }

    /// A lazy row whose children stand at `alignment` down its height -
    /// a child that names its own `verticalAlignment` keeps it.
    ///
    ///     ScrollView(.horizontal) {
    ///         LazyHStack(alignment: .top, spacing: 8) {
    ///             ForEach(cards) { CardView(card: $0) }
    ///         }
    ///     }
    public init(
        alignment: VerticalAlignment,
        spacing: Double?,
        @ViewBuilder content: @escaping () -> any View
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content
    }

    /// The same, with the stack's own spacing - the SwiftUI spelling.
    public init(spacing: Double?, @ViewBuilder content: @escaping () -> any View) {
        self.init(alignment: .center, spacing: spacing, content: content)
    }

    /// The stack's element, built for the window the host last named.
    public var body: some View {
        var element = LazyHStackElement()
        if let spacing { element.node.write(StackBaseContract.spacing, spacing) }
        let held = $realized
        let axis = alignment.axis
        element.node.write(
            LazyHStackContract.items,
            children.take(content(), into: &element.node, realized: held) { child, _ in
                if child.props[.verticalAlignment] == nil {
                    child.write(ViewContract.verticalAlignment,
                                child.props[.maximumHeight]?.number == .infinity ? .fill : axis)
                }
            }
        )
        element.node.addHandler(LazyHStackContract.realizedChanged.token) {
            guard let identities = MemberValues.carried(
                EventBuffer.current, by: LazyHStackContract.realizedChanged.name, as: [String].self),
                identities != held.wrappedValue
            else { return }

            held.wrappedValue = identities
        }
        return element
    }
}

/// The element a `LazyVStack` describes - the stack the host virtualizes.
struct LazyVStackElement: StackBase {
    var node = Node(contract: LazyVStackContract.self)
}

/// The element a `LazyHStack` describes - the row the host virtualizes.
struct LazyHStackElement: StackBase {
    var node = Node(contract: LazyHStackContract.self)
}

/// The children a lazy element describes: every one named, only the asked
/// ones built.
///
/// A child's identity is the one it was written with - a `ForEach` item's
/// or an `.id()`'s - or the place it stands at, told apart from an equal
/// one before it the way an `List` item's is. The names cross as the `items`
/// prop; the host answers with `realizedChanged`, and the producer gives the
/// differ only the children the host asks for.
///
/// A `ForEach` - alone, or a statement among others - is a `LazyRows`: it
/// names every row without building any, and its rows are made one at a
/// time, only for the identities the host asks for. Transparent groups and
/// node modifiers keep those sources. Other content is lazy in mounting alone.
@MainActor final class LazyChildren {
    /// One flat piece of a lazy container's content.
    private enum Segment {
        /// Rows named and built on asking - a `ForEach`, possibly under
        /// statement keys.
        case rows(any LazyRows)
        /// Children read already - static content.
        case nodes([Node])
    }

    private var previous: [Segment] = []
    private var identities: [String] = []
    private var owned: [String: (segment: Int, local: Int, place: Int)] = [:]
    private var positions: [String: Int] = [:]

    /// Names the children of `content` - `prepare` dressing each as its
    /// container asks - and sets `node`'s producer to the ones `realized`
    /// names, in the order they show. Answers every child's identity in the
    /// order it shows.
    func take(
        _ content: any View, into node: inout Node, realized: Binding<[String]>,
        prepare: @escaping (inout Node, Int) -> Void
    ) -> [String] {
        var segments: [Segment] = []
        var children: [Node] = []

        func append(_ element: Element) {
            if let rows = element as? any LazyRows {
                if !children.isEmpty { segments.append(.nodes(children)); children = [] }
                segments.append(.rows(rows))
            } else {
                let described = element.node
                if let elements = described.lazyElements {
                    for element in elements { append(element) }
                } else {
                    children.append(contentsOf: described.asChildren)
                }
            }
        }
        for element in (content as? TupleView)?.lazyElements ?? [content] { append(element) }
        if !children.isEmpty { segments.append(.nodes(children)) }

        // Comparing an unchanged range or value collection avoids stringifying
        // and indexing every identity again when only a lifetime counter moved.
        // The current segments still supply every row's newest captured values.
        let same = segments.count == previous.count && zip(segments, previous).allSatisfy { now, before in
            switch (now, before) {
            case (.rows(let now), .rows(let before)):
                return now.hasSameLazyIdentities(as: before)
            case (.nodes(let now), .nodes(let before)):
                return now.count == before.count && zip(now, before).allSatisfy {
                    $0.id == $1.id && $0.key == $1.key
                }
            default:
                return false
            }
        }
        previous = segments
        if !same {
            var taken: Set<String> = []
            identities = []
            owned = [:]
            var index = 0
            for (segmentIndex, segment) in segments.enumerated() {
                switch segment {
                case .rows(let rows):
                    for local in 0..<rows.lazyRowCount {
                        let base = rows.lazyRowIdentity(at: local) ?? "#\(index)"
                        var identity = base
                        var variant = 1
                        while taken.contains(identity) {
                            identity = "\(base)\u{0}\(variant)"
                            variant += 1
                        }
                        taken.insert(identity)
                        owned[identity] = (segmentIndex, local, index)
                        identities.append(identity)
                        index += 1
                    }

                case .nodes(let children):
                    for local in children.indices {
                        let base = children[local].id
                            ?? children[local].key.map { "#\($0)" }
                            ?? "#\(index)"
                        var identity = base
                        var variant = 1
                        while taken.contains(identity) {
                            identity = "\(base)\u{0}\(variant)"
                            variant += 1
                        }
                        taken.insert(identity)
                        owned[identity] = (segmentIndex, local, index)
                        identities.append(identity)
                        index += 1
                    }
                }
            }
            positions = Dictionary(uniqueKeysWithValues: identities.enumerated().map { ($1, $0) })
        }

        let positions = positions
        let owned = owned
        let rowStack: PropValue? = node.type == .lazyVStack || node.type == .lazyHStack
            ? .numbers([node.type == .lazyHStack ? 1 : 0, node.props[.spacing]?.number ?? 0]) : nil
        node.lazyWindow = realized.lender.map(ObjectIdentifier.init)
        // One prepared source may fill its window in several turns. Retained
        // rows already have descriptions; only incoming identities need their
        // builders again. A new take owns new captures and a new cache.
        var retained: [String: Node] = [:]
        node.producer = {
            let selected = realized.wrappedValue.filter { positions[$0] != nil }
                .sorted { positions[$0]! < positions[$1]! }
            let window = Set(selected)
            for identity in retained.keys.filter({ !window.contains($0) }) {
                retained.removeValue(forKey: identity)
            }
            return selected.compactMap { identity in
                if let child = retained[identity] { return child }
                guard let owner = owned[identity] else { return nil }
                var child: Node
                switch segments[owner.segment] {
                case .nodes(let nodes):
                    child = nodes[owner.local]
                case .rows(let rows):
                    child = rows.lazyRow(at: owner.local).node
                }
                if child.type == .fragment { child.materialize() }
                // A builder fragment has no box. Apply the container's defaults to its actual
                // children, where explicit alignment and flexible frame modifiers are visible.
                if child.type == .fragment, child.children.count == 1 {
                    child.children[0].lazyIdentity = identity
                } else if child.type != .fragment {
                    child.lazyIdentity = identity
                }
                if child.type == .fragment {
                    for index in child.children.indices { prepare(&child.children[index], owner.place) }
                } else {
                    prepare(&child, owner.place)
                }
                if child.type != .fragment { child.props[.lazyRowStack] = rowStack }
                // A fragment is retained by the differ even though only
                // its children mount. Its identity must survive window shifts too.
                if child.id == nil { child.id = identity }
                if child.type == .fragment {
                    var variant = 0
                    for index in child.children.indices where child.children[index].id == nil {
                        child.children[index].id = variant == 0 ? identity : "\(identity)\u{0}\(variant)"
                        variant += 1
                    }
                }
                retained[identity] = child
                return child
            }
        }
        return identities
    }

}
