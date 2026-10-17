// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import Synchronization

/// One immutable identity index shared by the renderer and its native lazy layout.
/// View closures stay in the renderer; reading this source never builds a row.
@_spi(Host) public final class HostLazySource: Sendable {
    /// A local edit shares the unchanged leaves of `sequence`. The complete
    /// array is only made if a caller explicitly needs the compatibility
    /// representation; native lazy layouts use the shared sequence directly.
    private let identitiesCache: Mutex<[String]?>
    private let insertedCache: Mutex<Set<String>?>
    public var identities: [String] {
        identitiesCache.withLock { stored in
            if let stored { return stored }
            let values = Array(sequence)
            stored = values
            return values
        }
    }
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
    private let insertionBase: HostLazyIdentitySequence?
    private let insertionRange: Range<Int>
    public var inserted: Set<String> {
        insertedCache.withLock { stored in
            if let stored { return stored }
            let result = insertionBase.map { base in
                Set(sequence[insertionRange].filter { base.position(of: $0) == nil })
            } ?? []
            stored = result
            return result
        }
    }
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
        identitiesCache = Mutex<[String]?>(identities)
        insertedCache = Mutex<Set<String>?>(nil)
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
        insertionBase = previous?.sequence
        insertionRange = after
        removed = old[before].filter { ordered.position(of: $0) == nil }
    }

    /// The producer has already compared the unchanged ends. Splice its new
    /// token interval into the persistent sequence; no full next array is
    /// required to describe this edit or locate any surviving identity.
    init(splicing previous: HostLazySource, before: Range<Int>, inserting names: [String]) {
        precondition(before.lowerBound >= 0 && before.upperBound <= previous.sequence.count)
        let after = before.lowerBound..<(before.lowerBound + names.count)
        predecessor = ObjectIdentifier(previous)
        let old = previous.sequence
        let detectedEdit: Edit
        if before.count == names.count, !before.isEmpty,
           let first = names.first,
           let pivot = previous.position(of: first),
           pivot > before.lowerBound, pivot < before.upperBound,
           old.matches(pivot..<before.upperBound,
                       names[..<(before.upperBound - pivot)]),
           old.matches(before.lowerBound..<pivot,
                       names[(before.upperBound - pivot)...]) {
            detectedEdit = .move(before.lowerBound..<pivot,
                                 to: before.lowerBound + before.upperBound - pivot)
        } else {
            detectedEdit = .replace(before, with: after)
        }
        var ordered = old
        switch detectedEdit {
        case .replace(let range, _):
            ordered.replace(range, with: names[...])
        case .move(let range, let destination):
            ordered.move(range, to: destination)
        }
        if ordered.uniqueCount != old.count - before.count + names.count {
            ordered = HostLazyIdentitySequence(Array(ordered))
        }
        sequence = ordered
        identitiesCache = Mutex<[String]?>(nil)
        insertedCache = Mutex<Set<String>?>(nil)
        edit = detectedEdit
        insertionBase = old
        insertionRange = after
        removed = old[before].filter { ordered.position(of: $0) == nil }
    }
}
