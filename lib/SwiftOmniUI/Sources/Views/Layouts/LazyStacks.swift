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
        children.take(content(), into: &element.node, realized: held) { child, _ in
            if child.props[.horizontalAlignment] == nil {
                child.write(ViewContract.horizontalAlignment,
                            child.props[.maximumWidth]?.number == .infinity ? .fill : axis)
            }
        }
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
        children.take(content(), into: &element.node, realized: held) { child, _ in
            if child.props[.verticalAlignment] == nil {
                child.write(ViewContract.verticalAlignment,
                            child.props[.maximumHeight]?.number == .infinity ? .fill : axis)
            }
        }
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
/// one before it the way a `List` item's is. The identity snapshot is shared
/// with the host; the host answers with `realizedChanged`, and the producer gives the
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
    private enum Key: Hashable {
        case row(AnyHashable, occurrence: Int)
        case node(String, occurrence: Int)
        case place(Int)
        case staticPlace(segment: Int, local: Int)
    }
    private var tokens: [Key: String] = [:]
    private var tokenKeys: [String: Key] = [:]
    private var source: HostLazySource?
    /// A leading ForEach's value identities. A changed Array has no edit
    /// notification, but its unchanged ends can be compared without hashing
    /// and re-interning every row on each folder expansion.
    private var leadingIDs: [AnyHashable]?
    private var leadingIDSet: Set<AnyHashable> = []

    /// Names the children of `content` - `prepare` dressing each as its
    /// container asks - and sets `node`'s producer to the ones `realized`
    /// names, in the order they show. The node keeps the shared identity index.
    func take(
        _ content: any View, into node: inout Node, realized: Binding<[String]>,
        prepare: @escaping (inout Node, Int) -> Void
    ) {
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

        // An unchanged range has a constant-time proof. Other sources compare
        // only IDs; the complete model values never participate in this check.
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
        let staticTailSame = segments.count == previous.count
            && zip(segments.dropFirst(), previous.dropFirst()).allSatisfy { now, before in
                guard case .nodes(let current) = now, case .nodes(let prior) = before else { return false }
                return current.count == prior.count && zip(current, prior).allSatisfy {
                    $0.id == $1.id && $0.key == $1.key
                }
            }
        previous = segments
        let leadingRows: (any LazyRows)? = {
            guard let first = segments.first else { return nil }
            if case .rows(let rows) = first { return rows }
            return nil
        }()
        let canIncrementLeadingRows = leadingRows != nil && segments.dropFirst().allSatisfy { segment in
            if case .nodes = segment { return true }
            return false
        }
        var updatedIncrementally = false
        if !same, let oldIDs = leadingIDs, let old = source,
           oldIDs.count <= old.identities.count,
           canIncrementLeadingRows, let rows = leadingRows {
            let newCount = rows.lazyRowCount
            var head = 0
            while head < min(oldIDs.count, newCount), rows.lazyRowID(at: head) == oldIDs[head] {
                head += 1
            }
            var oldEnd = oldIDs.count, newEnd = newCount
            while oldEnd > head, newEnd > head, rows.lazyRowID(at: newEnd - 1) == oldIDs[oldEnd - 1] {
                oldEnd -= 1
                newEnd -= 1
            }
            // A fresh Array with identical IDs changes row closures, not the
            // ordered source. Keep the existing index and avoid copying it.
            if head == oldIDs.count, head == newCount, staticTailSame {
                updatedIncrementally = true
            }
            if !updatedIncrementally {
                let removedIDs = Set(oldIDs[head..<oldEnd])
                var changedIDs: [AnyHashable] = []
                var changedSet: Set<AnyHashable> = []
                var unique = true
                for index in head..<newEnd {
                    guard let id = rows.lazyRowID(at: index),
                          changedSet.insert(id).inserted,
                          !leadingIDSet.contains(id) || removedIDs.contains(id) else {
                        unique = false
                        break
                    }
                    changedIDs.append(id)
                }
                if unique {
                    var names = Array(old.identities[..<head])
                    var variants: [String: Int] = [:]
                    func intern(_ key: Key, spelling: () -> String) -> String {
                        if let held = tokens[key] { return held }
                        let base = spelling()
                        var candidate = base, variant = variants[base, default: 1]
                        while tokenKeys[candidate] != nil {
                            candidate = "\(base)\u{0}\(variant)"
                            variant += 1
                        }
                        variants[base] = variant
                        tokens[key] = candidate
                        tokenKeys[candidate] = key
                        return candidate
                    }
                    for id in changedIDs {
                        names.append(intern(.row(id, occurrence: 0)) { String(describing: id) })
                    }
                    names.append(contentsOf: old.identities[oldEnd..<oldIDs.count])
                    var nodeOccurrences: [String: Int] = [:]
                    for (segmentIndex, segment) in segments.enumerated().dropFirst() {
                        guard case .nodes(let children) = segment else { continue }
                        for (local, child) in children.enumerated() {
                            if let base = child.id ?? child.key.map({ "#\($0)" }) {
                                let occurrence = nodeOccurrences[base, default: 0]
                                nodeOccurrences[base] = occurrence + 1
                                names.append(intern(.node(base, occurrence: occurrence)) { base })
                            } else {
                                let place = names.count
                                names.append(intern(.staticPlace(segment: segmentIndex, local: local)) {
                                    "#\(place)"
                                })
                            }
                        }
                    }
                    if names != old.identities {
                        let next = HostLazySource(names, following: old,
                            changedRanges: (before: head..<oldEnd, after: head..<newEnd))
                        for identity in next.removed {
                            if let key = tokenKeys.removeValue(forKey: identity) { tokens[key] = nil }
                        }
                        source = next
                    }
                    for id in removedIDs { leadingIDSet.remove(id) }
                    for id in changedIDs { leadingIDSet.insert(id) }
                    leadingIDs = Array(oldIDs[..<head]) + changedIDs + Array(oldIDs[oldEnd...])
                    updatedIncrementally = true
                }
            }
        }
        if (!same || source == nil) && !updatedIncrementally {
            var names: [String] = []
            var occurrences: [AnyHashable: Int] = [:]
            var nodeOccurrences: [String: Int] = [:]
            var variants: [String: Int] = [:]
            var newLeadingIDs: [AnyHashable]? = canIncrementLeadingRows ? [] : nil
            func append(_ key: Key, spelling: () -> String) {
                let identity: String
                if let held = tokens[key] {
                    identity = held
                } else {
                    let base = spelling()
                    var candidate = base, variant = variants[base, default: 1]
                    // Reserve surviving names before allocating a collision suffix.
                    // Unequal Hashable values may legitimately have equal descriptions.
                    while tokenKeys[candidate] != nil {
                        candidate = "\(base)\u{0}\(variant)"
                        variant += 1
                    }
                    variants[base] = variant
                    identity = candidate
                    tokens[key] = identity
                    tokenKeys[identity] = key
                }
                names.append(identity)
            }
            for (segmentIndex, segment) in segments.enumerated() {
                switch segment {
                case .rows(let rows):
                    for local in 0..<rows.lazyRowCount {
                        if let id = rows.lazyRowID(at: local) {
                            if segmentIndex == 0 { newLeadingIDs?.append(id) }
                            let occurrence = occurrences[id, default: 0]
                            occurrences[id] = occurrence + 1
                            append(.row(id, occurrence: occurrence)) { String(describing: id) }
                        } else {
                            if segmentIndex == 0 { newLeadingIDs = nil }
                            let place = names.count
                            append(.place(place)) { "#\(place)" }
                        }
                    }
                case .nodes(let children):
                    for (local, child) in children.enumerated() {
                        if let base = child.id ?? child.key.map({ "#\($0)" }) {
                            let occurrence = nodeOccurrences[base, default: 0]
                            nodeOccurrences[base] = occurrence + 1
                            append(.node(base, occurrence: occurrence)) { base }
                        } else {
                            let place = names.count
                            append(.staticPlace(segment: segmentIndex, local: local)) {
                                "#\(place)"
                            }
                        }
                    }
                }
            }
            if source?.identities != names {
                let next = HostLazySource(names, following: source)
                for identity in next.removed {
                    if let key = tokenKeys.removeValue(forKey: identity) { tokens[key] = nil }
                }
                source = next
            }
            if let newLeadingIDs, newLeadingIDs.count == leadingRows?.lazyRowCount {
                let uniqueIDs = Set(newLeadingIDs)
                if uniqueIDs.count == newLeadingIDs.count {
                    leadingIDs = newLeadingIDs
                    leadingIDSet = uniqueIDs
                } else {
                    leadingIDs = nil
                    leadingIDSet = []
                }
            } else {
                leadingIDs = nil
                leadingIDSet = []
            }
        }
        guard let source else { return }
        node.lazyRows = source
        // Segment boundaries are small, structural metadata. A row finds its
        // current builder by index; no second per-row ownership table is needed.
        var starts: [Int] = [], count = 0
        for segment in segments {
            starts.append(count)
            switch segment {
            case .rows(let rows): count += rows.lazyRowCount
            case .nodes(let nodes): count += nodes.count
            }
        }
        let boundaries = starts
        let positions = source.sequence
        let rowSpacing = node.props[.spacing]?.number
        let rowStack: PropValue? = node.type == .lazyVStack || node.type == .lazyHStack
            ? .numbers([node.type == .lazyHStack ? 1 : 0] + (rowSpacing.map { [$0] } ?? [])) : nil
        node.lazyWindow = realized.lender.map(ObjectIdentifier.init)
        let readings = LazyRowReadings()
        node.lazyRowReadings = readings
        let make: ([String: String]) -> [Node] = { retained in
            var nextReads: [String: Set<ObjectIdentifier>] = [:]
            let nodes: [Node] = realized.wrappedValue.filter { positions.position(of: $0) != nil }
                .sorted { positions.position(of: $0)! < positions.position(of: $1)! }
                .compactMap { identity in
                    guard let place = positions.position(of: identity) else { return nil }
                    var low = 0, high = boundaries.count
                    while low < high {
                        let middle = low + (high - low) / 2
                        if boundaries[middle] <= place { low = middle + 1 } else { high = middle }
                    }
                    let segment = low - 1, local = place - boundaries[segment]
                    if let id = retained[identity] {
                        // reconcileChildren keeps the existing rendered subtree. Do
                        // not construct a view just to discard its description there.
                        var kept = Node(type: .fragment, id: id)
                        kept.lazyIdentity = identity
                        nextReads[identity] = readings.rows[identity] ?? []
                        return kept
                    }
                    let (made, rowReads) = ReadScope.observed { () -> Node in
                        var child: Node
                        switch segments[segment] {
                        case .nodes(let nodes):
                            child = nodes[local]
                        case .rows(let rows):
                            child = rows.lazyRow(at: local).node
                        }
                        if child.type == .fragment { child.materialize() }
                        // A builder fragment has no box. Apply the container's defaults to its actual
                        // children, where explicit alignment and flexible frame modifiers are visible.
                        if child.type == .fragment, child.children.count == 1 {
                            child.children[0].lazyIdentity = identity
                        }
                        child.lazyIdentity = identity
                        if child.type == .fragment {
                            for index in child.children.indices { prepare(&child.children[index], place) }
                        } else {
                            prepare(&child, place)
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
                        return child
                    }
                    nextReads[identity] = rowReads
                    return made
                }
            readings.rows = nextReads
            return nodes
        }
        node.lazyProducer = make
        node.producer = { make([:]) }
    }

}
