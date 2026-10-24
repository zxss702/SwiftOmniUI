// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import SwiftOmniUIConformance
import XCTest

@MainActor private final class LazyRowPreparationProbe: WinUISingleChildView {
    var nativeProposals: [ProposedViewSize] = []

    override func prepareMeasure(width: Double, height: Double? = nil) {
        nativeProposals.append(ProposedViewSize(width: width, height: height))
        super.prepareMeasure(width: width, height: height)
    }
}

@MainActor private final class RowBuilds {
    var calls: [Int: Int] = [:]
}

private struct HoverWorkRow: View {
    let index: Int
    let builds: RowBuilds
    @State private var hovered = false

    var body: some View {
        builds.calls[index, default: 0] += 1
        return HStack(spacing: 0) {
            ForEach(0..<8) { part in
                VStack(spacing: 0) {
                    Text("\(index):\(part)")
                    Text("detail")
                }
            }
        }
        .frame(height: 32)
        .background(hovered ? Color.black : Color.clear)
        .onHover { hovered = $0 }
        .id("hover-\(index)")
    }
}

final class WinUILazyInvalidationTests: XCTestCase {
    func testNewWrappedRowPreparesOnlyItsFinalNativeAllocation() throws {
        try onUIThread {
            for grid in [false, true] {
                let host = WinUIRenderer.running(reducesMotion: true) {
                    ScrollView {
                        if grid {
                            LazyVGrid(columns: [GridItem(.fixed(120))], spacing: 0) { Text("row") }
                        } else { LazyVStack(spacing: 0) { Text("row") } }
                    }.frame(width: 120, height: 240)
                }
                for _ in 0..<16 { host.step() }
                let original = try XCTUnwrap(host.views(WinUILazyView.self).first)
                let identity = try XCTUnwrap(original.mounted.keys.first)
                let element = try XCTUnwrap(original.sourceElement)
                let cells = LazyCells(element, in: host.runtime)
                cells.takeItems()
                let lazy: WinUILazyView
                if grid {
                    let layout = WinUILazyGridView(axis: .vertical, cells: cells)
                    layout.tracks = [GridItem(.fixed(120))]
                    lazy = layout
                } else { lazy = WinUILazyStackView(axis: .vertical, cells: cells) }
                let words = WinUILabelView()
                words.setText("A file name with enough words to wrap across several lines")
                words.setLines(breaking: .wordWrap, maximum: nil)
                let row = LazyRowPreparationProbe()
                row.setItems([WinUILayoutItem(view: words)])
                lazy.setItems([(identity, WinUILayoutItem(view: row))])

                // This is the native Measure path used by a newly mounted
                // window, before its final row heights have been selected.
                lazy.prepareLayoutContent(in: Rect(0, 0, 120, 240), measuringNative: true)
                XCTAssertTrue(row.nativeProposals.isEmpty,
                              "learning row height must not prepare a provisional native subtree")
                lazy.prepareMeasure(width: 120, height: 240)
                lazy.arrange(width: 120, height: 240)
                XCTAssertFalse(row.nativeProposals.isEmpty)
                XCTAssertTrue(row.nativeProposals.allSatisfy { $0.height != nil && $0.height!.isFinite })
                XCTAssertGreaterThan(words.desiredSize.height, 20)
                XCTAssertEqual(row.laidOutFrame.height, lazy.measured[identity]?.size.height ?? 0, accuracy: 1)
                XCTAssertGreaterThan(words.laidOutFrame.height, 20)
            }
        }
    }

    func testArrangeMeasuresRowsBeforeConsumingPendingAnimation() throws {
        try onUIThread {
            for grid in [false, true] {
                let host = WinUIRenderer.running(clock: TestClock()) {
                    ScrollView {
                        let rows = ForEach(0..<4) { index in
                            Text("Row \(index)").frame(height: 32)
                        }
                        if grid {
                            LazyVGrid(columns: [GridItem(.fixed(120))], spacing: 0) { rows }
                        } else {
                            LazyVStack(spacing: 0) { rows }
                        }
                    }.frame(width: 240, height: 200)
                }
                for _ in 0..<16 { host.step(); host.frame() }
                let lazy = try XCTUnwrap(host.views(WinUILazyView.self).first)
                let identity = try XCTUnwrap(lazy.mounted.keys.first)
                lazy.measured.removeValue(forKey: identity)
                lazy.measuredRevisions.removeValue(forKey: identity)
                lazy.cells.animatesChanges = true
                lazy.cells.inserting.insert(identity)
                lazy.places.patchArrived()

                lazy.arrange(width: 240, height: 200)
                let row = try XCTUnwrap(lazy.mounted[identity]?.view)
                let measured = try XCTUnwrap(lazy.measured[identity])
                XCTAssertEqual(lazy.measuredRevisions[identity], row.measurementRevision)
                XCTAssertEqual(measured.size.height, 32, accuracy: 1)
                XCTAssertGreaterThan(row.laidOutFrame.width, 0)
                XCTAssertEqual(row.laidOutFrame.height, 32, accuracy: 1)
                XCTAssertFalse(lazy.cells.animatesChanges)
                XCTAssertFalse(lazy.cells.inserting.contains(identity))
            }
        }
    }

    func testHoverDoesNotResolveUnchangedLayoutSubtreesAsSourceGrows() throws {
        try onUIThread {
            let count = State(wrappedValue: 100)
            let builds = RowBuilds()
            let host = WinUIRenderer.running(reducesMotion: true) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(0..<count.wrappedValue) { HoverWorkRow(index: $0, builds: builds) }
                    }
                }.frame(width: 480, height: 240)
            }
            for expandedCount in [100, 10_000, 100] {
                count.wrappedValue = expandedCount
                for _ in 0..<20 { host.step(); host.frame() }
                let lazy = try XCTUnwrap(host.views(WinUILazyView.self).first)
                XCTAssertLessThan(lazy.mounted.count, 80)
                XCTAssertLessThan(builds.calls.count, 80, "offscreen bodies stay unevaluated")
                let row = try XCTUnwrap(lazy.mounted[lazy.cells.orderedIdentities[0]]?.view)
                let elements = host.views(WinUIView.self).compactMap { $0.sourceElement?.winUI }
                // Resolve once before measuring reuse, including window-owned ancestors.
                for element in elements { _ = element.resolvedLayoutValues }
                let inputs = elements.map(\.layoutInputResolutions)
                let collections = elements.map(\.layoutItemCollections)
                let otherBodies = builds.calls.filter { $0.key != 0 }
                let measurements = lazy.cells.measurements
                let lazyRevision = lazy.measurementRevision

                row.heard(.pointer(.pointerEntered, .zero))
                for _ in 0..<4 { host.step(); host.frame() }

                XCTAssertEqual(row.sourceElement?.value(.background), Color.black.propValue)
                XCTAssertEqual(elements.map(\.layoutInputResolutions), inputs)
                for (element, before) in zip(elements, collections)
                    where element.view is WinUIStackView || element.view is WinUILazyView {
                    XCTAssertEqual(element.layoutItemCollections, before)
                }
                XCTAssertEqual(builds.calls.filter { $0.key != 0 }, otherBodies)
                XCTAssertEqual(lazy.cells.measurements, measurements)
                XCTAssertEqual(lazy.measurementRevision, lazyRevision,
                               "a drawing-only row patch must not schedule a native Lazy measure")
                XCTAssertFalse(host.runtime.animator.isMoving)
                row.heard(.pointer(.pointerExited, .zero))
                for _ in 0..<4 { host.step(); host.frame() }
                XCTAssertEqual(row.sourceElement?.value(.background), Color.clear.propValue)
            }
        }
    }

    func testFiniteVerticalWidthDoesNotRecomputeHistoricalNaturalWidth() throws {
        try onUIThread {
            let host = WinUIRenderer.running(reducesMotion: true) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(0..<100) { index in
                            Text("Row \(index)").frame(height: 32)
                        }
                    }
                }.frame(width: 320, height: 240)
            }
            for _ in 0..<12 { host.step(); host.frame() }
            let lazy = try XCTUnwrap(host.views(WinUILazyStackView.self).first)
            lazy.standsAt = 320
            lazy.prepareLayoutContent(in: Rect(0, 0, 320, lazy.laidOutFrame.height), measuringNative: true)
            let offscreen = lazy.cells.orderedIdentities[50]
            XCTAssertNil(lazy.mounted[offscreen])
            lazy.acrossWidest[offscreen] = 900
            lazy.naturalAcross = 44
            lazy.invalidateMeasure()

            let fixed = lazy.contentSize(width: 320)
            XCTAssertEqual(fixed.width, 320)
            XCTAssertEqual(lazy.naturalAcross, 44,
                           "fixed-width vertical layout does not scan historical row widths")

            lazy.invalidateMeasure()
            lazy.prepareLayoutContent(in: Rect(0, 0, 320, lazy.laidOutFrame.height), measuringNative: true)
            let intrinsic = lazy.contentSize(width: nil)
            XCTAssertGreaterThanOrEqual(intrinsic.width, 900,
                                        "intrinsic layout still includes the widest offscreen row")
        }
    }

    func testHorizontalLazyKeepsTheHistoricalNaturalHeight() throws {
        try onUIThread {
            let host = WinUIRenderer.running(reducesMotion: true) {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(0..<100) { index in
                            Text("Row \(index)").frame(width: 48, height: 32)
                        }
                    }
                }.frame(width: 240, height: 120)
            }
            for _ in 0..<12 { host.step(); host.frame() }
            let lazy = try XCTUnwrap(host.views(WinUILazyStackView.self).first)
            lazy.prepareLayoutContent(in: lazy.laidOutFrame, measuringNative: true)
            let offscreen = lazy.cells.orderedIdentities[50]
            XCTAssertNil(lazy.mounted[offscreen])
            lazy.acrossWidest[offscreen] = 160
            lazy.invalidateMeasure()
            lazy.prepareLayoutContent(in: lazy.laidOutFrame, measuringNative: true)

            let size = lazy.contentSize(width: nil)
            XCTAssertGreaterThanOrEqual(size.height, 160,
                                        "horizontal intrinsic size retains previously measured rows")
        }
    }

    func testFiniteRowPreparationRefreshesCachedIntrinsicWidthWithUnchangedExtent() throws {
        try onUIThread {
            let host = WinUIRenderer.running(reducesMotion: true) {
                ScrollView {
                    LazyVStack(spacing: 0) { Text("i").frame(height: 32).id("row") }
                }.frame(width: 320, height: 120)
            }
            let lazy = try XCTUnwrap(host.views(WinUILazyStackView.self).first)
            let row = try XCTUnwrap(host.view(id: .manual("row")) as? WinUILayoutView)
            let label = try XCTUnwrap(host.views(WinUITextView.self).first)
            let total = lazy.cells.total
            label.setText("A substantially wider row")
            row.invalidateMeasurements()
            let before = lazy.naturalSize(width: nil)

            lazy.prepareMeasure(width: 320, height: lazy.laidOutFrame.height)

            XCTAssertEqual(lazy.cells.total, total)
            XCTAssertGreaterThan(lazy.naturalSize(width: nil).width, before.width,
                                 "a fixed-width pass also refreshes its cached intrinsic answer")
        }
    }

    func testDerivedExpansionInputsInvalidateThroughNestedLayouts() throws {
        try onUIThread {
            let expands = State(wrappedValue: false)
            let host = WinUIRenderer.running(reducesMotion: true) {
                VStack {
                    HStack {
                        Text("row").frame(maxWidth: expands.wrappedValue ? .infinity : 80)
                    }.id("inner")
                }.id("outer")
            }
            let outer = try XCTUnwrap(host.runtime.tree.root?.first(id: .manual("outer"))?.winUI)
            let inner = try XCTUnwrap(host.runtime.tree.root?.first(id: .manual("inner"))?.winUI)
            _ = outer.resolvedLayoutValues
            let before = outer.layoutInputResolutions
            expands.wrappedValue = true
            host.runtime.pump.turn()
            XCTAssertEqual(inner.resolvedLayoutValues.expandingAxes, .horizontal)
            XCTAssertEqual(outer.resolvedLayoutValues.expandingAxes, .horizontal)
            XCTAssertGreaterThan(outer.layoutInputResolutions, before)
            expands.wrappedValue = false
            host.runtime.pump.turn()
            XCTAssertEqual(outer.resolvedLayoutValues.expandingAxes, .neither)
        }
    }

    func testExistingLazyRowSizeChangesAnimateWithoutChangingIdentities() throws {
        try onUIThread {
            for gated in [false, true] {
                let height = State(wrappedValue: 28.0)
                let clock = TestClock()
                let law = Animation.eased(200, .linear)
                let host = WinUIRenderer.running(clock: clock) {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(0..<100) { index in
                                Text("row \(index)")
                                    .frame(height: index == 0 ? height.wrappedValue : 28)
                                    .id("size-\(index)")
                            }
                        }.animation(gated ? law : .inherited, value: height.wrappedValue)
                    }.frame(width: 320, height: 240)
                }
                for _ in 0..<12 { host.step(); host.frame() }
                XCTAssertFalse(host.runtime.animator.isMoving, "the first window arrives without an entrance animation")
                let lazy = try XCTUnwrap(host.views(WinUILazyView.self).first)
                let source = lazy.cells.element?.lazyRows
                let row = try XCTUnwrap(host.view(id: .manual("size-1")))
                let before = row.placedFrame.y
                if gated { height.wrappedValue = 56 }
                else { withAnimation(law) { height.wrappedValue = 56 } }
                for _ in 0..<12 { host.step(); host.frame() }
                XCTAssertTrue(lazy.cells.element?.lazyRows === source)
                XCTAssertTrue(host.view(id: .manual("size-1")) === row)
                clock.now = 100
                for _ in 0..<4 { host.frame(); host.step() }
                XCTAssertEqual(row.placedFrame.y, before + 14, accuracy: 1)
                clock.now = 200
                for _ in 0..<4 { host.frame(); host.step() }
                XCTAssertEqual(row.placedFrame.y, before + 28, accuracy: 1)
            }
        }
    }

    func testInsertedLazyRowsMoveSurvivingFollowersThroughIntermediatePositions() throws {
        try onUIThread {
            let rows = State(wrappedValue: Array(0..<40))
            let clock = TestClock()
            let law = Animation.eased(200, .linear)
            let host = WinUIRenderer.running(clock: clock) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows.wrappedValue) { index in
                            Text("row \(index)").frame(height: 28).id("entry-\(index)")
                        }
                    }
                }.frame(width: 320, height: 240)
            }
            for _ in 0..<12 { host.step(); host.frame() }
            let follower = try XCTUnwrap(host.view(id: .manual("entry-1")))
            let before = follower.placedFrame.y
            withAnimation(law) { rows.wrappedValue.insert(contentsOf: [-3, -2, -1], at: 1) }
            for _ in 0..<12 { host.step(); host.frame() }
            XCTAssertTrue(host.view(id: .manual("entry-1")) === follower)
            clock.now = 100
            for _ in 0..<4 { host.frame(); host.step() }
            XCTAssertEqual(follower.placedFrame.y, before + 42, accuracy: 1)
            clock.now = 200
            for _ in 0..<4 { host.frame(); host.step() }
            XCTAssertEqual(follower.placedFrame.y, before + 84, accuracy: 1)
            withAnimation(law) { rows.wrappedValue.removeSubrange(1..<4) }
            for _ in 0..<12 { host.step(); host.frame() }
            clock.now = 300
            for _ in 0..<4 { host.frame(); host.step() }
            XCTAssertEqual(follower.placedFrame.y, before + 42, accuracy: 1)
            clock.now = 400
            for _ in 0..<4 { host.frame(); host.step() }
            XCTAssertEqual(follower.placedFrame.y, before, accuracy: 1)
        }
    }
}
