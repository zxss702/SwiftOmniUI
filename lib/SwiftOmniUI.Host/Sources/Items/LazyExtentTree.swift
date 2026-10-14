// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// A persistent AVL sequence of uniform measurement runs. Unseen rows occupy
/// one leaf regardless of their count. Splicing a folder changes only the
/// paths to its boundaries; unaffected measurements and sums are shared.
struct LazyExtentTree: Sendable {
    private final class Node: Sendable {
        let left: Node?
        let right: Node?
        let extent: Double?
        let count: Int
        let known: Int
        let sum: Double
        let height: Int

        init(count: Int, extent: Double?) {
            left = nil; right = nil
            self.extent = extent
            self.count = count
            known = extent == nil ? 0 : count
            sum = (extent ?? 0) * Double(count)
            height = 1
        }

        init(_ left: Node, _ right: Node) {
            self.left = left; self.right = right
            extent = nil
            count = left.count + right.count
            known = left.known + right.known
            sum = left.sum + right.sum
            height = max(left.height, right.height) + 1
        }
    }

    private var root: Node?
    var count: Int { root?.count ?? 0 }
    var height: Int { root?.height ?? 0 }
    var storageNodes: Int {
        func nodes(_ node: Node?) -> Int {
            guard let node else { return 0 }
            return 1 + nodes(node.left) + nodes(node.right)
        }
        return nodes(root)
    }

    init(count: Int = 0) { root = count > 0 ? Node(count: count, extent: nil) : nil }

    init<C: Collection>(_ values: C, measurement: (C.Element) -> Double?) {
        var leaves: [Node] = []
        var count = 0, extent: Double?
        for value in values {
            let next = measurement(value)
            if count > 0, next != extent {
                leaves.append(Node(count: count, extent: extent))
                count = 0
            }
            extent = next
            count += 1
        }
        if count > 0 { leaves.append(Node(count: count, extent: extent)) }
        func build(_ range: Range<Int>) -> Node? {
            guard !range.isEmpty else { return nil }
            if range.count == 1 { return leaves[range.lowerBound] }
            let mid = range.lowerBound + range.count / 2
            return Node(build(range.lowerBound..<mid)!, build(mid..<range.upperBound)!)
        }
        root = build(leaves.indices)
    }

    func before(_ place: Int) -> (extent: Double, count: Int) {
        var node = root, remaining = min(count, max(0, place)), sum = 0.0, known = 0
        while let current = node, remaining > 0 {
            if remaining >= current.count {
                sum += current.sum; known += current.known
                break
            }
            guard let left = current.left else {
                if let extent = current.extent { sum += extent * Double(remaining); known += remaining }
                break
            }
            if remaining < left.count { node = left }
            else {
                sum += left.sum; known += left.known
                remaining -= left.count
                node = current.right
            }
        }
        return (sum, known)
    }

    func extent(at place: Int) -> Double? {
        guard place >= 0, place < count else { return nil }
        var node = root, place = place
        while let current = node {
            guard let left = current.left else { return current.extent }
            if place < left.count { node = left }
            else { place -= left.count; node = current.right }
        }
        return nil
    }

    mutating func measure(_ place: Int, extent: Double) {
        guard place >= 0, place < count else { return }
        var value = LazyExtentTree()
        value.root = Node(count: 1, extent: extent)
        replace(place..<(place + 1), with: value)
    }

    mutating func replace(_ range: Range<Int>, with replacement: LazyExtentTree) {
        let (head, rest) = Self.split(root, at: range.lowerBound)
        let (_, tail) = Self.split(rest, at: range.count)
        root = Self.join(Self.join(head, replacement.root), tail)
    }

    mutating func move(_ range: Range<Int>, to destination: Int) {
        let (head, rest) = Self.split(root, at: range.lowerBound)
        let (block, tail) = Self.split(rest, at: range.count)
        let (before, after) = Self.split(Self.join(head, tail), at: destination)
        root = Self.join(Self.join(before, block), after)
    }

    private static func split(_ node: Node?, at place: Int) -> (Node?, Node?) {
        guard let node else { return (nil, nil) }
        if place <= 0 { return (nil, node) }
        if place >= node.count { return (node, nil) }
        guard let left = node.left, let right = node.right else {
            return (Node(count: place, extent: node.extent), Node(count: node.count - place, extent: node.extent))
        }
        if place < left.count {
            let (head, tail) = split(left, at: place)
            return (head, join(tail, right))
        }
        let (head, tail) = split(right, at: place - left.count)
        return (join(left, head), tail)
    }

    private static func join(_ left: Node?, _ right: Node?) -> Node? {
        guard let left else { return right }
        guard let right else { return left }
        if left.left == nil, right.left == nil, left.extent == right.extent {
            return Node(count: left.count + right.count, extent: left.extent)
        }
        if left.height > right.height + 1 {
            return balanced(left.left!, join(left.right, right)!)
        }
        if right.height > left.height + 1 {
            return balanced(join(left, right.left)!, right.right!)
        }
        return Node(left, right)
    }

    private static func balanced(_ left: Node, _ right: Node) -> Node {
        if left.height > right.height + 1 {
            let a = left.left!, b = left.right!
            if a.height >= b.height { return Node(a, Node(b, right)) }
            return Node(Node(a, b.left!), Node(b.right!, right))
        }
        if right.height > left.height + 1 {
            let a = right.left!, b = right.right!
            if b.height >= a.height { return Node(Node(left, a), b) }
            return Node(Node(left, a.left!), Node(a.right!, b))
        }
        return Node(left, right)
    }
}
