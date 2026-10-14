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
