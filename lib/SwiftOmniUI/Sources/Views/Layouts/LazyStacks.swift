// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// The host keeps the declared identity payload as the first lane; its private
/// second lane is echoed by the lazy node so that one list can acknowledge its
/// own request without waiting for unrelated renders elsewhere in the scene.
enum LazyWindowRequest {
    static func decode(_ payload: [PropValue], by name: String) -> (identities: [String], generation: Int?)? {
        guard (1...2).contains(payload.count),
              let identities = MemberValues.carried(Array(payload.prefix(1)), by: name, as: [String].self)
        else { return nil }
        guard payload.count == 2 else { return (identities, nil) }
        guard case .number(let value) = payload[1], value.isFinite,
              value >= 0, value <= 9_007_199_254_740_991, value.rounded() == value
        else { return nil }
        return (identities, Int(value))
    }
}

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
    @State private var realizedGeneration = 0

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
        let heldGeneration = $realizedGeneration
        element.node.lazyRequestGeneration = realizedGeneration
        element.node.lazyRequestWindow = heldGeneration.lender.map(ObjectIdentifier.init)
        element.node.lazyRequestGenerationValue = { heldGeneration.wrappedValue }
        let axis = alignment.axis
        children.take(content(), into: &element.node, realized: held) { child, _ in
            if child.props[.horizontalAlignment] == nil {
                child.write(ViewContract.horizontalAlignment,
                            child.props[.maximumWidth]?.number == .infinity ? .fill : axis)
            }
        }
        element.node.addHandler(LazyVStackContract.realizedChanged.token) {
            guard let request = LazyWindowRequest.decode(
                EventBuffer.current, by: LazyVStackContract.realizedChanged.name) else { return }
            if request.identities != held.wrappedValue { held.wrappedValue = request.identities }
            if let generation = request.generation { heldGeneration.wrappedValue = generation }
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
    @State private var realizedGeneration = 0

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
        let heldGeneration = $realizedGeneration
        element.node.lazyRequestGeneration = realizedGeneration
        element.node.lazyRequestWindow = heldGeneration.lender.map(ObjectIdentifier.init)
        element.node.lazyRequestGenerationValue = { heldGeneration.wrappedValue }
        let axis = alignment.axis
        children.take(content(), into: &element.node, realized: held) { child, _ in
            if child.props[.verticalAlignment] == nil {
                child.write(ViewContract.verticalAlignment,
                            child.props[.maximumHeight]?.number == .infinity ? .fill : axis)
            }
        }
        element.node.addHandler(LazyHStackContract.realizedChanged.token) {
            guard let request = LazyWindowRequest.decode(
                EventBuffer.current, by: LazyHStackContract.realizedChanged.name) else { return }
            if request.identities != held.wrappedValue { held.wrappedValue = request.identities }
            if let generation = request.generation { heldGeneration.wrappedValue = generation }
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
    /// Non-nil only while the leading row source has unique IDs. Its tokens
    /// already live in `source.sequence`; `tokenKeys` recovers their value IDs
    /// without maintaining and shifting a second full-length array.
    private var leadingRowCount: Int?

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
        let previousLeadingRows: (any LazyRows)? = {
            guard let first = previous.first else { return nil }
            if case .rows(let rows) = first { return rows }
            return nil
        }()
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
        if !same, staticTailSame, let oldCount = leadingRowCount, let old = source,
           oldCount <= old.sequence.count,
           canIncrementLeadingRows, let rows = leadingRows {
            func oldID(for token: String) -> AnyHashable? {
                guard let key = tokenKeys[token],
                      case .row(let id, occurrence: 0) = key else { return nil }
                return id
            }
            func oldID(at index: Int) -> AnyHashable? { oldID(for: old.sequence[index]) }
            let newCount = rows.lazyRowCount
            let head: Int, oldEnd: Int, newEnd: Int
            if let previousLeadingRows,
               let compared = rows.changedLazyIdentityRanges(comparedTo: previousLeadingRows),
               compared.before.lowerBound == compared.after.lowerBound,
               compared.before.upperBound <= oldCount,
               compared.after.upperBound <= newCount {
                head = compared.before.lowerBound
                oldEnd = compared.before.upperBound
                newEnd = compared.after.upperBound
            } else {
                var common = 0
                var forwards = old.sequence.makeIterator()
                while common < Swift.min(oldCount, newCount),
                      let token = forwards.next(), let held = oldID(for: token),
                      rows.lazyRowID(at: common) == held {
                    common += 1
                }
                var oldTail = oldCount, newTail = newCount
                var backwards = old.sequence.backwards()
                // Skip static children after the leading row source.
                for _ in oldCount..<old.sequence.count { _ = backwards.next() }
                while oldTail > common, newTail > common,
                      let token = backwards.next(), let held = oldID(for: token),
                      rows.lazyRowID(at: newTail - 1) == held {
                    oldTail -= 1
                    newTail -= 1
                }
                head = common
                oldEnd = oldTail
                newEnd = newTail
            }
            // A fresh Array with identical IDs changes row closures, not the
            // ordered source. Keep the existing index and avoid copying it.
            if head == oldCount, head == newCount {
                updatedIncrementally = true
            }
            if !updatedIncrementally {
                let removedRange = (head..<oldEnd).compactMap { oldID(at: $0) }
                let removedIDs = Set(removedRange)
                var changedIDs: [AnyHashable] = []
                var changedSet: Set<AnyHashable> = []
                var unique = removedRange.count == oldEnd - head
                for index in head..<newEnd {
                    guard let id = rows.lazyRowID(at: index),
                          changedSet.insert(id).inserted,
                          tokens[.row(id, occurrence: 0)] == nil || removedIDs.contains(id) else {
                        unique = false
                        break
                    }
                    changedIDs.append(id)
                }
                if unique {
                    var names: [String] = []
                    names.reserveCapacity(changedIDs.count)
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
                    let next = HostLazySource(splicing: old, before: head..<oldEnd, inserting: names)
                    for identity in next.removed {
                        if let key = tokenKeys.removeValue(forKey: identity) { tokens[key] = nil }
                    }
                    source = next
                    leadingRowCount = newCount
                    updatedIncrementally = true
                }
            }
        }
        if (!same || source == nil) && !updatedIncrementally {
            var names: [String] = []
            var occurrences: [AnyHashable: Int] = [:]
            var nodeOccurrences: [String: Int] = [:]
            var variants: [String: Int] = [:]
            var newLeadingCount: Int? = canIncrementLeadingRows ? 0 : nil
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
                            let occurrence = occurrences[id, default: 0]
                            if segmentIndex == 0, let count = newLeadingCount {
                                newLeadingCount = occurrence == 0 ? count + 1 : nil
                            }
                            occurrences[id] = occurrence + 1
                            append(.row(id, occurrence: occurrence)) { String(describing: id) }
                        } else {
                            if segmentIndex == 0 { newLeadingCount = nil }
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
            if source?.sequence.count != names.count
                || source?.sequence.matches(0..<names.count, names[...]) != true {
                let next = HostLazySource(names, following: source)
                for identity in next.removed {
                    if let key = tokenKeys.removeValue(forKey: identity) { tokens[key] = nil }
                }
                source = next
            }
            leadingRowCount = newLeadingCount == leadingRows?.lazyRowCount ? newLeadingCount : nil
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
