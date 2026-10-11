// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest
import Foundation
import SwiftOmniUIConformance
import CSwiftOmniUIWinUI
import WinSDK

/// A `LazyVStack` on WinUI answers the same window questions as everywhere:
/// the rows the scroller's reach holds are mounted, and no more.
final class WinUILazyTests: XCTestCase {
    func testChangedGeometryCannotRewriteLaterScrollInput() throws {
        try onUIThread {
            for kind in 0..<4 {
                let horizontal = kind % 2 == 1
                let perRun = kind < 2 ? 1 : 4
                let rows = State(wrappedValue: Array(0..<1_000))
                let height = State(wrappedValue: 40.0)
                let host = WinUIRenderer.running {
                    let content = ForEach(rows.wrappedValue) { number in
                        Text("Row \(number)").frame(width: horizontal ? height.wrappedValue : 80,
                                                  height: horizontal ? 40 : height.wrappedValue)
                    }
                    return ScrollView(horizontal ? .horizontal : .vertical) {
                        Group {
                            if kind == 0 { LazyVStack(spacing: 0) { content } }
                            else if kind == 1 { LazyHStack(spacing: 0) { content } }
                            else if kind == 2 {
                                LazyVGrid(columns: Array(repeating: GridItem(.fixed(80)), count: 4), spacing: 0) { content }
                            } else {
                                LazyHGrid(rows: Array(repeating: GridItem(.fixed(40)), count: 4), spacing: 0) { content }
                            }
                        }
                    }.frame(width: 480, height: 240).animation(nil)
                }
                for _ in 0..<12 { host.step() }
                let lazy = try XCTUnwrap(host.views(WinUILazyView.self).first)
                let scroll = try XCTUnwrap(host.views(WinUIScrollView.self).first)
                scroll.scroller.move(to: Point(horizontal ? 800 : 0, horizontal ? 0 : 800))
                for _ in 0..<8 { host.step() }
                for phase in 0..<6 {
                    let span = try XCTUnwrap(lazy.span)
                    let first = kind < 2 ? lazy.cells.places(in: span, overscan: 0).lowerBound
                        : lazy.cells.runs.places(in: span, overscan: 0, count: rows.wrappedValue.count / perRun).lowerBound * perRun
                    let identity = lazy.cells.identities[first]
                    let row = try XCTUnwrap(lazy.mounted[identity]?.view)
                    let original = horizontal ? row.origin.x : row.origin.y
                    withAnimation(nil) {
                        if phase < 2 { rows.wrappedValue.removeFirst(perRun) }
                        else if phase < 4 { height.wrappedValue += 8 }
                        else { height.wrappedValue -= 8 }
                    }
                    host.runtime.pump.turn()
                    host.layOut()
                    let offset = scroll.scroller.nextOffset ?? scroll.scroller.standing.offset
                    let along = (horizontal ? offset.x : offset.y) + (phase.isMultiple(of: 2) ? 24 : -24)
                    let target = Point(horizontal ? along : 0, horizontal ? 0 : along)
                    scroll.scroller.move(to: target)
                    for _ in 0..<12 { host.step() }
                    let standing = scroll.scroller.standing.offset
                    XCTAssertEqual(horizontal ? row.origin.x : row.origin.y,
                                   original - (phase.isMultiple(of: 2) ? 24 : -24), accuracy: 1,
                                   "kind \(kind), phase \(phase): geometry must preserve the visible anchor and new input")
                    var displayed = [Double](repeating: 0, count: 6)
                    swiftomniui_winui_scroller_viewport(scroll.scroller.handle, lazy.handle, &displayed)
                    XCTAssertEqual(-displayed[horizontal ? 4 : 5], horizontal ? standing.x : standing.y, accuracy: 1)
                    XCTAssertFalse(lazy.mounted.isEmpty)
                }
            }
        }
    }

    func testContinuousScrollWorkIsBoundedByIncomingRows() throws {
        try onUIThread {
            for count in [1_000, 10_000] {
                for kind in 0..<4 {
                    let host = WinUIRenderer.running { ExactLazyPage(kind: kind, count: count, complex: true) }
                    for _ in 0..<12 { host.step() }
                    let scroll = try XCTUnwrap(host.views(WinUIScrollView.self).first)
                    let lazy = try XCTUnwrap(host.views(WinUILazyView.self).first)
                    let horizontal = kind % 2 == 1
                    let extent = horizontal ? 80.0 : 40.0
                    let perRun = kind < 2 ? 1 : 4
                    let start = extent * 20 + 5
                    scroll.scroller.move(to: Point(horizontal ? start : 0, horizontal ? 0 : start))
                    for _ in 0..<8 { host.step() }
                    let built = lazy.cells.built
                    let retained = lazy.mounted.mapValues(\.view)
                    let measured = lazy.cells.measurements
                    let requests = lazy.cells.requests
                    for step in 1...16 {
                        let offset = start + Double(step)
                        scroll.scroller.move(to: Point(horizontal ? offset : 0, horizontal ? 0 : offset))
                        host.step()
                        host.layOut()
                        XCTAssertEqual(lazy.cells.built, built)
                    }
                    XCTAssertEqual(lazy.cells.measurements, measured, "unchanged window: count \(count), kind \(kind)")
                    XCTAssertEqual(lazy.cells.requests, requests)
                    for (identity, view) in retained { XCTAssertTrue(lazy.mounted[identity]?.view === view) }
                    var displayed = [Double](repeating: 0, count: 6)
                    // A program's move lands a few compositor ticks after it is asked (`ScrollTo`'s queue).
                    host.settle {
                        swiftomniui_winui_scroller_viewport(scroll.scroller.handle, lazy.handle, &displayed)
                        return abs(-displayed[horizontal ? 4 : 5] - (start + 16)) < 1
                    }
                    XCTAssertEqual(-displayed[horizontal ? 4 : 5], start + 16, accuracy: 1)
                    XCTAssertEqual(lazy.cells.built, built)
                    let beforeBoundary = lazy.cells.measurements
                    let next = extent * 21 + 5
                    scroll.scroller.move(to: Point(horizontal ? next : 0, horizontal ? 0 : next))
                    for _ in 0..<6 { host.step() }
                    let incoming = lazy.mounted.keys.filter { retained[$0] == nil }
                    XCTAssertEqual(incoming.count, perRun)
                    XCTAssertEqual(lazy.cells.measurements - beforeBoundary, incoming.count,
                                   "measure each incoming row once per proposal: count \(count), kind \(kind)")
                    let idle = [lazy.cells.searches, lazy.cells.requests, lazy.cells.measurements]
                    for _ in 0..<20 { host.step() }
                    XCTAssertEqual([lazy.cells.searches, lazy.cells.requests, lazy.cells.measurements], idle)
                }
            }
        }
    }

    func testSpeculativeProposalsKeepEveryLazyContainersCommittedGeometry() throws {
        try onUIThread {
            for kind in 0..<4 {
                let horizontal = kind % 2 == 1
                let rows = State(wrappedValue: Array(0..<100))
                let host = WinUIRenderer.running(room: LayoutSize(width: 480, height: 240)) {
                    let content = ForEach(rows.wrappedValue) { number in
                        Text("Row \(number): " + String(repeating: "words that wrap ", count: 12))
                            .frame(width: horizontal ? 80 : nil, height: horizontal ? 40 : nil)
                            .frame(maxWidth: horizontal ? nil : .infinity)
                    }
                    return ScrollView(horizontal ? .horizontal : .vertical) {
                        Group {
                            if kind == 0 { LazyVStack(spacing: 0) { content } }
                            else if kind == 1 { LazyHStack(spacing: 0) { content } }
                            else if kind == 2 {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 0)], spacing: 0) { content }
                            } else {
                                LazyHGrid(rows: [GridItem(.fixed(40)), GridItem(.fixed(40))], spacing: 0) { content }
                            }
                        }
                    }
                    .frame(width: 480, height: 240)
                    .animation(nil)
                }
                for _ in 0..<8 { host.step() }
                let lazy = try XCTUnwrap(host.views(WinUILazyView.self).first)
                let scroll = try XCTUnwrap(host.views(WinUIScrollView.self).first)
                let window = try XCTUnwrap(lazy.cells.window)
                XCTAssertEqual(window.perRun, kind == 2 ? 4 : (kind == 3 ? 2 : 1))
                XCTAssertGreaterThan(lazy.mounted.count, window.perRun)
                let canonical = lazy.laidOutFrame.width
                _ = lazy.naturalSize(width: canonical)
                let runCount = (lazy.cells.identities.count + window.perRun - 1) / window.perRun
                let total = kind < 2 ? lazy.cells.total : lazy.cells.runs.total(count: runCount)
                let revisions = [lazy.cells.extents.revision, lazy.cells.runs.revision]
                let built = lazy.cells.built
                let retained = lazy.mounted.mapValues(\.view)
                let placed = retained.mapValues(\.placedFrame)
                let native = retained.mapValues(\.laidOutFrame)
                let origins = retained.mapValues(\.origin)
                let viewport = scroll.scroller.laidOutFrame
                let standing = scroll.scroller.standing
                XCTAssertGreaterThan(horizontal ? standing.reach.x : standing.reach.y, 0)
                for phase in 0..<2 {
                    if phase == 0 {
                        for proposal: Double? in [nil, 0, 72, canonical, nil, 72, canonical] {
                            _ = lazy.naturalSize(width: proposal)
                        }
                        let revision = lazy.measurementRevision
                        _ = lazy.measure(width: canonical, height: .infinity)
                        _ = lazy.measure(width: 72, height: .infinity)
                        lazy.arrange(width: canonical, height: lazy.laidOutFrame.height)
                        WinUIDoorbell.turn()
                        XCTAssertEqual(lazy.measurementRevision, revision,
                                       "speculative native measurement must not invalidate committed geometry")
                    } else {
                        host.layOut()
                        for _ in 0..<8 { host.step() }
                    }
                    XCTAssertEqual([lazy.cells.extents.revision, lazy.cells.runs.revision], revisions)
                    XCTAssertEqual(kind < 2 ? lazy.cells.total : lazy.cells.runs.total(count: runCount), total)
                    XCTAssertEqual(lazy.cells.built, built)
                    XCTAssertEqual(lazy.cells.window?.span, window.span)
                    XCTAssertEqual(lazy.cells.window?.revision, window.revision)
                    XCTAssertEqual(lazy.cells.window?.perRun, window.perRun)
                    XCTAssertEqual(scroll.scroller.laidOutFrame, viewport)
                    XCTAssertEqual(scroll.scroller.standing.reach, standing.reach)
                    XCTAssertEqual(scroll.scroller.standing.offset, standing.offset)
                    XCTAssertEqual(Set(lazy.mounted.keys), Set(retained.keys))
                    for (identity, view) in retained {
                        XCTAssertTrue(lazy.mounted[identity]?.view === view)
                        XCTAssertEqual(view.placedFrame, placed[identity])
                        XCTAssertEqual(view.laidOutFrame, native[identity])
                        XCTAssertEqual(view.origin, origins[identity])
                        XCTAssertGreaterThan(view.laidOutFrame.width, 0)
                        XCTAssertGreaterThan(view.laidOutFrame.height, 0)
                    }
                }
            }
        }
    }

    func testAddingToAnEmptyLazyStackRunsTheInsertionTransition() throws {
        try onUIThread {
            let clock = TestClock()
            let rows = State(wrappedValue: [Int]())
            let host = WinUIRenderer.running(clock: clock) {
                LazyVStack(spacing: 0) {
                    ForEach(rows.wrappedValue) { number in
                        Text("Row \(number)").frame(height: 40)
                    }
                }
                .animation(.eased(200, .linear))
                .frame(width: 240, height: 240)
            }

            for _ in 0..<8 {
                host.step()
                host.frame()
            }
            let lazy = try XCTUnwrap(host.views(WinUILazyView.self).first)
            for number in 0..<2 {
                rows.wrappedValue = [number]
                for _ in 0..<8 {
                    host.step()
                    host.frame()
                }
                let row = try XCTUnwrap(lazy.mounted.values.first?.view)
                XCTAssertEqual(row.drawnOpacity, 0, accuracy: 0.01)
                clock.now += 100
                for _ in 0..<8 {
                    host.step()
                    host.frame()
                }
                XCTAssertEqual(row.drawnOpacity, 0.5, accuracy: 0.01)
                clock.now += 100
                for _ in 0..<8 {
                    host.step()
                    host.frame()
                }
                XCTAssertEqual(row.drawnOpacity, 1, accuracy: 0.01)
                rows.wrappedValue = []
                for _ in 0..<8 {
                    host.step()
                    host.frame()
                }
            }

        }
    }

    func testDeletingBeforeTheViewportKeepsThePresentedAnchor() throws {
        try onUIThread {
            for kind in 0..<4 {
                let horizontal = kind % 2 == 1
                let perRun = kind < 2 ? 1 : 2
                let clock = TestClock()
                let rows = State(wrappedValue: Array(0..<100))
                let host = WinUIRenderer.running(clock: clock) {
                    let content = ForEach(rows.wrappedValue) { number in
                        Text("Row \(number)").frame(width: 40, height: 40)
                    }
                    return ScrollView(horizontal ? .horizontal : .vertical) {
                        Group {
                            if kind == 0 { LazyVStack(spacing: 0) { content } }
                            else if kind == 1 { LazyHStack(spacing: 0) { content } }
                            else if kind == 2 {
                                LazyVGrid(columns: [GridItem(.fixed(40)), GridItem(.fixed(40))], spacing: 0) { content }
                            } else {
                                LazyHGrid(rows: [GridItem(.fixed(40)), GridItem(.fixed(40))], spacing: 0) { content }
                            }
                        }
                        .animation(.eased(200, .linear))
                    }
                    .frame(width: 240, height: 240)
                }

                for _ in 0..<8 {
                    host.step()
                    host.frame()
                }
                let scroll = try XCTUnwrap(host.views(WinUIScrollView.self).first)
                let lazy = try XCTUnwrap(host.views(WinUILazyView.self).first)
                scroll.scroller.move(to: Point(horizontal ? 400 : 0, horizontal ? 0 : 400))
                for _ in 0..<8 {
                    host.step()
                    host.frame()
                }
                let identity = lazy.cells.identities[10 * perRun]
                let retained = try XCTUnwrap(lazy.mounted[identity]?.view)
                for removed in [11, 9, 0] {
                    let relative = (horizontal ? retained.placedFrame.x : retained.placedFrame.y)
                        - (horizontal ? scroll.scroller.standing.offset.x : scroll.scroller.standing.offset.y)
                    let began = clock.now
                    rows.wrappedValue.removeAll { (removed * perRun..<((removed + 1) * perRun)).contains($0) }
                    for tick in stride(from: 0.0, through: 240.0, by: 40) {
                        clock.now = began + tick
                        for _ in 0..<8 {
                            host.step()
                            host.frame()
                        }
                        XCTAssertEqual((horizontal ? retained.placedFrame.x : retained.placedFrame.y)
                                       - (horizontal ? scroll.scroller.standing.offset.x : scroll.scroller.standing.offset.y), relative, accuracy: 1,
                                       "removing \(removed), at \(tick) ms must keep the visible anchor in place")
                    }
                }
            }
        }
    }

    func testDataChangesAnimateInEveryLazyDirection() throws {
        try onUIThread {
            for kind in 0..<4 {
                let clock = TestClock()
                let rows = State(wrappedValue: Array(0..<40))
                let extent = State(wrappedValue: 40.0)
                let horizontal = kind % 2 == 1
                let perRun = kind < 2 ? 1 : 2
                let host = WinUIRenderer.running(clock: clock) {
                    let content = ForEach(rows.wrappedValue) { number in
                        ResizingLazyRow(number: number, varies: number < perRun,
                                        horizontal: horizontal, extent: extent.projectedValue)
                    }
                    return ScrollView(horizontal ? .horizontal : .vertical) {
                        Group {
                            if kind == 0 { LazyVStack(spacing: 0) { content } }
                            else if kind == 1 { LazyHStack(spacing: 0) { content } }
                            else if kind == 2 {
                                LazyVGrid(columns: [GridItem(.fixed(40)), GridItem(.fixed(40))], spacing: 0) { content }
                            } else {
                                LazyHGrid(rows: [GridItem(.fixed(40)), GridItem(.fixed(40))], spacing: 0) { content }
                            }
                        }
                        .animation(.eased(200, .linear))
                    }
                    .frame(width: 240, height: 240)
                }
                for _ in 0..<8 {
                    host.step()
                    host.frame()
                }
                let lazy = try XCTUnwrap(host.views(WinUILazyView.self).first)
                let identity = lazy.cells.identities[perRun * 2]
                let retained = try XCTUnwrap(lazy.mounted[identity]?.view)
                for operation in 0..<5 {
                    let before = horizontal ? retained.placedFrame.x : retained.placedFrame.y
                    let began = clock.now
                    let leaving = lazy.mounted[lazy.cells.identities[perRun]]?.view
                    if operation == 0 { rows.wrappedValue.removeSubrange(perRun..<perRun * 2) }
                    else if operation == 1 { rows.wrappedValue.insert(contentsOf: 100..<100 + perRun, at: perRun) }
                    else if operation == 2 { rows.wrappedValue.swapAt(perRun * 2, perRun * 3) }
                    else if operation == 3 { extent.wrappedValue = 80 }
                    else { extent.wrappedValue = 40 }
                    for _ in 0..<8 {
                        host.step()
                        host.frame()
                    }
                    let joining = operation == 1 ? lazy.mounted[lazy.cells.identities[perRun]]?.view : nil
                    if operation == 0 { XCTAssertEqual(try XCTUnwrap(leaving).drawnOpacity, 1, accuracy: 0.01) }
                    if let joining { XCTAssertEqual(joining.drawnOpacity, 0, accuracy: 0.01) }
                    let target = before + (operation == 0 || operation == 4 ? -40 : 40)
                    XCTAssertEqual(horizontal ? retained.placedFrame.x : retained.placedFrame.y, before, accuracy: 1,
                                   "kind \(kind), operation \(operation) must start at the old position")
                    clock.now = began + 100
                    for _ in 0..<8 {
                        host.step()
                        host.frame()
                    }
                    XCTAssertEqual(horizontal ? retained.placedFrame.x : retained.placedFrame.y, (before + target) / 2, accuracy: 1,
                                   "kind \(kind), operation \(operation) must pass through the midpoint")
                    if operation == 0 { XCTAssertEqual(try XCTUnwrap(leaving).drawnOpacity, 0.5, accuracy: 0.01) }
                    if let joining { XCTAssertEqual(joining.drawnOpacity, 0.5, accuracy: 0.01) }
                    clock.now = began + 200
                    for _ in 0..<8 {
                        host.step()
                        host.frame()
                    }
                    XCTAssertEqual(horizontal ? retained.placedFrame.x : retained.placedFrame.y, target, accuracy: 1)
                    XCTAssertTrue(lazy.mounted[identity]?.view === retained)
                    if let joining { XCTAssertEqual(joining.drawnOpacity, 1, accuracy: 0.01) }
                }
                let scroll = try XCTUnwrap(host.views(WinUIScrollView.self).first)
                scroll.scroller.move(to: Point(horizontal ? 480 : 0, horizontal ? 0 : 480))
                for _ in 0..<8 {
                    host.step()
                    host.frame()
                }
                XCTAssertFalse(host.runtime.animator.isMoving, "scrolling must not start data transitions")
                for item in lazy.mounted.values { XCTAssertEqual(item.view.drawnOpacity, 1, accuracy: 0.01) }

            }
        }
    }


    func testDeletingDataAnimatesRetainedRowsAfterTheMeasureWindowChanges() throws {
        try onUIThread {
            let clock = TestClock()
            let rows = State(wrappedValue: Array(0..<1_000))
            let standing = State(wrappedValue: 0)
            let host = WinUIRenderer.running(clock: clock) {
                VStack {
                    Text("\(standing.wrappedValue) standing")
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(rows.wrappedValue) { row in
                                HStack {
                                    Text("Row \(row)")
                                    Button("Delete \(row)") { rows.wrappedValue.removeAll { $0 == row } }
                                }
                                .frame(height: 48)
                                .animation(.inherited)
                                .onAppear { standing.wrappedValue += 1 }
                                .onDisappear { standing.wrappedValue -= 1 }
                            }
                        }
                        .animation(.eased(200, .linear))
                    }
                    .frame(width: 480, height: 300)
                }
            }
            for _ in 0..<20 { host.step() }
            let label = try XCTUnwrap(host.views(WinUILabelView.self).first { $0.text == "Row 2" })
            let lazy = try XCTUnwrap(host.views(WinUILazyView.self).first)
            let row = try XCTUnwrap(lazy.mounted.values.first { item in
                var ancestor = label.placingLayout
                while let layout = ancestor {
                    if layout === item.view { return true }
                    ancestor = layout.placingLayout
                }
                return false
            }?.view)
            let before = row.laidOutFrame.y
            try XCTUnwrap(host.views(WinUIButtonView.self).first { $0.text == "Delete 1" }).invoke()
            for _ in 0..<8 { host.step() }
            XCTAssertTrue(host.views(WinUILabelView.self).first { $0.text == "Row 2" } === label)
            XCTAssertEqual(row.laidOutFrame.y, before, accuracy: 1,
                           "Measure may realize the changed window but must not discard the data animation")
            clock.now = 100
            host.frame()
            XCTAssertEqual(row.laidOutFrame.y, before - 28, accuracy: 1,
                           "the surviving row moves halfway through its 56-point gap")
            XCTAssertEqual(row.drawnOpacity, 1)
            XCTAssertEqual(label.drawnOpacity, 1)
            clock.now = 200
            host.frame()
            XCTAssertEqual(row.laidOutFrame.y, before - 56, accuracy: 1)
            let scroll = try XCTUnwrap(host.views(WinUIScrollView.self).first)
            for offset in [560.0, 1_120, 280] {
                scroll.scroller.move(to: Point(0, offset))
                for _ in 0..<8 { host.step() }
                XCTAssertFalse(host.runtime.animator.isMoving, "scroll realization never starts an animation")
                for label in host.views(WinUILabelView.self) { XCTAssertEqual(label.drawnOpacity, 1) }
            }
        }
    }

    func testGalleryTilesReachTheLastItemWithoutReopeningThePage() throws {
        try onUIThread {
            let standing = State(wrappedValue: 0)
            let host = WinUIRenderer.running {
                VStack {
                    Text("\(standing.wrappedValue) standing of 200")
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 12) {
                            ForEach(1...200) { tile in
                                Text("Tile \(tile)")
                                    .font(.system(size: 14))
                                    .frame(width: 140, height: 160)
                                    .onAppear { standing.wrappedValue += 1 }
                                    .onDisappear { standing.wrappedValue -= 1 }
                            }
                        }
                    }
                    .frame(height: 200)
                }
                .spacing(10)
                .frame(width: 480)
            }
            for _ in 0..<20 { host.step() }
            let scroll = try XCTUnwrap(host.views(WinUIScrollView.self).first)
            let lazy = try XCTUnwrap(host.views(WinUILazyStackView.self).first)
            let total = 200.0 * 140 + 199 * 12
            XCTAssertEqual(lazy.cells.total, total, accuracy: 1)
            XCTAssertEqual(scroll.scroller.standing.reach.x + scroll.scroller.laidOutFrame.width,
                           total, accuracy: 1, "the native document must replace the initial 44-point estimate")
            scroll.scroller.move(to: scroll.scroller.standing.reach)
            for _ in 0..<20 { host.step() }
            let identity = try XCTUnwrap(lazy.cells.identities.last)
            let last = try XCTUnwrap(lazy.mounted[identity]?.view)
            XCTAssertEqual(last.laidOutFrame.width, 140, accuracy: 1)
            XCTAssertEqual(last.origin.x + last.laidOutFrame.width,
                           scroll.scroller.origin.x + scroll.scroller.laidOutFrame.width, accuracy: 1)
        }
    }

    func testGalleryAdaptiveGridAndShelvesGetTheirViewportWidthOnFirstPresentation() throws {
        try onUIThread {
            for shelves in [false, true] {
                let standing = State(wrappedValue: 0)
                let host = WinUIRenderer.running(room: LayoutSize(width: 1_000, height: 800)) {
                    GeometryReader { proxy in
                        Grid {
                            Text("Lazy stacks and grids")
                            ZStack {
                                Grid {
                                    VStack {
                                        Text("\(standing.wrappedValue) standing")
                                        ScrollView {
                                            if shelves {
                                                LazyVStack(spacing: 18) {
                                                    ForEach(0..<24) { shelf in
                                                        VStack {
                                                            Text("Shelf \(shelf)").horizontalAlignment(.start)
                                                            ScrollView(.horizontal) {
                                                                LazyHStack(spacing: 8) {
                                                                    ForEach(0..<40) { tile in
                                                                        Text("\(shelf).\(tile)")
                                                                            .frame(width: 96, height: 72)
                                                                            .onAppear { standing.wrappedValue += 1 }
                                                                            .onDisappear { standing.wrappedValue -= 1 }
                                                                    }
                                                                }
                                                            }
                                                            .frame(height: 88)
                                                        }
                                                    }
                                                }
                                            } else {
                                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                                                    ForEach(0..<500) { cell in
                                                        Text("Cell \(cell)")
                                                            .frame(height: 64)
                                                            .frame(maxWidth: .infinity)
                                                            .onAppear { standing.wrappedValue += 1 }
                                                            .onDisappear { standing.wrappedValue -= 1 }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    .spacing(10)
                                }
                                .contentPadding(16)
                            }
                            .gridRow(1)
                        }
                        .rows(.auto, .fill)
                        .rowSpacing(16)
                        .contentPadding(24)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                }
                for turn in 0..<20 {
                    let scrolls = host.views(WinUIScrollView.self)
                    let outer = try XCTUnwrap(scrolls.first)
                    let width = outer.scroller.laidOutFrame.width
                    XCTAssertGreaterThan(width, 800)
                    if shelves {
                        for scroll in scrolls.dropFirst() {
                            XCTAssertEqual(scroll.scroller.laidOutFrame.width, width, accuracy: 1,
                                           "turn \(turn): a shelf inherits the vertical viewport's width")
                            if scroll.scroller.origin.y < outer.scroller.origin.y + outer.scroller.laidOutFrame.height,
                               scroll.scroller.origin.y + scroll.scroller.laidOutFrame.height > outer.scroller.origin.y {
                                XCTAssertEqual(scroll.scroller.standing.reach.x + scroll.scroller.laidOutFrame.width,
                                               40 * 96 + 39 * 8, accuracy: 1)
                            }
                        }
                        XCTAssertGreaterThan(scrolls.count, 2)
                    } else {
                        let grid = try XCTUnwrap(host.views(WinUILazyGridView.self).first)
                        let tracks = Int((width + 10) / 106)
                        XCTAssertEqual(grid.cells.window?.perRun, tracks, "turn \(turn)")
                        XCTAssertGreaterThan(grid.mounted.count, tracks)
                        for item in grid.mounted.values {
                            XCTAssertGreaterThanOrEqual(item.view.laidOutFrame.width, 96,
                                                       "turn \(turn): cells must not collapse to their text width")
                        }
                    }
                    host.step()
                }
            }
        }
    }

    func testNewCompositeRowsAreMeasuredBeforeTheyAreArranged() throws {
        try onUIThread {
            let host = WinUIRenderer.running { LazyRowsPage() }
            let lazy = try XCTUnwrap(host.views(WinUILazyStackView.self).first)
            let identity = try XCTUnwrap(lazy.cells.identities.first)
            let label = WinUILabelView()
            label.setText("Row 0")
            label.setTextFont(size: 14, attributes: nil, family: nil)
            let button = WinUIButtonView()
            button.setText("Delete")
            button.setFont(size: 12, attributes: nil, family: nil)
            button.setPadding(EdgeInsets(10, 4))
            let row = WinUIGridView()
            row.columns = [.fill, .auto]
            row.padding = EdgeInsets(14, 4)
            var words = WinUILayoutItem(view: label)
            words.values.vertical = 1
            var action = WinUILayoutItem(view: button)
            action.values.column = 1
            row.setItems([words, action])
            lazy.setItems([(identity, WinUILayoutItem(view: row))])

            XCTAssertEqual(label.desiredSize, .zero)
            _ = lazy.measure(width: 480.0, height: 240.0)
            XCTAssertGreaterThan(label.desiredSize.width, 20, "Measure must reach the row's Text before Arrange")
            XCTAssertGreaterThan(label.desiredSize.height, 10)
            XCTAssertGreaterThan(button.desiredSize.width, 20)
            lazy.arrange(width: 480, height: 240)
            XCTAssertGreaterThan(lazy.measured[identity]?.size.height ?? 0, 20)
        }
    }

    func testExactWindowsReachIdentityAndIdleInEveryDirection() throws {
        try onUIThread {
            for kind in 0..<4 {
                let host = WinUIRenderer.running { ExactLazyPage(kind: kind) }
                for _ in 0..<30 { host.step() }
                let scroll = try XCTUnwrap(host.views(WinUIScrollView.self).first)
                let lazy = try XCTUnwrap(host.views(WinUILazyView.self).first)
                let horizontal = kind % 2 == 1
                let perRun = kind < 2 ? 1 : 4
                let extent = horizontal ? 80.0 : 40.0
                let viewport = horizontal ? scroll.frame.width : scroll.frame.height
                let reach = scroll.scroller.standing.reach
                XCTAssertEqual(viewport, horizontal ? 480 : 240, accuracy: 1)
                XCTAssertEqual(horizontal ? reach.x : reach.y,
                               1_000 / Double(perRun) * extent - viewport, accuracy: 1)
                var previous: [String: WinUIView] = [:]
                for offset in [0.0, extent * 20, extent * 21, extent * 21 + 1,
                               extent * 20, extent * 150, extent * 5, 0] {
                    scroll.scroller.move(to: Point(horizontal ? offset : 0, horizontal ? 0 : offset))
                    for _ in 0..<6 { host.step() }
                    let span = try XCTUnwrap(lazy.span)
                    let first = Int((span.lowerBound / extent).rounded(.down))
                    let last = Int((span.upperBound / extent).rounded(.up))
                    let margin = Int(viewport / extent)
                    let expected = max(0, first - 1 - margin) * perRun..<min(1_000, (last + 1 + margin) * perRun)
                    XCTAssertEqual(lazy.cells.built, expected, "kind \(kind), offset \(offset)")
                    XCTAssertEqual(lazy.mounted.count, expected.count)
                    for (identity, item) in lazy.mounted {
                        if let kept = previous[identity] { XCTAssertTrue(kept === item.view) }
                        XCTAssertGreaterThan(item.view.frame.width, 0)
                        XCTAssertGreaterThan(item.view.frame.height, 0)
                    }
                    previous = lazy.mounted.mapValues(\.view)
                }
                let work = [lazy.cells.searches, lazy.cells.requests, lazy.cells.measurements]
                for _ in 0..<200 { host.step() }
                XCTAssertEqual([lazy.cells.searches, lazy.cells.requests, lazy.cells.measurements], work,
                               "stationary kind \(kind) must not recalculate")
            }
        }
    }

    func testComposedViewportsKeepExactWindowsAndPaintIncomingCells() throws {
        try onUIThread {
            for (count, complex) in [(1_000, false), (10_000, false), (1_000, true)] {
                for kind in 0..<4 {
                    let host = WinUIRenderer.running { ExactLazyPage(kind: kind, count: count, complex: complex) }
                    for _ in 0..<12 { host.step() }
                    let scroll = try XCTUnwrap(host.views(WinUIScrollView.self).first)
                    let lazy = try XCTUnwrap(host.views(WinUILazyView.self).first)
                    let horizontal = kind % 2 == 1
                    let perRun = kind < 2 ? 1 : 4
                    let extent = horizontal ? 80.0 : 40.0
                    var previous: [String: WinUIView] = [:]
                    var animatedPhases: Set<Int> = []
                    var phaseStarts: [Double] = []
                    var animatedMove: (phase: Int, from: Double, to: Double)?
                    let animationEar = WinUIScrollEar(owner: host) { [weak scroller = scroll.scroller, weak lazy] in
                        guard let scroller, let lazy, let move = animatedMove else { return }
                        var displayed = [Double](repeating: 0, count: 6)
                        swiftomniui_winui_scroller_viewport(scroller.handle, lazy.handle, &displayed)
                        let along = -displayed[horizontal ? 4 : 5]
                        if abs(along - move.from) > 1, abs(along - move.to) > 1 {
                            animatedPhases.insert(move.phase)
                        }
                    }
                    scroll.scroller.ears.append(animationEar)
                    defer { animationEar.owner = nil }
                    let window = try XCTUnwrap(host.window)
                    let title = "SOUILazyPixels-\(count)-\(complex)-\(kind)"
                    window.setTitle(title)
                    let name = Array(title.utf16) + [0]
                    let hwnd = try XCTUnwrap(name.withUnsafeBufferPointer { FindWindowW(nil, $0.baseAddress) })
                    _ = SetForegroundWindow(hwnd)
                    XCTAssertTrue(SetWindowPos(hwnd, HWND(bitPattern: -1), 0, 0, 0, 0, UINT(SWP_NOMOVE | SWP_NOSIZE)))
                    defer { _ = SetWindowPos(hwnd, HWND(bitPattern: -2), 0, 0, 0, 0, UINT(SWP_NOMOVE | SWP_NOSIZE)) }
                    let initial = try XCTUnwrap(lazy.mounted[lazy.cells.identities[0]])
                    let frame = scroll.scroller.laidOutFrame
                    let cross = horizontal
                        ? initial.view.origin.y - scroll.scroller.origin.y + 1
                        : initial.view.origin.x - scroll.scroller.origin.x + initial.view.laidOutFrame.width - 3
                    let origin = scroll.scroller.origin
                    var corner = POINT()
                    XCTAssertTrue(ClientToScreen(hwnd, &corner))
                    let scale = Double(GetDpiForWindow(hwnd)) / 96
                    let points = [3.0, (horizontal ? frame.width : frame.height) - 3].map { along in
                        let sample = horizontal ? (along, cross) : (cross, along)
                        return POINT(x: corner.x + LONG((origin.x + sample.0) * scale),
                                     y: corner.y + LONG((origin.y + sample.1) * scale))
                    }
                    let probe = WinUILazyScreenProbe(window: hwnd, points: points)
                    let rawProbe = Unmanaged.passRetained(probe).toOpaque()
                    let created = CreateThread(nil, 0, WinUILazyScreenProbe.entry, rawProbe, 0, nil)
                    if created == nil { Unmanaged<WinUILazyScreenProbe>.fromOpaque(rawProbe).release() }
                    let thread = try XCTUnwrap(created)
                    defer {
                        probe.lock.lock()
                        probe.stopped = true
                        probe.lock.unlock()
                        _ = WaitForSingleObject(thread, 2_000)
                        _ = CloseHandle(thread)
                    }
                    for step in 0..<192 {
                        if step < 36 {
                            let run = step < 12 ? step * 3 : step < 24 ? (36 - step) * 3 : (step - 24) * 11
                            let offset = Double(run) * extent + (step.isMultiple(of: 2) ? 1 : 0)
                            scroll.scroller.move(to: Point(horizontal ? offset : 0, horizontal ? 0 : offset))
                        } else if step < 180, (step - 36).isMultiple(of: 48) {
                            let phase = (step - 36) / 48
                            let offset = [800.0, 4_000.0, 0][phase]
                            var displayed = [Double](repeating: 0, count: 6)
                            swiftomniui_winui_scroller_viewport(scroll.scroller.handle, lazy.handle, &displayed)
                            animatedMove = (phase, -displayed[horizontal ? 4 : 5], offset)
                            phaseStarts.append(WinUIFrameClock.monotonic())
                            swiftomniui_winui_scroller_move(scroll.scroller.handle,
                                                       horizontal ? offset : 0, horizontal ? 0 : offset, true)
                        }
                        if step == 180 { phaseStarts.append(WinUIFrameClock.monotonic()) }
                        host.step()
                        if step < 36 {
                            // Complete direct jumps; native animations below keep their normal layout schedule.
                            host.layOut()
                            let span = try XCTUnwrap(lazy.span)
                            let first = Int((span.lowerBound / extent).rounded(.down))
                            let last = Int((span.upperBound / extent).rounded(.up))
                            let margin = Int((horizontal ? frame.width : frame.height) / extent)
                            let expected = max(0, first - 1 - margin) * perRun..<min(count, (last + 1 + margin) * perRun)
                            XCTAssertEqual(lazy.cells.built, expected, "kind \(kind), step \(step)")
                            XCTAssertEqual(lazy.mounted.count, expected.count)
                        }
                        for (identity, item) in lazy.mounted {
                            XCTAssertGreaterThan(item.view.laidOutFrame.width, 0)
                            XCTAssertGreaterThan(item.view.laidOutFrame.height, 0)
                            XCTAssertEqual(item.view.drawnOpacity, 1)
                            if let kept = previous[identity] { XCTAssertTrue(kept === item.view) }
                        }
                        previous = lazy.mounted.mapValues(\.view)
                    }
                    probe.lock.lock()
                    probe.stopped = true
                    probe.lock.unlock()
                    XCTAssertEqual(WaitForSingleObject(thread, 2_000), 0, "the pixel sampler must finish")
                    probe.lock.lock()
                    let samples = probe.samples
                    probe.lock.unlock()
                    XCTAssertGreaterThan(samples.count, 0, "the displayed test window must be sampled")
                    for edge in 0..<2 {
                        XCTAssertGreaterThan(samples.filter { $0.edge == edge }.count, 0,
                                             "both displayed viewport edges must be sampled")
                    }
                    XCTAssertEqual(phaseStarts.count, 4)
                    for (phase, interval) in zip(phaseStarts, phaseStarts.dropFirst()).enumerated() {
                        for edge in 0..<2 {
                            let captured = samples.filter {
                                $0.edge == edge && $0.time >= interval.0 && $0.time < interval.1
                            }
                            XCTAssertGreaterThan(captured.count, 1, "phase \(phase), edge \(edge) must be sampled")
                        }
                    }
                    for sample in samples {
                        let diagnostic = "screen=\(String(sample.pixel, radix: 16)) time=\(sample.time) count=\(count) kind=\(kind) complex=\(complex) leading=\(sample.edge == 0)"
                        XCTAssertGreaterThan(sample.pixel & 255, 160, "incoming cell was not painted: \(diagnostic)")
                        XCTAssertLessThan((sample.pixel >> 8) & 255, 100, "scrolling exposed a white gap: \(diagnostic)")
                    }
                    XCTAssertEqual(animatedPhases, [0, 1, 2],
                                   "each native animation must display a position between its start and destination")
                    for _ in 0..<12 { host.step() }
                    let work = [lazy.cells.searches, lazy.cells.requests, lazy.cells.measurements]
                    for _ in 0..<200 { host.step() }
                    XCTAssertEqual([lazy.cells.searches, lazy.cells.requests, lazy.cells.measurements], work)
                }
            }
        }
    }

    func testAnimatedNativeOffsetsKeepCorrectRowsReachable() throws {
        try onUIThread {
            for kind in 0..<4 {
                let horizontal = kind % 2 == 1
                let perRun = kind < 2 ? 1 : 4
                let extent = horizontal ? 80.0 : 40.0
                let host = WinUIRenderer.running {
                    let buttons = ForEach(0..<1_000) { row in
                        Grid {
                            Text("").frame(width: 16, height: 40)
                                .background(Color(red: 40 + row % 16 * 12,
                                                  green: 40 + row / 16 % 16 * 12,
                                                  blue: 40 + row / 256 % 16 * 12))
                            Button("Row \(row)", action: {}).frame(width: 64, height: 40).gridColumn(1)
                        }
                        .columns(.fixed(16), .fixed(64))
                        .columnSpacing(0)
                        .frame(width: 80, height: 40)
                        .background(Color(red: 40 + row % 16 * 12,
                                          green: 40 + row / 16 % 16 * 12,
                                          blue: 40 + row / 256 % 16 * 12))
                    }
                    return ScrollView(horizontal ? .horizontal : .vertical) {
                        if kind == 0 {
                            LazyVStack(spacing: 0) { buttons }
                        } else if kind == 1 {
                            LazyHStack(spacing: 0) { buttons }
                        } else if kind == 2 {
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(80)), count: 4), spacing: 0) {
                                buttons
                            }
                        } else {
                            LazyHGrid(rows: Array(repeating: GridItem(.fixed(40)), count: 4), spacing: 0) {
                                buttons
                            }
                        }
                    }
                    .frame(width: 480, height: 240)
                }
                for _ in 0..<12 { host.step() }
                let scroll = try XCTUnwrap(host.views(WinUIScrollView.self).first)
                let lazy = try XCTUnwrap(host.views(WinUILazyView.self).first)
                let title = "SOUILazyNativeOffsets-\(kind)"
                try XCTUnwrap(host.window).setTitle(title)
                let name = Array(title.utf16) + [0]
                let hwnd = try XCTUnwrap(name.withUnsafeBufferPointer { FindWindowW(nil, $0.baseAddress) })
                _ = SetForegroundWindow(hwnd)
                XCTAssertTrue(SetWindowPos(hwnd, HWND(bitPattern: -1), 0, 0, 0, 0, UINT(SWP_NOMOVE | SWP_NOSIZE)))
                defer { _ = SetWindowPos(hwnd, HWND(bitPattern: -2), 0, 0, 0, 0, UINT(SWP_NOMOVE | SWP_NOSIZE)) }
                var previousOffset = horizontal ? scroll.scroller.standing.offset.x : scroll.scroller.standing.offset.y
                let first = try XCTUnwrap(lazy.mounted[lazy.cells.identities[0]]?.view)
                let sampleX = horizontal ? scroll.scroller.origin.x + 240 : first.origin.x + 8
                let sampleY = horizontal ? first.origin.y + 1 : scroll.scroller.origin.y + 120
                let sampleScale = Double(GetDpiForWindow(hwnd)) / 96
                var screenPoint = POINT(x: LONG(sampleX * sampleScale), y: LONG(sampleY * sampleScale))
                XCTAssertTrue(ClientToScreen(hwnd, &screenPoint))
                for target in [801.0, 4_001.0, 241.0, 0.0] {
                    let forward = target > previousOffset
                    let probe = WinUILazyScreenProbe(window: hwnd, points: [screenPoint])
                    let raw = Unmanaged.passRetained(probe).toOpaque()
                    let created = CreateThread(nil, 0, WinUILazyScreenProbe.entry, raw, 0, nil)
                    if created == nil { Unmanaged<WinUILazyScreenProbe>.fromOpaque(raw).release() }
                    let thread = try XCTUnwrap(created)
                    defer {
                        probe.lock.lock()
                        probe.stopped = true
                        probe.lock.unlock()
                        _ = WaitForSingleObject(thread, 2_000)
                        _ = CloseHandle(thread)
                    }
                    swiftomniui_winui_scroller_move(scroll.scroller.handle,
                                                   horizontal ? target : 0, horizontal ? 0 : target, true)
                    // The animation runs on the compositor's clock, not the test's steps: follow it until it lands.
                    for _ in 0..<400 {
                        host.step()
                        let offset = horizontal ? scroll.scroller.standing.offset.x : scroll.scroller.standing.offset.y
                        XCTAssertGreaterThanOrEqual((offset - previousOffset) * (forward ? 1 : -1), -1,
                                                    "native scrolling must not jump backwards, kind \(kind)")
                        previousOffset = offset
                        if abs(offset - target) < 0.5, !scroll.held { break }
                    }
                    probe.lock.lock()
                    let pixels = probe.samples.map(\.pixel)
                    probe.lock.unlock()
                    XCTAssertGreaterThan(Set(pixels).count, 3,
                                         "native scrolling must paint intermediate rows: kind \(kind), target \(target), samples \(pixels.count)")
                    XCTAssertFalse(pixels.contains(0x00FFFFFF),
                                   "native animation exposed an unpainted row: kind \(kind), target \(target)")
                    var native = [0.0, 0.0, 0.0, 0.0]
                    swiftomniui_winui_scroller_offset(scroll.scroller.handle, &native)
                    let offset = native[horizontal ? 0 : 1]
                    XCTAssertEqual(offset, target, accuracy: 1, "kind \(kind)")
                    var viewport = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
                    swiftomniui_winui_scroller_viewport(scroll.scroller.handle, lazy.handle, &viewport)
                    let room = viewport[horizontal ? 2 : 3]
                    let run = Int(((offset + room / 2) / extent).rounded(.down))
                    let row = run * perRun
                    let identity = lazy.cells.identities[row]
                    let item = try XCTUnwrap(lazy.mounted[identity]?.view)
                    let button = try XCTUnwrap(host.views(WinUIButtonView.self).first { $0.text == "Row \(row)" })
                    let crossRoom = viewport[horizontal ? 3 : 2]
                    let crossExtent = horizontal ? 40.0 : 80.0
                    let cross = (crossRoom - Double(perRun) * crossExtent) / 2 + crossExtent / 2
                    let along = (Double(run) + 0.5) * extent - offset
                    let corner = scroll.scroller.origin
                    // The expected point uses only the native viewport, item geometry and scroller origin.
                    let expected = Point(x: corner.x + (horizontal ? along : cross),
                                         y: corner.y + (horizontal ? cross : along))
                    XCTAssertEqual(item.laidOutFrame.width, 80, accuracy: 1)
                    XCTAssertEqual(item.laidOutFrame.height, 40, accuracy: 1)
                    XCTAssertEqual(item.origin.x + 40, expected.x, accuracy: 1, "kind \(kind), offset \(offset)")
                    XCTAssertEqual(item.origin.y + 20, expected.y, accuracy: 1, "kind \(kind), offset \(offset)")
                    let actual = button.origin
                    XCTAssertGreaterThan(button.laidOutFrame.width, 0)
                    XCTAssertLessThanOrEqual(button.laidOutFrame.width, 64)
                    XCTAssertGreaterThan(button.laidOutFrame.height, 0)
                    XCTAssertLessThanOrEqual(button.laidOutFrame.height, 40)
                    XCTAssertEqual(actual.x + button.laidOutFrame.width / 2, expected.x + 8, accuracy: 1,
                                   "kind \(kind), offset \(offset)")
                    XCTAssertEqual(actual.y + button.laidOutFrame.height / 2, expected.y, accuracy: 1,
                                   "kind \(kind), offset \(offset)")
                    XCTAssertTrue(swiftomniui_winui_reaches(button.handle,
                                                         expected.x + 8 - actual.x, expected.y - actual.y),
                                  "the correct row must be reachable at its independent viewport point")
                    let dc = try XCTUnwrap(GetDC(nil))
                    defer { _ = ReleaseDC(nil, dc) }
                    let scale = Double(GetDpiForWindow(hwnd)) / 96
                    var point = POINT(x: LONG((expected.x - 32) * scale), y: LONG(expected.y * scale))
                    XCTAssertTrue(ClientToScreen(hwnd, &point))
                    let hit = try XCTUnwrap(WindowFromPoint(point))
                    XCTAssertEqual(GetAncestor(hit, UINT(GA_ROOT)), hwnd)
                    let pixel = GetPixel(dc, point.x, point.y)
                    XCTAssertNotEqual(pixel, 0xFFFFFFFF)
                    let channels = [40 + row % 16 * 12, 40 + row / 16 % 16 * 12, 40 + row / 256 % 16 * 12]
                    for channel in 0..<3 {
                        XCTAssertEqual(Double((pixel >> (channel * 8)) & 255), Double(channels[channel]), accuracy: 2,
                                       "the displayed strip must identify row \(row), kind \(kind), offset \(offset)")
                    }
                    let outsideIndex = offset > 0 ? lazy.cells.built.lowerBound : lazy.cells.built.upperBound - perRun
                    let outside = try XCTUnwrap(lazy.mounted[lazy.cells.identities[outsideIndex]])
                    XCTAssertFalse(swiftomniui_winui_reaches(outside.view.handle, 40, 20),
                                   "preloaded rows outside the native viewport must stay clipped")
                }
            }
        }
    }

    func testNaturalCompositeRowsScrollDeleteAndChangeHeightWithoutBlankChildren() throws {
        try onUIThread {
            let rows = State(wrappedValue: Array(0..<1_000))
            let tall = State(wrappedValue: false)
            let standing = State(wrappedValue: 0)
            let host = WinUIRenderer.running(room: WinUITestHost.room) {
                GeometryReader { proxy in
                    Grid {
                        Text("LazyVStack, LazyHStack, LazyVGrid - children built where the window reaches, and let go where it leaves.")
                            .font(.system(size: 15))
                        ZStack {
                            Grid {
                                VStack {
                                    Text("\(standing.wrappedValue) standing")
                                    ScrollView {
                                        LazyVStack(spacing: 8) {
                                            Text("- the top -")
                                            ForEach(rows.wrappedValue) { row in
                                                Grid {
                                                    Text("Row \(row)" + (tall.wrappedValue && row.isMultiple(of: 3) ? "\nsecond line\nthird line" : ""))
                                                        .font(.system(size: 14))
                                                        .verticalAlignment(.center)
                                                    Button("Delete", action: { rows.wrappedValue.removeAll { $0 == row } })
                                                        .font(.system(size: 12))
                                                        .contentPadding(EdgeInsets(10, 4))
                                                        .bold()
                                                        .background(Color("#CF380D"))
                                                        .foregroundStyle(.white)
                                                        .frame(minWidth: 44, minHeight: 44)
                                                        .gridColumn(1)
                                                }
                                                .columns(.fill, .auto)
                                                .contentPadding(EdgeInsets(14, 4))
                                                .animation(.inherited)
                                                .onAppear { standing.wrappedValue += 1 }
                                                .onDisappear { standing.wrappedValue -= 1 }
                                            }
                                            Text("- the end -")
                                        }
                                    }
                                }
                                .spacing(10)
                            }
                            .contentPadding(16)
                        }
                        .clipsContent(true)
                        .gridRow(1)
                    }
                    .rows(.auto, .fill)
                    .rowSpacing(16)
                    .contentPadding(24)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .horizontalAlignment(.start)
                    .verticalAlignment(.start)
                }
            }
            let scroll = try XCTUnwrap(host.views(WinUIScrollView.self).first)
            let lazy = try XCTUnwrap(host.views(WinUILazyStackView.self).first)
            for _ in 0..<12 { host.step() }
            let probe = WinUILabelView()
            probe.setTextFont(size: 14, attributes: nil, family: nil)
            for phase in 0..<3 {
                if phase == 1 {
                    withAnimation(nil) {
                        rows.wrappedValue.removeFirst(40)
                        tall.wrappedValue = true
                    }
                } else if phase == 2 {
                    withAnimation(nil) { tall.wrappedValue = false }
                }
                for _ in 0..<12 { host.step() }
                for step in 0..<30 {
                    let offset = step < 24 ? Double(step < 12 ? step * 120 : (24 - step) * 120)
                        : scroll.scroller.standing.reach.y
                    scroll.scroller.move(to: Point(0, offset))
                    host.step()
                    host.layOut()
                    let words = host.views(WinUILabelView.self).filter { $0.text.hasPrefix("Row ") }
                    let buttons = host.views(WinUIButtonView.self)
                    XCTAssertFalse(words.isEmpty, "phase \(phase), step \(step): nonempty data cannot render white")
                    XCTAssertEqual(words.count, buttons.count)
                    for word in words {
                        XCTAssertGreaterThan(word.laidOutFrame.width, 20)
                        XCTAssertGreaterThan(word.laidOutFrame.height, 10)
                        XCTAssertEqual(word.drawnOpacity, 1)
                        if let row = word.placingLayout as? WinUIGridView,
                           let button = row.items.first(where: { $0.view is WinUIButtonView })?.view {
                            let textFrame = word.laidOutFrame, buttonFrame = button.laidOutFrame
                            XCTAssertEqual(textFrame.y + textFrame.height / 2,
                                           buttonFrame.y + buttonFrame.height / 2, accuracy: 1,
                                           "\(word.text): Text and Delete must have the same vertical centre; placed=\(String(describing: word.placed)), native=\(textFrame), desired=\(word.desiredSize), button=\(buttonFrame)")
                            probe.setText(word.text)
                            let natural = probe.measure(width: nil, height: nil)
                            XCTAssertEqual(textFrame.height, natural.height, accuracy: 1,
                                           "\(word.text): a row must not retain wrapped height from another proposal; placed=\(String(describing: word.placed)), native=\(textFrame), desired=\(word.desiredSize), natural=\(natural), grid=\(row.laidOutFrame), button=\(buttonFrame)")
                        }
                    }
                    for button in buttons {
                        XCTAssertGreaterThan(button.laidOutFrame.width, 20)
                        XCTAssertGreaterThan(button.laidOutFrame.height, 10)
                        XCTAssertEqual(button.drawnOpacity, 1)
                    }
                }
                for _ in 0..<30 { host.step() }
                if phase == 0 {
                    // Visit every row so total-length assertions compare known measurements, not a
                    // changing statistical estimate of rows the test has never displayed.
                    for offset in stride(from: 0.0, through: scroll.scroller.standing.reach.y, by: 200) {
                        scroll.scroller.move(to: Point(0, offset))
                        host.step()
                    }
                    scroll.scroller.move(to: scroll.scroller.standing.reach)
                    for _ in 0..<30 { host.step() }
                    // Deleting the last visible rows must shrink an already scrolled document too.
                    for _ in 0..<3 {
                        let previousTotal = lazy.cells.total
                        try XCTUnwrap(host.views(WinUIButtonView.self).last).invoke()
                        for _ in 0..<35 { host.step() }
                        XCTAssertEqual(previousTotal - lazy.cells.total, 60, accuracy: 5,
                                       "removing one row must retain the sizes of surviving identities")
                    }
                }
                let end = scroll.scroller.standing
                XCTAssertEqual(end.offset.y, end.reach.y, accuracy: 1, "deletion must not leave a stale end anchor")
                XCTAssertEqual(end.reach.y + scroll.scroller.laidOutFrame.height, lazy.cells.total, accuracy: 1,
                               "deletion and shrinking must resize the native document, not just the lazy children")
                let footer = try XCTUnwrap(host.views(WinUILabelView.self).first { $0.text == "- the end -" })
                XCTAssertEqual(footer.laidOutFrame.y + footer.laidOutFrame.height,
                               lazy.cells.total, accuracy: 1, "the actual last child must end at the document bottom")
                XCTAssertEqual(footer.origin.y + footer.laidOutFrame.height,
                               scroll.scroller.origin.y + scroll.scroller.laidOutFrame.height, accuracy: 1,
                               "the visible footer must meet the viewport bottom at the scroll limit")
                let work = [lazy.cells.searches, lazy.cells.requests, lazy.cells.measurements]
                for _ in 0..<200 { host.step() }
                XCTAssertEqual([lazy.cells.searches, lazy.cells.requests, lazy.cells.measurements], work)
            }
        }
    }

    /// Of a thousand rows a window's worth are built, and no more.
    func testOnlyTheWindowedRowsAreBuilt() throws {
        try onUIThread {
            let host = WinUIRenderer.running { LazyRowsPage() }
            host.settle { host.views(WinUILabelView.self).count > 4 }

            XCTAssertLessThan(host.views(WinUILabelView.self).count, 60, "a window's reach of a thousand rows")
        }
    }

    /// Scrolling asks the rows the window moved to be built, and lets the
    /// ones it left go.
    func testScrollingBuildsAheadAndLetsGoBehind() throws {
        try onUIThread {
            let host = WinUIRenderer.running { LazyRowsPage() }
            let scroll = try XCTUnwrap(host.views(WinUIScrollView.self).first)
            host.settle { host.views(WinUILabelView.self).contains { $0.text == "Row 0" } }

            scroll.scroller.move(to: Point(0, 20_000))
            host.settle { host.views(WinUILabelView.self).contains { $0.text == "Row 500" } }

            let standing = host.views(WinUILabelView.self).map(\.text)
            XCTAssertFalse(standing.contains("Row 0"), "the first row was let go")
            XCTAssertLessThan(standing.count, 150, "still a window's reach")
        }
    }

    /// The room is the run's whole length before most of its rows exist.
    func testTheScrollRoomIsTheWholeRunAtOnce() throws {
        try onUIThread {
            let host = WinUIRenderer.running { LazyRowsPage() }
            host.settle { host.views(WinUILabelView.self).count > 4 }

            // A thousand forty-point rows: the lazy view's height is their run.
            let lazy = try XCTUnwrap(host.views(WinUILazyStackView.self).first)
            XCTAssertEqual(lazy.laidOutFrame.height, 40_000, accuracy: 4_000)
        }
    }

    /// Outside a scroller there is no window to narrow by: every child is
    /// built, as a plain stack's would be.
    func testALazyStackWithNoScrollerBuildsAll() throws {
        try onUIThread {
            let host = WinUIRenderer.running { LazyRowsPage(count: 30, scrolls: false) }
            host.settle { host.views(WinUILabelView.self).count == 30 }

            XCTAssertEqual(host.views(WinUILabelView.self).count, 30)
        }
    }
}

/// Reads displayed pixels off the UI thread during scrolling and layout; polling does not cover every frame.
private final class WinUILazyScreenProbe: @unchecked Sendable {
    let lock = NSLock()
    let window: HWND
    let points: [POINT]
    var stopped = false
    var samples: [(time: Double, edge: Int, pixel: DWORD)] = []

    init(window: HWND, points: [POINT]) {
        self.window = window
        self.points = points
    }

    nonisolated static let entry: @convention(c) (UnsafeMutableRawPointer?) -> DWORD = { raw in
        guard let raw else { return 1 }
        let probe = Unmanaged<WinUILazyScreenProbe>.fromOpaque(raw).takeRetainedValue()
        guard let dc = GetDC(nil) else { return 1 }
        defer { _ = ReleaseDC(nil, dc) }
        while true {
            probe.lock.lock()
            let stopped = probe.stopped
            probe.lock.unlock()
            if stopped { return 0 }
            for (edge, point) in probe.points.enumerated() {
                guard let hit = WindowFromPoint(point),
                      GetAncestor(hit, UINT(GA_ROOT)) == probe.window else { continue }
                let pixel = GetPixel(dc, point.x, point.y)
                if pixel != 0xFFFFFFFF {
                    let time = WinUIFrameClock.monotonic()
                    probe.lock.lock()
                    probe.samples.append((time, edge, pixel))
                    probe.lock.unlock()
                }
            }
            Sleep(8)
        }
    }
}

/// A thousand forty-point rows in a scroller - or thirty, where it does not
/// scroll.
private struct LazyRowsPage: View {
    var count = 1_000
    var scrolls = true

    var body: some View {
        if scrolls {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(0..<count) { row in
                        Text("Row \(row)").frame(height: 40)
                    }
                }
            }
        } else {
            LazyVStack(spacing: 0) {
                ForEach(0..<count) { row in
                    Text("Row \(row)").frame(height: 40)
                }
            }
        }
    }
}

private struct ExactLazyPage: View {
    let kind: Int
    var count = 1_000
    var complex = false

    var body: some View {
        let overlay = VStack {
            HStack {
                Text("Left")
                Text("Right")
            }
            HStack {
                Text("Top")
                Text("Bottom")
            }
        }
        .font(.system(size: 8))
        .frame(width: 40, height: 20)
        return ScrollView(kind % 2 == 1 ? .horizontal : .vertical) {
            if kind == 0 {
                LazyVStack(spacing: 0) {
                    ForEach(0..<count) { number in
                        if complex {
                            Text("Row \(number)").frame(width: 80, height: 40).background(Color("#D03020"))
                                .overlay(overlay)
                                .frame(width: 80, height: 40)
                                .id("tile-\(number)")
                        } else {
                            Text("Row \(number)").frame(width: 80, height: 40).background(Color("#D03020"))
                        }
                    }
                }
            } else if kind == 1 {
                LazyHStack(spacing: 0) {
                    ForEach(0..<count) { number in
                        if complex {
                            Text("Row \(number)").frame(width: 80, height: 40).background(Color("#D03020"))
                                .overlay(overlay)
                                .frame(width: 80, height: 40)
                                .id("tile-\(number)")
                        } else {
                            Text("Row \(number)").frame(width: 80, height: 40).background(Color("#D03020"))
                        }
                    }
                }
            } else if kind == 2 {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(80)), count: 4), spacing: 0) {
                    ForEach(0..<count) { number in
                        if complex {
                            Text("Row \(number)").frame(width: 80, height: 40).background(Color("#D03020"))
                                .overlay(overlay)
                                .frame(width: 80, height: 40)
                                .id("tile-\(number)")
                        } else {
                            Text("Row \(number)").frame(width: 80, height: 40).background(Color("#D03020"))
                        }
                    }
                }
            } else {
                LazyHGrid(rows: Array(repeating: GridItem(.fixed(40)), count: 4), spacing: 0) {
                    ForEach(0..<count) { number in
                        if complex {
                            Text("Row \(number)").frame(width: 80, height: 40).background(Color("#D03020"))
                                .overlay(overlay)
                                .frame(width: 80, height: 40)
                                .id("tile-\(number)")
                        } else {
                            Text("Row \(number)").frame(width: 80, height: 40).background(Color("#D03020"))
                        }
                    }
                }
            }
        }
        .frame(width: 480, height: 240)
    }
}

/// Its own state read changes the child without rebuilding the lazy source.
private struct ResizingLazyRow: View {
    let number: Int
    let varies: Bool
    let horizontal: Bool
    @Binding var extent: Double

    var body: some View {
        Text("Row \(number)")
            .frame(width: horizontal && varies ? extent : 40,
                   height: !horizontal && varies ? extent : 40)
            .transition(.opacity)
            .animation(.eased(200, .linear))
    }
}
