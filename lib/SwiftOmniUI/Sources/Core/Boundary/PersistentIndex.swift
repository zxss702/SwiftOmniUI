// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// Copy-on-write hash trie used by immutable lazy snapshots. Editing a key
/// copies only its hash path; copying a snapshot never copies a whole Dictionary.
struct PersistentIndex<Key: Hashable & Sendable, Value: Equatable & Sendable>: Sendable {
    private struct Entry: Sendable {
        let key: Key
        let hash: UInt
        var value: Value
    }

    // Mutation is confined to uniquely referenced nodes, including every child
    // on the edited path. Separate Sendable values therefore share only nodes
    // that neither value can mutate without copying first.
    private final class Node: @unchecked Sendable {
        var entries: [Entry] = []
        var children: [Node?]?
        var count = 0

        func copy() -> Node {
            let result = Node()
            result.entries = entries
            result.children = children
            result.count = count
            return result
        }
    }

    private var root: Node?
    var count: Int { root?.count ?? 0 }

    init() {}

    /// Build an initial snapshot in one pass through each hash bucket. Later
    /// edits still copy only the affected trie path.
    init(_ values: [(Key, Value)]) {
        var unique: [Key: Value] = [:]
        unique.reserveCapacity(values.count)
        for (key, value) in values { unique[key] = value }
        root = Self.build(unique.map { Entry(key: $0.key, hash: UInt(bitPattern: $0.key.hashValue), value: $0.value) }, depth: 0)
    }

    private static func build(_ entries: [Entry], depth: Int) -> Node? {
        guard !entries.isEmpty else { return nil }
        let node = Node()
        node.count = entries.count
        guard entries.count > 8, (depth + 1) * 4 < UInt.bitWidth else {
            node.entries = entries
            return node
        }
        var buckets = [[Entry]](repeating: [], count: 16)
        for entry in entries { buckets[slot(entry.hash, depth)].append(entry) }
        node.children = buckets.map { build($0, depth: depth + 1) }
        return node
    }

    subscript(key: Key) -> Value? {
        get {
            let hash = UInt(bitPattern: key.hashValue)
            var node = root, depth = 0
            while let current = node {
                guard let children = current.children else {
                    return current.entries.first { $0.hash == hash && $0.key == key }?.value
                }
                node = children[Self.slot(hash, depth)]
                depth += 1
            }
            return nil
        }
        set {
            guard self[key] != newValue else { return }
            Self.write(&root, key: key, hash: UInt(bitPattern: key.hashValue), value: newValue, depth: 0)
        }
    }

    private static func slot(_ hash: UInt, _ depth: Int) -> Int {
        Int((hash >> (depth * 4)) & 15)
    }

    private static func write(_ node: inout Node?, key: Key, hash: UInt, value: Value?, depth: Int) {
        if node == nil {
            guard let value else { return }
            let made = Node()
            made.entries = [Entry(key: key, hash: hash, value: value)]
            made.count = 1
            node = made
            return
        }
        if !isKnownUniquelyReferenced(&node) { node = node!.copy() }
        if node!.children != nil {
            let slot = slot(hash, depth)
            let oldCount = node!.children![slot]?.count ?? 0
            write(&node!.children![slot], key: key, hash: hash, value: value, depth: depth + 1)
            node!.count += (node!.children![slot]?.count ?? 0) - oldCount
            if node!.count == 0 { node = nil }
            return
        }
        if let index = node!.entries.firstIndex(where: { $0.hash == hash && $0.key == key }) {
            if let value { node!.entries[index].value = value }
            else { node!.entries.remove(at: index); node!.count -= 1 }
        } else if let value {
            node!.entries.append(Entry(key: key, hash: hash, value: value))
            node!.count += 1
        }
        if node!.count == 0 { node = nil; return }
        // A terminal bucket also handles genuine hash collisions. No hash shift
        // ever reaches UInt.bitWidth, even when every key has the same hash.
        if node!.entries.count > 8, (depth + 1) * 4 < UInt.bitWidth {
            let entries = node!.entries
            node!.entries = []
            node!.children = [Node?](repeating: nil, count: 16)
            for entry in entries {
                let slot = slot(entry.hash, depth)
                write(&node!.children![slot], key: entry.key, hash: entry.hash,
                      value: entry.value, depth: depth + 1)
            }
        }
    }
}
