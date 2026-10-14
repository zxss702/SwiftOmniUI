// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import Synchronization

/// A persistent order-statistic sequence and identity locator. Folder edits
/// share unchanged chunks; a row's position is its leaf offset plus ancestor
/// counts, so inserting rows never rewrites every following position.
@_spi(Host) public struct HostLazyIdentitySequence: RandomAccessCollection, Sendable {
    public typealias Index = Int
    private static let serial = Mutex<UInt64>(0)

    private final class Node: Sendable {
        let serial: UInt64
        let left: Node?
        let right: Node?
        let values: [String]
        let count: Int
        let height: Int

        init(_ values: [String]) {
            serial = HostLazyIdentitySequence.serial.withLock { $0 += 1; return $0 }
            left = nil; right = nil
            self.values = values
            count = values.count
            height = 1
        }

        init(_ left: Node, _ right: Node) {
            serial = HostLazyIdentitySequence.serial.withLock { $0 += 1; return $0 }
            self.left = left; self.right = right
            values = []
            count = left.count + right.count
            height = Swift.max(left.height, right.height) + 1
        }
    }

    private struct Location: Equatable, Sendable {
        let leaf: UInt64
        let offset: Int
    }
    private struct Parent: Equatable, Sendable {
        let node: UInt64
        let before: Int
    }

    private var root: Node?
    private var locations = PersistentIndex<String, Location>()
    private var parents = PersistentIndex<UInt64, Parent>()
    /// Deterministic edit-work evidence for regression tests, not elapsed time.
    private(set) var indexedIdentities = 0
    var parentEntries: Int { parents.count }
    var uniqueCount: Int { locations.count }
    var storageNodes: Int {
        func count(_ node: Node?) -> Int {
            guard let node else { return 0 }
            return 1 + count(node.left) + count(node.right)
        }
        return count(root)
    }

    public init(_ values: [String] = []) {
        root = nil
        root = build(values[...])
    }

    public var startIndex: Int { 0 }
    public var endIndex: Int { root?.count ?? 0 }
    public func index(after index: Int) -> Int { index + 1 }
    public func index(before index: Int) -> Int { index - 1 }
    public func index(_ index: Int, offsetBy distance: Int) -> Int { index + distance }
    public func distance(from start: Int, to end: Int) -> Int { end - start }

    public subscript(position: Int) -> String {
        precondition(position >= 0 && position < endIndex)
        var node = root!, offset = position
        while let left = node.left {
            if offset < left.count { node = left }
            else { offset -= left.count; node = node.right! }
        }
        return node.values[offset]
    }

    /// No absolute-position table: only the edited boundary paths acquire new
    /// parent links. Queries follow the links belonging to this snapshot.
    public func position(of identity: String) -> Int? {
        guard let location = locations[identity] else { return nil }
        var at = location.leaf, result = location.offset
        while let parent = parents[at] {
            result += parent.before
            at = parent.node
        }
        return at == root?.serial ? result : nil
    }

    public struct Iterator: IteratorProtocol {
        private var pending: [Node] = []
        private var leaf: Node?
        private var offset = 0
        private let backwards: Bool

        fileprivate init(_ sequence: HostLazyIdentitySequence, at index: Int = 0, backwards: Bool = false) {
            self.backwards = backwards
            guard index >= 0, index < sequence.count, var node = sequence.root else { return }
            var index = index
            while let left = node.left {
                if index < left.count {
                    if !backwards { pending.append(node.right!) }
                    node = left
                } else {
                    if backwards { pending.append(left) }
                    index -= left.count
                    node = node.right!
                }
            }
            leaf = node
            offset = index
        }

        public mutating func next() -> String? {
            guard let current = leaf else { return nil }
            let value = current.values[offset]
            offset += backwards ? -1 : 1
            if offset < 0 || offset == current.values.count {
                leaf = nil
                if var node = pending.popLast() {
                    while let left = node.left {
                        pending.append(backwards ? left : node.right!)
                        node = backwards ? node.right! : left
                    }
                    leaf = node
                    offset = backwards ? node.values.count - 1 : 0
                }
            }
            return value
        }
    }

    public func makeIterator() -> Iterator { Iterator(self) }
    func backwards() -> Iterator { Iterator(self, at: count - 1, backwards: true) }
    func matches(_ range: Range<Int>, _ values: ArraySlice<String>) -> Bool {
        guard range.count == values.count else { return false }
        var iterator = Iterator(self, at: range.lowerBound)
        return values.allSatisfy { iterator.next() == $0 }
    }

    mutating func replace(_ range: Range<Int>, with values: ArraySlice<String>) {
        indexedIdentities = 0
        let (head, rest) = split(root, at: range.lowerBound)
        let (removed, tail) = split(rest, at: range.count)
        discard(removed)
        let replacement = build(values)
        let beforeTail = join(head, replacement)
        root = join(beforeTail, tail)
        if let root { parents[root.serial] = nil }
    }

    mutating func move(_ range: Range<Int>, to destination: Int) {
        indexedIdentities = 0
        let (head, rest) = split(root, at: range.lowerBound)
        let (block, tail) = split(rest, at: range.count)
        let restRoot = join(head, tail)
        let (before, after) = split(restRoot, at: destination)
        let beforeAfter = join(before, block)
        root = join(beforeAfter, after)
        if let root { parents[root.serial] = nil }
    }

    private mutating func leaf(_ values: ArraySlice<String>, replacing: Bool = true) -> Node? {
        guard !values.isEmpty else { return nil }
        let node = Node(Array(values))
        for (offset, value) in values.enumerated() {
            if replacing || locations[value] == nil {
                locations[value] = Location(leaf: node.serial, offset: offset)
                indexedIdentities += 1
            }
        }
        return node
    }

    private mutating func branch(_ left: Node, _ right: Node) -> Node {
        let node = Node(left, right)
        parents[left.serial] = Parent(node: node.serial, before: 0)
        parents[right.serial] = Parent(node: node.serial, before: left.count)
        return node
    }

    private mutating func build(_ values: ArraySlice<String>) -> Node? {
        guard !values.isEmpty else { return nil }
        if values.count <= 64 { return leaf(values, replacing: false) }
        let mid = values.startIndex + values.count / 2
        let left = build(values[..<mid])!, right = build(values[mid...])!
        return branch(left, right)
    }

    private mutating func discard(_ node: Node?) {
        guard let node else { return }
        parents[node.serial] = nil
        if let left = node.left {
            discard(left); discard(node.right)
        } else {
            for value in node.values {
                locations[value] = nil
                indexedIdentities += 1
            }
        }
    }

    private mutating func split(_ node: Node?, at index: Int) -> (Node?, Node?) {
        guard let node else { return (nil, nil) }
        parents[node.serial] = nil
        if index <= 0 { return (nil, node) }
        if index >= node.count { return (node, nil) }
        guard let left = node.left, let right = node.right else {
            let head = leaf(node.values[..<index]), tail = leaf(node.values[index...])
            return (head, tail)
        }
        if index < left.count {
            let (head, tail) = split(left, at: index)
            let suffix = join(tail, right)
            if let head { parents[head.serial] = nil }
            if let suffix { parents[suffix.serial] = nil }
            return (head, suffix)
        }
        let (head, tail) = split(right, at: index - left.count)
        let prefix = join(left, head)
        if let prefix { parents[prefix.serial] = nil }
        if let tail { parents[tail.serial] = nil }
        return (prefix, tail)
    }

    private mutating func join(_ left: Node?, _ right: Node?) -> Node? {
        guard let left else {
            if let right { parents[right.serial] = nil }
            return right
        }
        guard let right else {
            parents[left.serial] = nil
            return left
        }
        if left.left == nil, right.left == nil, left.count + right.count <= 64 {
            parents[left.serial] = nil
            parents[right.serial] = nil
            return leaf((left.values + right.values)[...])
        }
        if left.height > right.height + 1 {
            parents[left.serial] = nil
            let tail = join(left.right, right)!
            return balanced(left.left!, tail)
        }
        if right.height > left.height + 1 {
            parents[right.serial] = nil
            let head = join(left, right.left)!
            return balanced(head, right.right!)
        }
        return branch(left, right)
    }

    private mutating func balanced(_ left: Node, _ right: Node) -> Node {
        if left.height > right.height + 1 {
            parents[left.serial] = nil
            let a = left.left!, b = left.right!
            if a.height >= b.height {
                let tail = branch(b, right)
                return branch(a, tail)
            }
            parents[b.serial] = nil
            let head = branch(a, b.left!), tail = branch(b.right!, right)
            return branch(head, tail)
        }
        if right.height > left.height + 1 {
            parents[right.serial] = nil
            let a = right.left!, b = right.right!
            if b.height >= a.height {
                let head = branch(left, a)
                return branch(head, b)
            }
            parents[a.serial] = nil
            let head = branch(left, a.left!), tail = branch(a.right!, b)
            return branch(head, tail)
        }
        return branch(left, right)
    }
}
