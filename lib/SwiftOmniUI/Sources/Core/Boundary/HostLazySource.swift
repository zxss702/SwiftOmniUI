// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// One immutable identity index shared by the renderer and its native lazy layout.
/// View closures stay in the renderer; reading this source never builds a row.
@_spi(Host) public final class HostLazySource: Sendable {
    public let identities: [String]
    public let positions: [String: Int]
    /// The snapshot these edits follow. A host that skipped it rebuilds once.
    public let predecessor: ObjectIdentifier?
    public let edit: Edit
    /// Changes relative to a predecessor; the initial source has no insert animation.
    public let inserted: Set<String>
    public let removed: [String]

    public enum Edit: Sendable {
        /// Replace just this range, retaining geometry outside it.
        case replace(Range<Int>, with: Range<Int>)
        /// Move a block to an index in the sequence after removing that block.
        case move(Range<Int>, to: Int)
    }

    public init(_ identities: [String], following previous: HostLazySource? = nil) {
        self.identities = identities
        var positions: [String: Int] = [:]
        positions.reserveCapacity(identities.count)
        for (place, identity) in identities.enumerated() where positions[identity] == nil {
            positions[identity] = place
        }
        self.positions = positions
        predecessor = previous.map(ObjectIdentifier.init)
        let old = previous?.identities ?? []
        var head = 0
        while head < min(old.count, identities.count), old[head] == identities[head] { head += 1 }
        var oldEnd = old.count, newEnd = identities.count
        while oldEnd > head, newEnd > head, old[oldEnd - 1] == identities[newEnd - 1] {
            oldEnd -= 1
            newEnd -= 1
        }
        let before = head..<oldEnd, after = head..<newEnd
        inserted = previous == nil ? [] : Set(identities[after].filter { previous?.positions[$0] == nil })
        removed = old[before].filter { positions[$0] == nil }

        // A rotation of the changed interval is a block move. No measurement
        // in either block needs to be copied or looked up again.
        if before.count == after.count, !before.isEmpty,
           let pivot = previous?.positions[identities[head]], pivot > head, pivot < oldEnd,
           old[pivot..<oldEnd].elementsEqual(identities[head..<(head + oldEnd - pivot)]),
           old[head..<pivot].elementsEqual(identities[(head + oldEnd - pivot)..<newEnd]) {
            edit = .move(head..<pivot, to: head + oldEnd - pivot)
        } else {
            edit = .replace(before, with: after)
        }
    }
}
