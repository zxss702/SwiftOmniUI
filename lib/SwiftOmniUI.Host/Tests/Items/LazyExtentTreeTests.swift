// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) @testable import SwiftOmniUICore
@_spi(Host) @testable import SwiftOmniUIHost
import XCTest

final class LazyExtentTreeTests: XCTestCase {
    func testUnmeasuredRowsUseOneRunAndEditsKeepStorageBounded() {
        var tree = LazyExtentTree(count: 100_000)
        XCTAssertEqual(tree.storageNodes, 1)
        tree.measure(50_000, extent: 28)
        XCTAssertEqual(tree.before(50_001).extent, 28)
        XCTAssertEqual(tree.before(50_001).count, 1)
        XCTAssertLessThanOrEqual(tree.storageNodes, 5)
        let original = tree
        tree.replace(10..<10, with: LazyExtentTree(count: 1_000_000))
        XCTAssertEqual(tree.count, 1_100_000)
        XCTAssertEqual(tree.extent(at: 1_050_000), 28)
        XCTAssertLessThan(tree.storageNodes, 12)
        tree.replace(10..<1_000_010, with: LazyExtentTree())
        XCTAssertEqual(tree.count, 100_000)
        XCTAssertEqual(tree.extent(at: 50_000), 28)
        XCTAssertEqual(original.extent(at: 50_000), 28, "value copies share immutable storage")
        tree.measure(50_000, extent: 60)
        XCTAssertEqual(original.extent(at: 50_000), 28)
    }

    func testMixedSplicesMovesAndMeasurementsMatchAFlatOracle() {
        var values = (0..<500).map { $0.isMultiple(of: 3) ? Optional(Double($0 % 41)) : nil }
        var tree = LazyExtentTree(values) { $0 }
        for step in 0..<200 {
            let place = (step * 37) % values.count
            if step.isMultiple(of: 3) {
                let replacement: [Double?] = [nil, Double(step), 0]
                values.replaceSubrange(place..<(place + 1), with: replacement)
                tree.replace(place..<(place + 1), with: LazyExtentTree(replacement) { $0 })
            } else if step.isMultiple(of: 2) {
                let end = min(values.count, place + 5)
                let block = Array(values[place..<end])
                values.removeSubrange(place..<end)
                let target = (step * 19) % (values.count + 1)
                values.insert(contentsOf: block, at: target)
                tree.move(place..<end, to: target)
            } else {
                values[place] = Double(step % 53)
                tree.measure(place, extent: Double(step % 53))
            }
            XCTAssertEqual(tree.count, values.count)
            for end in stride(from: 0, through: values.count, by: 13) {
                let known = values[..<end].compactMap { $0 }
                XCTAssertEqual(tree.before(end).extent, known.reduce(0, +), accuracy: 0.0001)
                XCTAssertEqual(tree.before(end).count, known.count)
            }
            XCTAssertLessThan(tree.height, 24, "repeated folder edits must not degenerate into a chain")
        }
    }

    func testSourceSplicesAndSkippedVersionsPreserveMeasuredIdentities() {
        let source = HostLazySource((0..<10_000).map(String.init))
        var extents = LazyExtents()
        extents.spacing = 0
        extents.adopt(source)
        for id in source.identities { extents.measure(id, extent: 28) }
        let before = extents.total(in: source.identities)
        let expanded = HostLazySource(Array(source.identities[..<5]) + ["a", "b"]
                                     + Array(source.identities[5...]), following: source)
        extents.adopt(expanded)
        XCTAssertEqual(extents.total(in: expanded.identities), before + 88)
        XCTAssertEqual(extents.extent(of: "9999"), 28)
        XCTAssertLessThan(extents.storageNodes, 12, "uniform known and unknown rows remain compressed")
        extents.measure("a", extent: 0)
        let moved = HostLazySource(["a", "b"] + source.identities, following: expanded)
        extents.adopt(moved)
        XCTAssertEqual(extents.offset(of: 2, in: moved.identities), 44)
        XCTAssertEqual(extents.total(in: moved.identities), before + 44)

        let omitted = HostLazySource(["new"] + moved.identities, following: moved)
        let latest = HostLazySource(Array(omitted.identities.reversed()), following: omitted)
        extents.adopt(latest)
        XCTAssertEqual(extents.extent(of: "a"), 0)
        XCTAssertEqual(extents.extent(of: "9999"), 28)
        XCTAssertEqual(extents.total(in: latest.identities), before + 88)
    }

    func testGridEditsKeepAlignedRunsAndInvalidateRegroupedSuffixes() {
        let source = HostLazySource((0..<100).map(String.init))
        var runs = LazyRunExtents()
        runs.adopt(source, perRun: 4)
        for run in 0..<25 { runs.measure(run, extent: Double(run + 20)) }
        let aligned = HostLazySource(Array(source.identities[..<8]) + ["a", "b", "c", "d"]
                                    + Array(source.identities[8...]), following: source)
        runs.adopt(aligned, perRun: 4)
        XCTAssertEqual(runs.extent(of: 0), 20)
        XCTAssertFalse(runs.hasMeasurement(for: 2))
        XCTAssertEqual(runs.extent(of: 3), 22)
        XCTAssertEqual(runs.extent(of: 25), 44)
        let regrouped = HostLazySource(Array(aligned.identities[..<9]) + ["x"]
                                      + Array(aligned.identities[9...]), following: aligned)
        runs.adopt(regrouped, perRun: 4)
        XCTAssertEqual(runs.extent(of: 1), 21)
        XCTAssertFalse(runs.hasMeasurement(for: 3))
        XCTAssertFalse(runs.hasMeasurement(for: 25))
    }

    func testSpeculativeGridCountsDoNotDropCommittedMeasurements() {
        var runs = LazyRunExtents()
        runs.measure(499, extent: 80)
        XCTAssertEqual(runs.total(count: 500), 500 * 44 + 36)
        XCTAssertEqual(runs.total(count: 20), 20 * 44)
        XCTAssertEqual(runs.total(count: 1_000), 1_000 * 44 + 36)
        XCTAssertEqual(runs.extent(of: 499), 80)
        XCTAssertEqual(runs.total(count: 500), 500 * 44 + 36)
    }
}
