// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) @testable import SwiftOmniUICore
@_spi(Host) @testable import SwiftOmniUIHost
import XCTest

final class LazyGeometryTests: XCTestCase {
    @MainActor
    func testDrawingContentUpdatesKeepTheWindowUsedToRecognizeANewScrollAnchor() throws {
        let runtime = HostRuntime.still()
        var patch = HostPatch(id: .manual("lazy"), type: .lazyVStack)
        patch.lazyRows = HostLazySource((0..<10_000).map(String.init))
        runtime.tree.apply(patch, complete: true)
        let element = try XCTUnwrap(runtime.tree.root)
        let cells = LazyCells(element, in: runtime)
        cells.takeItems()
        cells.show(10_000..<10_240, realize: 9_760..<10_480, prefetch: true)
        let previous = try XCTUnwrap(cells.window)
        var drawing = HostPatch(id: element.id, type: element.type)
        drawing.lazyContentChanged = true
        runtime.tree.apply(drawing, complete: false)
        cells.takeItems()
        XCTAssertEqual(cells.window?.span, previous.span)
        XCTAssertFalse(cells.needsWindowUpdate,
                       "a drawing change keeps the realized window and its optional prefetch work")
        cells.show(11_000..<11_240, realize: 10_760..<11_480, prefetch: true)
        XCTAssertFalse(cells.needsWindowUpdate)
        XCTAssertNil(cells.correctedOrigin(), "a drawing update must not restore the earlier scroll position")
    }

    @MainActor
    func testRendererAndMountedLayoutShareTheSourceAcrossFolderEdits() throws {
        let runtime = HostRuntime.still()
        let source = HostLazySource((0..<100_000).map(String.init))
        var patch = HostPatch(id: .manual("lazy"), type: .lazyVStack)
        patch.lazyRows = source
        runtime.tree.apply(patch, complete: true)
        let element = try XCTUnwrap(runtime.tree.root)
        let cells = LazyCells(element, in: runtime)
        cells.takeItems()
        XCTAssertTrue(element.lazyRows === source)
        XCTAssertNil(element.value(.items))
        cells.extents.measure("500", extent: 28)
        cells.show(0..<240)
        let next = HostLazySource(["new"] + source.identities, following: source)
        var update = HostPatch(id: element.id, type: element.type)
        update.lazyRows = next
        runtime.tree.apply(update, complete: false)
        cells.takeItems()
        XCTAssertTrue(element.lazyRows === next)
        XCTAssertEqual(cells.position(of: "500"), 501)
        XCTAssertEqual(cells.extents.extent(of: "500"), 28)
        cells.show(0..<240)
        XCTAssertEqual(cells.inserting, ["new"])
        XCTAssertEqual(cells.total, 100_001 * 44 - 16)
        XCTAssertLessThan(cells.extents.storageNodes, 12)
        runtime.tree.apply(HostPatch(id: element.id, type: element.type), complete: false)
        XCTAssertFalse(cells.takeItems(), "viewport updates do not re-adopt the source")
    }

    @MainActor
    func testContentAndWindowUpdatesDoNotReindexTheWholeSource() throws {
        let runtime = HostRuntime.still()
        var patch = HostPatch(id: .manual("lazy"), type: .lazyVStack)
        patch.properties = [.items: .strings((0..<10_000).map(String.init))]
        runtime.tree.apply(patch, complete: true)
        let element = try XCTUnwrap(runtime.tree.root)
        let cells = LazyCells(element, in: runtime)
        XCTAssertTrue(cells.takeItems())
        let source = element.lazyItemsRevision
        cells.extents.measure("5", extent: 28)
        cells.show(0..<240)
        let built = cells.built
        let geometry = cells.extents.revision
        for _ in 0..<100 {
            var update = HostPatch(id: element.id, type: element.type)
            update.lazyContentChanged = true
            runtime.tree.apply(update, complete: false)
            XCTAssertTrue(cells.takeItems())
            XCTAssertEqual(element.lazyItemsRevision, source)
            XCTAssertEqual(cells.built, built)
            XCTAssertEqual(cells.extents.revision, geometry)
            XCTAssertTrue(cells.inserting.isEmpty)
            runtime.tree.apply(HostPatch(id: element.id, type: element.type), complete: false)
            XCTAssertFalse(cells.takeItems())
        }
        patch.properties = [.items: .strings(["new"] + (0..<10_000).map(String.init))]
        runtime.tree.apply(patch, complete: false)
        XCTAssertTrue(cells.takeItems())
        XCTAssertNotEqual(element.lazyItemsRevision, source)
        XCTAssertEqual(cells.position(of: "5"), 6)
        XCTAssertEqual(cells.extents.extent(of: "5"), 28)
        cells.show(0..<240)
        XCTAssertEqual(cells.inserting, ["new"])
    }

    func testMeasurementsReplaceOnlyTheirOwnProvisionalExtents() {
        let identities = ["hero", "file", "unseen"]
        var extents = LazyExtents()
        extents.spacing = 0
        XCTAssertEqual(extents.total(in: identities), 132)
        extents.measure("hero", extent: 720)
        XCTAssertEqual(extents.extent(of: "unseen"), 44)
        XCTAssertEqual(extents.total(in: identities), 808)
        extents.measure("file", extent: 20)
        XCTAssertEqual(extents.total(in: identities), 784)
        extents.keep(identities: Set(["file", "unseen"]))
        XCTAssertEqual(extents.total(in: ["file", "unseen"]), 64)
        extents.reset()
        XCTAssertEqual(extents.total(in: ["file", "unseen"]), 88)

        var runs = LazyRunExtents()
        runs.measure(0, extent: 720)
        runs.measure(1, extent: 20)
        XCTAssertEqual(runs.extent(of: 2), 44)
        XCTAssertEqual(runs.total(count: 3), 784)
        runs.reset()
        XCTAssertEqual(runs.total(count: 3), 132)
    }

    func testUnspecifiedLazyStackSpacingUsesEightButExplicitZeroDoesNot() {
        let rows = ["first", "second", "third"]
        var extents = LazyExtents()
        XCTAssertNil(extents.spacing)
        XCTAssertEqual(extents.offset(of: 1, in: rows), 52)
        XCTAssertEqual(extents.total(in: rows), 148)
        extents.spacing = 0
        XCTAssertEqual(extents.offset(of: 1, in: rows), 44)
        XCTAssertEqual(extents.total(in: rows), 132)
        extents.spacing = 12
        XCTAssertEqual(extents.total(in: rows), 156)
        extents.spacing = nil
        XCTAssertEqual(extents.total(in: rows), 148)
    }

    @MainActor
    func testLargeFolderEditKeepsInsertionAnimationWithinRequestedWindow() throws {
        let runtime = HostRuntime.still()
        let original = HostLazySource((0..<10_000).map(String.init))
        var patch = HostPatch(id: .manual("lazy"), type: .lazyVStack)
        patch.lazyRows = original
        runtime.tree.apply(patch, complete: true)
        let element = try XCTUnwrap(runtime.tree.root)
        let cells = LazyCells(element, in: runtime)
        cells.extents.spacing = 0
        cells.takeItems()
        cells.show(0..<240)

        let expanded = HostLazySource((0..<5_000).map { "new-\($0)" } + original.identities,
                                      following: original)
        var update = HostPatch(id: element.id, type: element.type)
        update.lazyRows = expanded
        runtime.tree.apply(update, complete: false)
        cells.takeItems()
        XCTAssertTrue(cells.inserting.isEmpty,
                      "a structural edit does not allocate an animation entry for every new row")
        cells.show(0..<240)
        XCTAssertFalse(cells.inserting.isEmpty)
        XCTAssertLessThan(cells.inserting.count, 32)

        cells.show(100_000..<100_240)
        XCTAssertTrue(cells.inserting.isEmpty,
                      "rows first encountered by scrolling after the edit do not animate as new")
    }

    func testZeroMeasurementsKeepProvisionalRoomForUnseenRows() {
        let identities = ["empty", "card", "last"]
        var extents = LazyExtents()
        extents.spacing = 0
        extents.measure("empty", extent: 0)
        XCTAssertEqual(extents.extent(of: "empty"), 0)
        XCTAssertEqual(extents.estimate, 44)
        XCTAssertEqual(extents.total(in: identities), 88)
        XCTAssertEqual(extents.places(in: 0..<44, overscan: 0, in: identities), 1..<2)
        extents.measure("card", extent: 360)
        XCTAssertEqual(extents.offset(of: 2, in: identities), 360)
        extents.measure("last", extent: 0)
        XCTAssertEqual(extents.total(in: identities), 360, "measured zeros take no space")

        var runs = LazyRunExtents()
        runs.measure(0, extent: 0)
        XCTAssertEqual(runs.extent(of: 0), 0)
        XCTAssertEqual(runs.total(count: 3), 88)
        runs.measure(1, extent: 360)
        runs.measure(2, extent: 0)
        XCTAssertEqual(runs.total(count: 3), 360)
    }

    @MainActor
    func testIncrementalWindowMeasuresTallRowsBeforeExpandingItsEstimate() throws {
        let runtime = HostRuntime.still()
        let identities = (0..<10_000).map(String.init)
        var patch = HostPatch(id: .manual("lazy"), type: .lazyVStack)
        patch.properties = [.items: .strings(identities)]
        runtime.tree.apply(patch, complete: true)
        let cells = LazyCells(try XCTUnwrap(runtime.tree.root), in: runtime)
        cells.takeItems()
        XCTAssertEqual(cells.extents.estimate, 44)
        cells.show(0..<240, realize: 0..<480, measureBeforeExpanding: true)
        XCTAssertEqual(cells.built, 0..<1, "an estimate must not build twelve unmeasured tall cards")
        XCTAssertTrue(cells.needsMeasurement)
        cells.extents.measure("0", extent: 360)
        cells.show(0..<240, realize: 0..<480, measureBeforeExpanding: true)
        XCTAssertEqual(cells.built, 0..<2)
        cells.extents.measure("1", extent: 360)
        cells.show(0..<240, realize: 0..<480, measureBeforeExpanding: true)
        XCTAssertEqual(cells.built, 0..<3, "two intersecting cards plus the existing neighbour policy")
        XCTAssertFalse(cells.needsMeasurement)
    }

    @MainActor
    func testIncrementalWindowResumesWhenActualHeightEqualsTheEstimate() throws {
        let runtime = HostRuntime.still()
        var patch = HostPatch(id: .manual("lazy"), type: .lazyVStack)
        patch.properties = [.items: .strings((0..<100).map(String.init))]
        runtime.tree.apply(patch, complete: true)
        let cells = LazyCells(try XCTUnwrap(runtime.tree.root), in: runtime)
        cells.takeItems()
        cells.show(0..<88, measureBeforeExpanding: true)
        let revision = cells.extents.revision
        cells.extents.measure("0", extent: 44)
        XCTAssertEqual(cells.extents.revision, revision)
        cells.show(0..<88, measureBeforeExpanding: true)
        XCTAssertEqual(cells.built, 0..<2, "measurement completion must resume even without a geometry revision")
        cells.extents.measure("1", extent: 44)
        cells.show(0..<88, measureBeforeExpanding: true)
        XCTAssertEqual(cells.built, 0..<3)
        XCTAssertFalse(cells.needsMeasurement)
    }

    @MainActor
    func testIncrementalGridRequestsWholeRunsAndKeepsSurvivingSeats() throws {
        let runtime = HostRuntime.still()
        var patch = HostPatch(id: .manual("lazy"), type: .lazyVGrid)
        patch.properties = [.items: .strings((0..<100).map(String.init))]
        runtime.tree.apply(patch, complete: true)
        let element = try XCTUnwrap(runtime.tree.root)
        let cells = LazyCells(element, in: runtime)
        cells.takeItems()
        cells.show(0..<240, perRun: 4, grid: true, measureBeforeExpanding: true)
        XCTAssertEqual(cells.built, 0..<4)
        cells.runs.measure(0, extent: 360)
        cells.show(0..<240, perRun: 4, grid: true, measureBeforeExpanding: true)
        XCTAssertEqual(cells.built, 0..<8)

        // A surviving seat in the requested window remains mounted while the
        // preceding inserted rows have not been measured yet.
        patch.children = .arranged([HostPatch(id: .manual("7"), type: .text)])
        runtime.tree.apply(patch, complete: false)
        cells.runs.reset()
        cells.show(0..<240, perRun: 4, grid: true, measureBeforeExpanding: true)
        XCTAssertGreaterThanOrEqual(cells.built.upperBound, 8)
        XCTAssertTrue(element.children.contains { $0.id == .manual("7") })
    }

    @MainActor
    func testExplicitViewIdentityKeepsItsLazySourcePositionAcrossUpdates() throws {
        let runtime = HostRuntime.still()
        var patch = HostPatch(id: .manual("lazy"), type: .lazyVStack)
        patch.properties = [.items: .strings(["source-0", "source-1"])]
        var row = HostPatch(id: .manual("business-row"), type: .text)
        row.lazyIdentity = "source-1"
        patch.children = .arranged([row])
        runtime.tree.apply(patch, complete: true)
        let cells = LazyCells(try XCTUnwrap(runtime.tree.root), in: runtime)
        cells.takeItems()
        let mounted = try XCTUnwrap(cells.item("source-1"))
        XCTAssertEqual(mounted.id, .manual("business-row"))
        XCTAssertEqual(cells.mounted.map(\.place), [1])
        row.lazyIdentity = "source-0"
        patch.children = .changed([row])
        runtime.tree.apply(patch, complete: false)
        XCTAssertTrue(cells.item("source-0") === mounted)
        XCTAssertEqual(cells.mounted.map(\.place), [0])
        row.lazyIdentity = nil
        row.properties = [.text: .string("Updated")]
        patch.children = .changed([row])
        runtime.tree.apply(patch, complete: false)
        XCTAssertEqual(mounted.lazyIdentity, "source-0", "sparse content patches keep source ownership")
        XCTAssertEqual(cells.mounted.map(\.place), [0])
    }

    func testEstimatedLengthAndExactIntersections() {
        let identities = (0..<10_000).map(String.init)
        var extents = LazyExtents()
        extents.spacing = 0
        extents.measure("0", extent: 40)
        XCTAssertEqual(extents.total(in: identities), 439_996, accuracy: 0.001)
        XCTAssertEqual(extents.places(in: 876..<1_140, overscan: 0, in: identities), 20..<26)
        XCTAssertEqual(extents.places(in: 877..<1_141, overscan: 0, in: identities), 20..<27)
        XCTAssertEqual(extents.places(in: 439_952..<440_010, overscan: 0, in: identities), 9_999..<10_000)
        XCTAssertEqual(extents.places(in: 439_996..<440_010, overscan: 0, in: identities), 0..<0)
        extents.spacing = 10
        extents.padding = (5, 7)
        XCTAssertEqual(extents.places(in: 45..<55, overscan: 0, in: identities), 0..<0)
        XCTAssertEqual(extents.total(in: identities), 539_998, accuracy: 0.001)
    }

    func testVariableExtentsMatchIntersectionsAcrossTheWholeRun() {
        let identities = (0..<200).map(String.init)
        let sizes = (0..<200).map { Double(($0 * 37) % 113 + 1) }
        var extents = LazyExtents()
        extents.spacing = 3
        extents.padding = (11, 9)
        for index in identities.indices { extents.measure(identities[index], extent: sizes[index]) }
        var origins: [Double] = []
        var position = 11.0
        for size in sizes { origins.append(position); position += size + 3 }
        for start in stride(from: 0.0, through: position, by: 17) {
            let intersecting = sizes.indices.filter { origins[$0] < start + 130 && origins[$0] + sizes[$0] > start }
            let expected = intersecting.first.map { $0..<(intersecting.last! + 1) } ?? 0..<0
            XCTAssertEqual(extents.places(in: start..<start + 130, overscan: 0, in: identities), expected)
        }
        let reversed = Array(identities.reversed())
        extents.keep(identities: Set(reversed))
        XCTAssertEqual(extents.offset(of: 1, in: reversed), 11 + sizes.last! + 3)
    }

    func testGridMeasurementsCanShrinkAndRegroup() {
        var runs = LazyRunExtents()
        runs.measure(0, extent: 100)
        XCTAssertEqual(runs.total(count: 500), 22_056)
        runs.measure(0, extent: 20)
        XCTAssertEqual(runs.total(count: 500), 21_976)
        runs.measure(1, extent: 40)
        XCTAssertEqual(runs.offset(of: 2, count: 500), 60)
        let revision = runs.revision
        runs.measure(1, extent: 40)
        XCTAssertEqual(runs.revision, revision)
        runs.reset()
        runs.measure(0, extent: 50)
        XCTAssertEqual(runs.total(count: 250), 11_006)
        XCTAssertEqual(runs.places(in: 94..<182, overscan: 0, count: 250), 2..<4)
    }

    @MainActor
    func testDeletingRowsKeepsKnownSizesAndTheVisibleAnchor() throws {
        let runtime = HostRuntime.still()
        var identities = ["header"] + (0..<1_000).map(String.init) + ["footer"]
        var patch = HostPatch(id: .manual("lazy"), type: .lazyVStack)
        patch.properties = [.items: .strings(identities)]
        runtime.tree.apply(patch, complete: true)
        let cells = LazyCells(try XCTUnwrap(runtime.tree.root), in: runtime)
        cells.takeItems()
        cells.extents.spacing = 8
        // A short header/footer must not replace the many row measurements after each deletion.
        for identity in identities {
            cells.extents.measure(identity, extent: identity == "header" || identity == "footer" ? 20 : 52)
        }
        cells.show((cells.total - 600)..<cells.total)
        for removed in ["0", "998", "500"] {
            let before = cells.total
            identities.removeAll { $0 == removed }
            patch.properties = [.items: .strings(identities)]
            patch.lazyContentChanged = true
            runtime.tree.apply(patch, complete: false)
            XCTAssertTrue(cells.takeItems())
            XCTAssertEqual(before - cells.total, 60, accuracy: 0.001)
            XCTAssertEqual(cells.correctedOrigin(), cells.total - 600)
            XCTAssertEqual(cells.extents.extent(of: "header"), 20)
            XCTAssertEqual(cells.extents.extent(of: "999"), 52)
        }
        // An update with unchanged identities keeps the sizes it already knows;
        // changed rows re-measure on their next layout pass.
        runtime.tree.apply(patch, complete: false)
        XCTAssertTrue(cells.takeItems())
        cells.extents.measure("999", extent: 100)
        XCTAssertEqual(cells.extents.extent(of: "501"), 52)
        XCTAssertEqual(cells.extents.extent(of: "999"), 100)

    }

    func testViewportLookupAndMeasurementUpdateBenchmark() {
        for count in [1_000, 10_000] {
            let identities = (0..<count).map(String.init)
            var extents = LazyExtents()
            for row in 0..<20 { extents.measure(identities[row], extent: Double(40 + row % 7 * 9)) }
            _ = extents.total(in: identities)
            var checksum = 0
            for step in 0..<10_000 {
                let offset = Double((step * 137) % (count * 60))
                checksum += extents.places(in: offset..<offset + 480, overscan: 0, in: identities).count
            }
            for row in 20..<120 {
                extents.measure(identities[row], extent: Double(40 + row % 7 * 9))
                _ = extents.places(in: Double(row * 65)..<Double(row * 65 + 480), overscan: 0, in: identities)
            }
            XCTAssertGreaterThan(checksum, 10_000)
        }
    }

    func testScrollAxesUseViewportSpaceAndKeepCrossAxisAndBounds() {
        var values = LayoutValues()
        values.scrollAxes = .vertical
        XCTAssertEqual(values.sized(LayoutSize(width: 120, height: 40_000)), LayoutSize(width: 120, height: 0))
        values.minimumHeight = 80
        values.maximumHeight = 240
        XCTAssertEqual(values.sized(LayoutSize(width: 120, height: 40_000)).height, 80)
        values.height = 300
        XCTAssertEqual(values.sized(LayoutSize(width: 120, height: 40_000)).height, 240)
        values = LayoutValues()
        values.scrollAxes = .horizontal
        XCTAssertEqual(values.sized(LayoutSize(width: 40_000, height: 56)), LayoutSize(width: 0, height: 56))
    }
}
