// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// A view that can name its children without building them - what a lazy
/// container asks of its content before anything is made. `ForEach` is the
/// one: it keeps its items and the row closure, so a lazy stack learns every
/// identity up front and runs the closure only for the ones a scroller's
/// window asks for. Transparent fragments and their node modifiers retain
/// this source; other content is lazy in mounting, not in building.
protocol LazyRows: Element {
    /// The rows' nodes, all of them - the eager reading, for a container that
    /// does not ask lazily.
    var lazyChildren: [Node] { get }

    /// How many rows there are.
    var lazyRowCount: Int { get }

    /// The identity `index`'s row carries - `nil` for one with none.
    func lazyRowIdentity(at index: Int) -> String?

    /// Hashable identity, kept as a value until a new host token is needed.
    func lazyRowID(at index: Int) -> AnyHashable?

    /// Whether a fresh source can reuse the previous source's identity index.
    /// Row builders are always refreshed, even when this answers true.
    func hasSameLazyIdentities(as other: any LazyRows) -> Bool

    /// The row at `index`, built only when asked.
    func lazyRow(at index: Int) -> any Element
}

extension LazyRows {
    func lazyRowID(at index: Int) -> AnyHashable? { lazyRowIdentity(at: index).map(AnyHashable.init) }
}

/// UI-thread-owned dependencies of the currently requested row closures.
/// Dropping a row drops these reads as well as its rendered subtree.
final class LazyRowReadings {
    var rows: [String: Set<ObjectIdentifier>] = [:]
    var states: Set<ObjectIdentifier> {
        rows.values.reduce(into: Set<ObjectIdentifier>()) { $0.formUnion($1) }
    }
}

extension Node {
    /// Opens transparent composition without expanding a row source. The fragment's
    /// writes are retained on each piece, including content added as a slot.
    @MainActor var lazyElements: [Element]? {
        guard type == .fragment, let lazyContent else { return nil }
        var writes = self
        writes.lazyContent = nil
        writes.producer = nil
        writes.children = []

        func dressed(_ node: Node) -> Node {
            var node = node
            for (property, member) in writes.inheritedMembers { node.inherit(property, member: member) }
            node.absorbFragmentWrites(of: writes)
            return node
        }

        var elements: [Element]
        switch lazyContent {
        case .rows(let rows):
            elements = [ModifiedLazyRows(rows: rows, writes: writes)]
        case .elements(let source):
            elements = source.flatMap { element -> [Element] in
                let child = dressed(element.node)
                return child.lazyElements ?? child.asChildren.map { $0 as Element }
            }
        }
        elements += children.flatMap { child -> [Element] in
            let child = dressed(child)
            return child.lazyElements ?? child.asChildren.map { $0 as Element }
        }
        return elements
    }
}

/// Node modifiers describe a fragment once; each requested row takes those writes
/// when it is built. Modifier values change builders, never the identity index.
private struct ModifiedLazyRows: LazyRows {
    let rows: any LazyRows
    let writes: Node

    var node: Node {
        var node = Node(type: .fragment)
        node.lazyContent = .rows(self)
        node.producer = { self.lazyChildren }
        return node
    }

    var lazyChildren: [Node] { rows.lazyChildren.flatMap { dressed($0).asChildren } }
    var lazyRowCount: Int { rows.lazyRowCount }

    func lazyRowIdentity(at index: Int) -> String? { rows.lazyRowIdentity(at: index) }
    func lazyRowID(at index: Int) -> AnyHashable? { rows.lazyRowID(at: index) }

    func hasSameLazyIdentities(as other: any LazyRows) -> Bool {
        guard let other = other as? Self else { return false }
        return rows.hasSameLazyIdentities(as: other.rows)
    }

    func lazyRow(at index: Int) -> any Element { dressed(rows.lazyRow(at: index).node) }

    private func dressed(_ node: Node) -> Node {
        var node = node
        for (property, member) in writes.inheritedMembers { node.inherit(property, member: member) }
        node.absorbFragmentWrites(of: writes)
        return node
    }
}

/// A `LazyRows` under one more path segment - a statement's number, or a
/// branch's name, on the front of every row's key.
struct LazyKeyed: LazyRows {
    let segment: String
    let rows: any LazyRows

    var node: Node {
        var node = Node(type: .fragment)
        node.lazyContent = .rows(self)
        node.producer = { self.lazyChildren }
        return node
    }

    var lazyChildren: [Node] {
        rows.lazyChildren.map { child in
            var child = child
            child.key = child.key.map { "\(segment).\($0)" } ?? segment
            return child
        }
    }

    var lazyRowCount: Int { rows.lazyRowCount }

    func lazyRowIdentity(at index: Int) -> String? {
        rows.lazyRowIdentity(at: index).map { "\(segment).\($0)" }
    }

    func lazyRowID(at index: Int) -> AnyHashable? {
        rows.lazyRowID(at: index).map { AnyHashable(ScopedLazyID(segment: segment, value: $0)) }
    }

    func hasSameLazyIdentities(as other: any LazyRows) -> Bool {
        guard let other = other as? Self, segment == other.segment else { return false }
        return rows.hasSameLazyIdentities(as: other.rows)
    }

    /// The row under this segment - the key gains it; a `manual` id is the
    /// author's own name and keeps it.
    func lazyRow(at index: Int) -> any Element {
        SegmentKeyed(segment: segment, raw: rows.lazyRow(at: index))
    }
}

private struct ScopedLazyID: Hashable, CustomStringConvertible {
    let segment: String
    let value: AnyHashable
    var description: String { "\(segment).\(value)" }
}

/// A lazy row under one more path segment, as `LazyKeyed.lazyRow` wraps it.
private struct SegmentKeyed: Element {
    let segment: String
    let raw: Element

    var node: Node {
        var node = raw.node
        if node.type == .fragment {
            node.materialize()
            node.children = node.children.map { child in
                var child = child
                child.key = child.key.map { "\(segment).\($0)" } ?? segment
                return child
            }
        } else {
            node.key = node.key.map { "\(segment).\($0)" } ?? segment
        }
        return node
    }
}
