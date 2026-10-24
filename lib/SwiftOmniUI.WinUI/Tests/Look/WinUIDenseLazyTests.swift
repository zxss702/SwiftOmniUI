// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import SwiftOmniUIConformance
import CSwiftOmniUIWinUI
import XCTest

@MainActor private final class DenseLazyBuilds {
    var rows: [Int: Int] = [:]
    var total: Int { rows.values.reduce(0, +) }
}

private struct DenseFileRow: View {
    let index: Int
    let names: Binding<Bool>

    var body: some View {
        HStack(alignment: .top, spacing: 3) {
            Spacer().frame(width: Double(index % 5) * 5)
            Image(systemName: index.isMultiple(of: 7) ? "\u{E70D}" : "\u{E76C}")
                .frame(width: 8, height: 12)
            Image(systemName: index.isMultiple(of: 7) ? "\u{E8B7}" : "\u{E8A5}")
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 0) {
                Text(index.isMultiple(of: 11) || names.wrappedValue && index.isMultiple(of: 3)
                     ? "Source_\(index)_a_very_long_file_name_中文文件_automatically_wraps_across_lines.swift"
                     : "File_\(index).swift")
                    .font(.system(size: 9))
                if index.isMultiple(of: 17) {
                    HStack(spacing: 2) {
                        Image(systemName: "\u{E823}").frame(width: 8, height: 9)
                        Text("modified · \(index) bytes").font(.system(size: 7))
                    }
                }
            }
            Spacer()
            Image(systemName: "\u{EA3A}").frame(width: 5, height: 8)
        }
    }
}

private struct DenseFilePage: View {
    let grid: Bool
    let builds: DenseLazyBuilds
    @Binding var rows: [Int]
    @Binding var longNames: Bool

    private func row(_ index: Int) -> some View {
        builds.rows[index, default: 0] += 1
        return DenseFileRow(index: index, names: $longNames).id("dense-\(index)")
    }

    var body: some View {
        ScrollView {
            if grid {
                LazyVGrid(columns: [GridItem(.fixed(280)), GridItem(.fixed(280))], spacing: 0) {
                    ForEach(rows) { row($0) }
                }
            } else {
                LazyVStack(spacing: 0) { ForEach(rows) { row($0) } }
            }
        }
        .frame(width: grid ? 570 : 280, height: 1_200)
    }
}

final class WinUIDenseLazyTests: XCTestCase {
    func testDenseSidebarFillsAndScrollsWithManySimultaneousRows() throws { try exercise(grid: false) }
    func testDenseFileGridFillsAndScrollsWithManySimultaneousRows() throws { try exercise(grid: true) }
    func testDenseFileGridFillsDuringContinuousFastScroll() throws { try exercise(grid: true, continuous: true) }

    private func exercise(grid: Bool, continuous: Bool = false) throws {
        try onUIThread {
            let rows = State(wrappedValue: Array(0..<3_000))
            let longNames = State(wrappedValue: false)
            let builds = DenseLazyBuilds()
            let opened = WinUIFrameClock.monotonic()
            let host = WinUIRenderer.running(reducesMotion: true, room: LayoutSize(width: 620, height: 1_300)) {
                DenseFilePage(grid: grid, builds: builds, rows: rows.projectedValue, longNames: longNames.projectedValue)
            }
            let lazy = try XCTUnwrap(host.views(WinUILazyView.self).first)
            let scroll = try XCTUnwrap(host.views(WinUIScrollView.self).first)
            @MainActor func ready() -> Bool {
                guard let span = lazy.span, lazy.hasMountedWindow(in: span) else { return false }
                return lazy.cells.requestedItemsAreCurrent && !lazy.needsRowMeasurements
                    && !lazy.cells.needsWindowUpdate && !scroll.held && !host.runtime.lazyPrefetch.isPending
            }
            @MainActor func assertPaintedLeaves() throws {
                // Verify native ink, not merely nonzero layout rectangles.
                // Select by type: row modifiers can own the public source id.
                let image = try XCTUnwrap(host.views(WinUIImageView.self).first)
                let text = try XCTUnwrap(host.views(WinUILabelView.self).first)
                let labels = host.views(WinUILabelView.self)
                let wrapped = try XCTUnwrap(labels.first { $0.text.hasPrefix("Source_") })
                let single = try XCTUnwrap(labels.first { $0.text.hasPrefix("File_") })
                XCTAssertGreaterThan(wrapped.desiredSize.height, single.desiredSize.height,
                                     "long file names must actually wrap in XAML, not just contain long strings")
                for leaf in [image as WinUIView, text as WinUIView] {
                    let room = leaf.laidOutFrame
                    let points = stride(from: 0.5, to: min(room.height, 30), by: 1).flatMap { y in
                        stride(from: 0.5, to: min(room.width, 60), by: 1).map { x in (x, y) }
                    }
                    XCTAssertFalse(points.isEmpty)
                    XCTAssertTrue(leaf.pixels(at: points).contains { $0 >> 24 != 0 },
                                  "a measured file row must contain actual native text/glyph ink")
                }
            }
            host.settle(until: ready)
            XCTAssertTrue(ready())
            let initial = WinUIFrameClock.monotonic() - opened
            XCTAssertEqual(lazy.preparationDuration, 0,
                           "cold first-screen construction is not one incoming scroll batch")
            let mounted = lazy.mounted.count
            XCTAssertGreaterThanOrEqual(mounted, 75, "this fixture must actually show a dense window")
            XCTAssertLessThan(mounted, 220)
            XCTAssertLessThan(builds.rows.count, 250, "first paint cannot construct the data source")
            XCTAssertTrue(lazy.hasMountedWindow(in: try XCTUnwrap(lazy.span)))
            XCTAssertGreaterThan(host.views(WinUIImageView.self).count, 200)
            try assertPaintedLeaves()

            var longest = 0.0, longestFrame = 0.0, maxGap = 0.0
            var slowestFrameDetail = ""
            var requestTrace: [String] = []
            let requestHook = lazy.cells.onRowsRequested
            lazy.cells.onRowsRequested = { [weak lazy] in
                requestHook?()
                guard let lazy else { return }
                requestTrace.append("\(lazy.cells.built)/\(lazy.expansionRuns)")
            }
            let frameWork = host.frameClock.onFrame
            host.frameClock.onFrame = { now in
                let start = WinUIFrameClock.monotonic()
                let before = lazy.cells.built
                let requests = lazy.cells.requests
                let traceStart = requestTrace.count
                let velocity = lazy.scrollVelocity
                let readiness = lazy.preparationDuration
                frameWork?(now)
                let elapsed = WinUIFrameClock.monotonic() - start
                if elapsed > longestFrame {
                    longestFrame = elapsed
                    slowestFrameDetail = "built \(before)->\(lazy.cells.built), requests \(requests)->\(lazy.cells.requests), velocity \(velocity)->\(lazy.scrollVelocity), readiness \(readiness)->\(lazy.preparationDuration), trace=\(requestTrace[traceStart...])"
                }
            }
            defer { host.frameClock.onFrame = frameWork }
            var peak = mounted
            let targets = continuous ? stride(from: 100.0, through: 1_200.0, by: 100.0).map { $0 }
                : [600.0, 1_800, 3_200, 1_200, 0]
            for target in targets {
                swiftomniui_winui_scroller_move(scroll.scroller.handle, 0, target, true)
                for _ in 0..<(continuous ? 2 : 24) {
                    let start = WinUIFrameClock.monotonic()
                    host.step()
                    longest = max(longest, WinUIFrameClock.monotonic() - start)
                    peak = max(peak, lazy.mounted.count)
                    if let span = lazy.span, !lazy.cells.built.isEmpty {
                        let last = grid ? (lazy.cells.built.upperBound - 1) / 2 : lazy.cells.built.upperBound - 1
                        let end = grid ? lazy.cells.runs.offset(of: last, count: (rows.wrappedValue.count + 1) / 2)
                            + lazy.cells.runs.extent(of: last)
                            : lazy.cells.offset(of: last) + lazy.cells.extents.extent(of: lazy.cells.orderedIdentities[last])
                        maxGap = max(maxGap, span.upperBound - end)
                    }
                }
            }
            host.settle(until: ready)
            XCTAssertTrue(ready())
            XCTAssertTrue(lazy.hasMountedWindow(in: try XCTUnwrap(lazy.span)))
            try assertPaintedLeaves()
            // step() pumps a queue containing multiple callbacks and frames;
            // its total duration is not the duration of one application frame.
            XCTAssertLessThan(longestFrame, 1_000, "a single display callback cannot burst-build for seconds")
            XCTAssertLessThanOrEqual(maxGap, 1, "coalesced demand must fill the viewport without a row-per-frame trail")
            XCTAssertLessThan(peak, 400, "a dense window cannot turn into the whole file tree")

            let report = "Dense file \(grid ? "grid" : "sidebar"): initial=\(initial)ms, mounted=\(mounted), peak=\(peak), slowest frame callback=\(longestFrame)ms [\(slowestFrameDetail)], longest message pump=\(longest)ms, largest uncovered geometry=\(maxGap)dip"
            print(report)
            if continuous { return }

            let existing = lazy.mounted.mapValues(\.view)
            let measurements = lazy.cells.measurements
            rows.wrappedValue.append(contentsOf: 3_000..<3_100)
            for _ in 0..<10 { host.step() }
            XCTAssertEqual(lazy.cells.measurements, measurements)
            for (identity, view) in existing { XCTAssertTrue(lazy.mounted[identity]?.view === view) }
            longNames.wrappedValue = true
            for _ in 0..<12 { host.step() }
            XCTAssertTrue(ready())
            XCTAssertTrue(lazy.hasMountedWindow(in: try XCTUnwrap(lazy.span)))
            rows.wrappedValue.removeFirst(23)
            for _ in 0..<12 { host.step() }
            XCTAssertTrue(ready())
            XCTAssertFalse(lazy.mounted.isEmpty)
            let idle = [lazy.cells.requests, lazy.cells.measurements, builds.total]
            for _ in 0..<8 { host.step() }
            XCTAssertEqual([lazy.cells.requests, lazy.cells.measurements, builds.total], idle)
        }
    }
}
