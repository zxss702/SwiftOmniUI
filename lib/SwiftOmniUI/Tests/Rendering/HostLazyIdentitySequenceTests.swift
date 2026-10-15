// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) @testable import SwiftOmniUICore
import XCTest

final class HostLazyIdentitySequenceTests: XCTestCase {
    func testInitialIndexFindsEveryRowAndKeepsFirstDuplicate() {
        let names = (0..<10_000).map { "file-\($0)" }
        let ordered = HostLazyIdentitySequence(names + ["file-37"])
        XCTAssertEqual(ordered.count, 10_001)
        XCTAssertEqual(ordered.position(of: "file-0"), 0)
        XCTAssertEqual(ordered.position(of: "file-37"), 37)
        XCTAssertEqual(ordered.position(of: "file-9999"), 9_999)
        XCTAssertEqual(ordered.parentEntries, ordered.storageNodes - 1)
    }

    func testFolderInsertionAndRemovalShareTheUnchangedIdentityIndex() {
        let original = HostLazyIdentitySequence((0..<10_000).map { "file-\($0)" })
        var expanded = original
        expanded.replace(6..<6, with: ["new-a", "new-b", "new-c"][...])

        XCTAssertEqual(expanded.count, 10_003)
        XCTAssertEqual(expanded.position(of: "file-0"), 0)
        XCTAssertEqual(expanded.position(of: "new-b"), 7)
        XCTAssertEqual(expanded.position(of: "file-9999"), 10_002)
        XCTAssertEqual(original.position(of: "file-9999"), 9_999)
        XCTAssertLessThan(expanded.indexedIdentities, 512,
                          "a local splice must not reindex every surviving file")
        XCTAssertEqual(expanded.parentEntries, expanded.storageNodes - 1)

        expanded.replace(6..<9, with: [String]()[...])
        XCTAssertNil(expanded.position(of: "new-a"))
        XCTAssertEqual(expanded.position(of: "file-9999"), 9_999)
        XCTAssertLessThan(expanded.indexedIdentities, 512)
        XCTAssertEqual(expanded.parentEntries, expanded.storageNodes - 1)
        XCTAssertEqual(Array(expanded), Array(original))
    }

    func testMiddleSplitAndBlockMoveKeepEveryPositionReachable() {
        var ordered = HostLazyIdentitySequence((0..<257).map { "row-\($0)" })
        var flat = Array(ordered)
        for step in 0..<90 {
            let start = 1 + (step * 37) % (flat.count - 5)
            if step.isMultiple(of: 3) {
                let name = "inserted-\(step)"
                flat.insert(name, at: start)
                ordered.replace(start..<start, with: [name][...])
            } else if step.isMultiple(of: 3) == false && step.isMultiple(of: 2) {
                let end = start + 2
                flat.removeSubrange(start..<end)
                ordered.replace(start..<end, with: [String]()[...])
            } else {
                let range = start..<(start + 3)
                let block = Array(flat[range])
                flat.removeSubrange(range)
                let destination = (step * 11) % (flat.count + 1)
                flat.insert(contentsOf: block, at: destination)
                ordered.move(range, to: destination)
            }
            XCTAssertEqual(Array(ordered), flat, "edit \(step)")
            XCTAssertEqual(ordered.parentEntries, ordered.storageNodes - 1, "edit \(step)")
            for (position, identity) in flat.enumerated() {
                XCTAssertEqual(ordered.position(of: identity), position, "edit \(step): \(identity)")
            }
        }
    }

    func testPersistentLocationMapCopiesOnlyTheEditedHashPathAndHandlesCollisions() {
        struct Key: Hashable, Sendable {
            let value: Int
            func hash(into hasher: inout Hasher) { hasher.combine(1) }
        }

        var original = PersistentIndex<Key, Int>()
        for number in 0..<100 { original[Key(value: number)] = number }
        var edited = original
        for number in 10..<30 { edited[Key(value: number)] = nil }
        edited[Key(value: 50)] = 500

        XCTAssertEqual(original.count, 100)
        XCTAssertEqual(edited.count, 80)
        XCTAssertEqual(original[Key(value: 20)], 20)
        XCTAssertNil(edited[Key(value: 20)])
        XCTAssertEqual(original[Key(value: 50)], 50)
        XCTAssertEqual(edited[Key(value: 50)], 500)
    }

    func testBulkHashIndexPreservesCollisionLookupsAcrossSnapshotEdits() {
        struct Key: Hashable, Sendable {
            let value: Int
            func hash(into hasher: inout Hasher) { hasher.combine(value % 17) }
        }
        let initial = PersistentIndex((0..<10_000).map { (Key(value: $0), $0) })
        XCTAssertEqual(initial.count, 10_000)
        for number in stride(from: 0, to: 10_000, by: 97) {
            XCTAssertEqual(initial[Key(value: number)], number)
        }
        var edited = initial
        edited[Key(value: 8_000)] = nil
        edited[Key(value: 20_000)] = 20_000
        XCTAssertEqual(initial[Key(value: 8_000)], 8_000)
        XCTAssertNil(edited[Key(value: 8_000)])
        XCTAssertEqual(edited[Key(value: 20_000)], 20_000)
        XCTAssertEqual(edited.count, 10_000)
    }
}
