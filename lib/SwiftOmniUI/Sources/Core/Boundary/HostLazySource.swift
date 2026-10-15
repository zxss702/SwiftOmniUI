// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// One immutable identity index shared by the renderer and its native lazy layout.
/// View closures stay in the renderer; reading this source never builds a row.
@_spi(Host) public final class HostLazySource: Sendable {
    public let identities: [String]
    /// The ordered identities and their persistent position links. Unchanged
    /// leaves and links are shared with the preceding source after a local edit.
    public let sequence: HostLazyIdentitySequence
    /// Compatibility for callers that explicitly need a complete table. Lazy
    /// layouts use `position(of:)` and never materialize this dictionary.
    public var positions: [String: Int] {
        var result: [String: Int] = [:]
        result.reserveCapacity(identities.count)
        for (place, identity) in identities.enumerated() where result[identity] == nil {
            result[identity] = place
        }
        return result
    }
    public func position(of identity: String) -> Int? { sequence.position(of: identity) }
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

    public convenience init(_ identities: [String], following previous: HostLazySource? = nil) {
        self.init(identities, following: previous, changedRanges: nil)
    }

    /// A producer that has already compared both unchanged ends can pass its
    /// ranges through. Repeating those comparisons here makes one folder edit
    /// walk the entire visible identity list twice on the UI thread.
    init(_ identities: [String], following previous: HostLazySource?,
         changedRanges: (before: Range<Int>, after: Range<Int>)?) {
        self.identities = identities
        predecessor = previous.map(ObjectIdentifier.init)
        let old = previous?.identities ?? []
        let before: Range<Int>, after: Range<Int>
        if let changedRanges {
            before = changedRanges.before
            after = changedRanges.after
        } else {
            var head = 0
            while head < min(old.count, identities.count), old[head] == identities[head] { head += 1 }
            var oldEnd = old.count, newEnd = identities.count
            while oldEnd > head, newEnd > head, old[oldEnd - 1] == identities[newEnd - 1] {
                oldEnd -= 1
                newEnd -= 1
            }
            before = head..<oldEnd
            after = head..<newEnd
        }
        // A rotation of the changed interval is a block move. No measurement
        // in either block needs to be copied or looked up again.
        let detectedEdit: Edit
        if before.count == after.count, !before.isEmpty,
           let pivot = previous?.position(of: identities[before.lowerBound]),
           pivot > before.lowerBound, pivot < before.upperBound,
           old[pivot..<before.upperBound].elementsEqual(
               identities[before.lowerBound..<(before.lowerBound + before.upperBound - pivot)]),
           old[before.lowerBound..<pivot].elementsEqual(
               identities[(before.lowerBound + before.upperBound - pivot)..<after.upperBound]) {
            detectedEdit = .move(before.lowerBound..<pivot, to: before.lowerBound + before.upperBound - pivot)
        } else {
            detectedEdit = .replace(before, with: after)
        }
        var ordered: HostLazyIdentitySequence
        if let previous {
            ordered = previous.sequence
            switch detectedEdit {
            case .replace(let before, let after):
                ordered.replace(before, with: identities[after])
            case .move(let range, let destination):
                ordered.move(range, to: destination)
            }
        } else {
            ordered = HostLazyIdentitySequence(identities)
        }
        // The renderer interns unique names. Direct SPI clients may supply
        // duplicates; rebuilding those preserves the first-occurrence contract.
        if ordered.uniqueCount != identities.count {
            ordered = HostLazyIdentitySequence(identities)
        }
        edit = detectedEdit
        sequence = ordered
        inserted = previous == nil ? [] : Set(identities[after].filter { previous?.position(of: $0) == nil })
        removed = old[before].filter { ordered.position(of: $0) == nil }
    }
}
