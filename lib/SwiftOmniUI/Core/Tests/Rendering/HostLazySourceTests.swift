// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) @testable import SwiftOmniUICore
import XCTest

final class HostLazySourceTests: XCTestCase {
    func testFolderEditsDescribeOnlyTheChangedInterval() {
        let original = HostLazySource((0..<10_000).map(String.init))
        let expanded = HostLazySource(Array(original.identities[..<6]) + ["a", "b", "c"]
                                     + Array(original.identities[6...]), following: original)
        guard case .replace(let before, let after) = expanded.edit else { return XCTFail("expected insertion") }
        XCTAssertEqual(before, 6..<6)
        XCTAssertEqual(after, 6..<9)
        XCTAssertEqual(expanded.inserted, ["a", "b", "c"])
        XCTAssertTrue(expanded.removed.isEmpty)
        XCTAssertEqual(expanded.predecessor, ObjectIdentifier(original))
        XCTAssertEqual(expanded.positions["9999"], 10_002)
        XCTAssertEqual(expanded.position(of: "9999"), 10_002)
        XCTAssertLessThan(expanded.sequence.indexedIdentities, 512,
                          "expansion must reuse the IDs and positions after the inserted folder")

        let collapsed = HostLazySource(original.identities, following: expanded)
        guard case .replace(let removed, let replacement) = collapsed.edit else { return XCTFail("expected deletion") }
        XCTAssertEqual(removed, 6..<9)
        XCTAssertEqual(replacement, 6..<6)
        XCTAssertEqual(collapsed.removed, ["a", "b", "c"])
        XCTAssertTrue(collapsed.inserted.isEmpty)
        XCTAssertEqual(collapsed.position(of: "9999"), 9_999)
        XCTAssertLessThan(collapsed.sequence.indexedIdentities, 512)
    }

    func testBlockReorderingIsAMoveAndDoesNotInsertOrDeleteIdentity() {
        let original = HostLazySource(["a", "b", "c", "d", "e", "f"])
        let moved = HostLazySource(["a", "d", "e", "b", "c", "f"], following: original)
        guard case .move(let range, let destination) = moved.edit else { return XCTFail("expected block move") }
        XCTAssertEqual(range, 1..<3)
        XCTAssertEqual(destination, 3)
        XCTAssertTrue(moved.inserted.isEmpty)
        XCTAssertTrue(moved.removed.isEmpty)
        XCTAssertEqual(moved.position(of: "b"), 3)
        XCTAssertEqual(moved.position(of: "e"), 2)
    }

    func testProducerSpliceReusesItsComparedBoundsIncludingAStaticTail() {
        let original = HostLazySource((0..<10_000).map(String.init) + ["tail"])
        let names = Array(original.identities[..<4]) + ["new-a", "new-b"]
            + Array(original.identities[4...])
        let expanded = HostLazySource(names, following: original,
            changedRanges: (before: 4..<4, after: 4..<6))
        guard case .replace(let before, let after) = expanded.edit else {
            return XCTFail("expected insertion")
        }
        XCTAssertEqual(before, 4..<4)
        XCTAssertEqual(after, 4..<6)
        XCTAssertEqual(expanded.position(of: "tail"), 10_002)
        XCTAssertEqual(expanded.identities.last, original.identities.last)
        XCTAssertEqual(expanded.inserted, ["new-a", "new-b"])
        XCTAssertLessThan(expanded.sequence.indexedIdentities, 512)

        let restored = HostLazySource(original.identities, following: expanded,
            changedRanges: (before: 4..<6, after: 4..<4))
        XCTAssertEqual(restored.identities, original.identities)
        XCTAssertEqual(restored.removed, ["new-a", "new-b"])
        XCTAssertEqual(restored.position(of: "tail"), 10_000)
    }

    func testPersistentSpliceSharesTheUnchangedIdentitySequence() {
        var original: HostLazySource? = HostLazySource((0..<10_000).map(String.init) + ["tail"])
        weak var released = original
        let expanded = HostLazySource(splicing: original!, before: 4..<4,
                                      inserting: ["new-a", "new-b"])
        original = nil
        XCTAssertNil(released, "a source edit must not retain an entire predecessor")
        guard case .replace(let before, let after) = expanded.edit else {
            return XCTFail("expected insertion")
        }
        XCTAssertEqual(before, 4..<4)
        XCTAssertEqual(after, 4..<6)
        XCTAssertEqual(expanded.sequence.count, 10_003)
        XCTAssertEqual(expanded.sequence[4], "new-a")
        XCTAssertEqual(expanded.sequence[10_002], "tail")
        XCTAssertEqual(expanded.position(of: "tail"), 10_002)
        XCTAssertLessThan(expanded.sequence.indexedIdentities, 512)

        let collapsed = HostLazySource(splicing: expanded, before: 4..<6, inserting: [])
        XCTAssertEqual(collapsed.sequence.count, 10_001)
        XCTAssertEqual(collapsed.position(of: "tail"), 10_000)
        XCTAssertEqual(collapsed.removed, ["new-a", "new-b"])
        XCTAssertLessThan(collapsed.sequence.indexedIdentities, 512)
    }

    func testPersistentSpliceDetectsBlockMoveWithoutReplacingSurvivingRows() {
        let original = HostLazySource(["a", "b", "c", "d", "e", "f"])
        let moved = HostLazySource(splicing: original, before: 1..<5,
                                   inserting: ["d", "e", "b", "c"])
        guard case .move(let range, let destination) = moved.edit else {
            return XCTFail("expected block move")
        }
        XCTAssertEqual(range, 1..<3)
        XCTAssertEqual(destination, 3)
        XCTAssertEqual(moved.identities, ["a", "d", "e", "b", "c", "f"])
        XCTAssertTrue(moved.inserted.isEmpty)
        XCTAssertTrue(moved.removed.isEmpty)
    }

    func testDirectPersistentSpliceRetainsFirstOccurrenceForDuplicateNames() {
        let original = HostLazySource(["a", "b"])
        let repeated = HostLazySource(splicing: original, before: 1..<1, inserting: ["a"])
        XCTAssertEqual(repeated.identities, ["a", "a", "b"])
        XCTAssertEqual(repeated.position(of: "a"), 0)
        XCTAssertEqual(repeated.position(of: "b"), 2)
    }

    func testSnapshotDoesNotRetainItsPredecessors() {
        var original: HostLazySource? = HostLazySource(["a", "b"])
        weak var released = original
        let next = HostLazySource(["a", "x", "b"], following: original)
        original = nil
        XCTAssertNil(released, "scrolling and edits must not accumulate every prior source")
        XCTAssertEqual(next.positions["b"], 2)
    }

    func testMergingPatchesKeepsTheLatestSnapshot() {
        let first = HostLazySource(["a"])
        let second = HostLazySource(["a", "b"], following: first)
        var a = HostPatch(id: .manual("lazy"), type: .lazyVStack)
        a.lazyRows = first
        var b = HostPatch(id: a.id, type: a.type)
        b.lazyRows = second
        XCTAssertFalse(a.isEmpty)
        XCTAssertTrue(a.merging(b).lazyRows === second)
        XCTAssertTrue(a.merging(HostPatch(id: a.id, type: a.type)).lazyRows === first)
    }
}
