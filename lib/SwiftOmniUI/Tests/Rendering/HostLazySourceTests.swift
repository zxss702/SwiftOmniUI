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
