// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import SwiftOmniUIConformance
import CSwiftOmniUIWinUI
import XCTest

@MainActor private final class ComplexLazyBuilds {
    var counts: [Int: Int] = [:]
    var total: Int { counts.values.reduce(0, +) }
}

/// Natural heights, wrapped text and native symbol controls; no seeded geometry
/// or artificial sleeps stand in for the cost of constructing a row.
private struct ComplexLazyCard: View {
    let number: Int
    let width: Double
    @Binding var expanded: Int

    private var paragraph: String {
        String(repeating: "A nested card with automatically wrapped text and symbols. 中文内容也需要自动换行。 ",
               count: expanded == number ? 12 : 1 + number % 3)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill").frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Card \(number)").font(.system(size: 16))
                    Text("Nested content and metadata").font(.system(size: 11))
                }
                Spacer()
                Image(systemName: "ellipsis").frame(width: 18, height: 18)
            }
            Text(paragraph).font(.system(size: 13))
            ForEach(0..<(1 + number % 3)) { section in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "doc.text").frame(width: 18, height: 18)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Section \(section)").font(.system(size: 12))
                        HStack(spacing: 5) {
                            Image(systemName: "clock").frame(width: 14, height: 14)
                            Text("Updated recently").font(.system(size: 11))
                        }
                    }
                }
            }
            HStack(spacing: 7) {
                ForEach(0..<8) { badge in
                    Image(systemName: badge.isMultiple(of: 2) ? "star.fill" : "checkmark.circle")
                        .frame(width: 14, height: 14)
                }
            }
        }
        .padding(10)
        .frame(width: width)
        .background(Color("#E4EDF8"))
    }
}

private struct ComplexLazyPage: View {
    let kind: Int
    let builds: ComplexLazyBuilds
    @Binding var rows: [Int]
    @Binding var expanded: Int

    private func card(_ number: Int) -> some View {
        builds.counts[number, default: 0] += 1
        return ComplexLazyCard(number: number, width: kind == 0 ? 420 : 210, expanded: $expanded)
            .id("complex-\(number)")
    }

    var body: some View {
        ScrollView(kind == 1 || kind == 3 ? .horizontal : .vertical) {
            if kind == 0 {
                LazyVStack(spacing: 8) { ForEach(rows) { card($0) } }
            } else if kind == 1 {
                LazyHStack(alignment: .top, spacing: 8) { ForEach(rows) { card($0) } }
            } else if kind == 2 {
                LazyVGrid(columns: [GridItem(.fixed(210)), GridItem(.fixed(210))], spacing: 8) {
                    ForEach(rows) { card($0) }
                }
            } else {
                LazyHGrid(rows: [GridItem(.fixed(380))], spacing: 8) {
                    ForEach(rows) { card($0) }
                }
            }
        }
        .frame(width: 460, height: 380)
    }
}

final class WinUIComplexLazyTests: XCTestCase {
    func testNestedVStackSymbolsAndWrappedTextDuringScrollAndEdits() throws { try exercise(kind: 0) }
    func testNestedHStackSymbolsAndWrappedTextDuringScrollAndEdits() throws { try exercise(kind: 1) }
    func testNestedVGridSymbolsAndWrappedTextDuringScrollAndEdits() throws { try exercise(kind: 2) }
    func testNestedHGridSymbolsAndWrappedTextDuringScrollAndEdits() throws { try exercise(kind: 3) }

    private func exercise(kind: Int) throws {
        try onUIThread {
            let rows = State(wrappedValue: Array(0..<240))
            let expanded = State(wrappedValue: -1)
            let builds = ComplexLazyBuilds()
            let host = WinUIRenderer.running(reducesMotion: true) {
                ComplexLazyPage(kind: kind, builds: builds, rows: rows.projectedValue, expanded: expanded.projectedValue)
            }
            let lazy = try XCTUnwrap(host.views(WinUILazyView.self).first)
            let scroll = try XCTUnwrap(host.views(WinUIScrollView.self).first)
            let horizontal = kind == 1 || kind == 3
            let perRun = kind == 2 ? 2 : 1
            @MainActor func settled() -> Bool {
                lazy.cells.requestedItemsAreCurrent && !lazy.needsRowMeasurements
                    && !lazy.cells.needsWindowUpdate && !scroll.held && !host.runtime.lazyPrefetch.isPending
            }
            host.settle(until: settled)
            XCTAssertTrue(settled(), "initial natural geometry must converge")
            XCTAssertLessThan(builds.total, 20, "opening cannot instantiate a source of complex cards")
            XCTAssertGreaterThan(host.views(WinUIImageView.self).count, 12)

            var slowestStep = 0.0
            var peakMounted = 0
            // Native animated movement, a second target before completion, and
            // reversal exercise cold rows as well as previously measured rows.
            for target in [900.0, 2_200, 0] {
                swiftomniui_winui_scroller_move(scroll.scroller.handle, horizontal ? target : 0,
                                               horizontal ? 0 : target, true)
                for _ in 0..<28 {
                    let start = WinUIFrameClock.monotonic()
                    host.step()
                    slowestStep = max(slowestStep, WinUIFrameClock.monotonic() - start)
                    peakMounted = max(peakMounted, lazy.mounted.count)
                }
            }
            host.settle(until: settled)
            XCTAssertTrue(settled(), "scroll input must eventually release pending work")
            XCTAssertTrue(lazy.hasMountedWindow(in: try XCTUnwrap(lazy.span)))
            XCTAssertLessThan(slowestStep, 2_000, "one UI turn must not stall for seconds building the predicted window")
            XCTAssertLessThan(peakMounted, 40, "complex rows must remain windowed during movement")
            XCTAssertLessThan(builds.counts.count, rows.wrappedValue.count / 2)

            // A large prediction must not burst-build even rows whose old
            // geometry is known. Readiness must not force native measurement.
            let span = try XCTUnwrap(lazy.span)
            lazy.cells.show(span, perRun: perRun, grid: kind >= 2,
                            realize: span.lowerBound..<(span.upperBound + 3_000), prefetch: true, demand: span)
            host.runtime.pump.turn()
            let previous = lazy.cells.built, measured = lazy.cells.measurements
            host.runtime.lazyPrefetch.drain { host.runtime.pump.turn() }
            XCTAssertLessThanOrEqual(lazy.cells.built.count - previous.count, perRun)
            XCTAssertEqual(lazy.cells.measurements, measured, "optional readiness must not synchronously measure native rows")
            lazy.cells.cancelPrefetch()
            lazy.viewportReported(Rect(0, 0, 460, 380))
            host.settle(until: settled)

            // Appending outside the window must reuse every mounted subtree.
            let retained = lazy.mounted.mapValues(\.view)
            let builtBeforeAppend = builds.total
            let measuredBeforeAppend = lazy.cells.measurements
            rows.wrappedValue.append(contentsOf: 240..<260)
            for _ in 0..<12 { host.step() }
            XCTAssertTrue(settled())
            // A new source can evaluate its visible row descriptions again;
            // its native subtrees and geometry must survive that evaluation.
            XCTAssertLessThanOrEqual(builds.total - builtBeforeAppend, retained.count)
            XCTAssertEqual(lazy.cells.measurements, measuredBeforeAppend)
            for (identity, view) in retained { XCTAssertTrue(lazy.mounted[identity]?.view === view) }

            let number = try XCTUnwrap(rows.wrappedValue.first { host.view(id: .manual("complex-\($0)")) != nil })
            let card = try XCTUnwrap(host.view(id: .manual("complex-\(number)")))
            let compactHeight = card.laidOutFrame.height
            let paragraph = try XCTUnwrap(host.views(WinUILabelView.self).first { $0.text.hasPrefix("A nested card") })
            let compactTextHeight = paragraph.laidOutFrame.height
            expanded.wrappedValue = number
            for _ in 0..<12 { host.step() }
            XCTAssertGreaterThan(paragraph.laidOutFrame.height, compactTextHeight + 30,
                                 "a mounted child's wrapped text must update its natural height")
            // Horizontal scrollers constrain the cross-axis height to their
            // viewport/track; the text inside must still reflow naturally.
            if !horizontal { XCTAssertGreaterThan(card.laidOutFrame.height, compactHeight + 30) }
            expanded.wrappedValue = -1
            for _ in 0..<12 { host.step() }
            XCTAssertEqual(card.laidOutFrame.height, compactHeight, accuracy: 1)

            rows.wrappedValue.removeAll { $0 == number }
            for _ in 0..<16 { host.step() }
            XCTAssertNil(host.view(id: .manual("complex-\(number)")))
            XCTAssertTrue(settled(), "removing a visible variable-height row must not leave a realization loop")
            XCTAssertFalse(lazy.mounted.isEmpty)
            XCTAssertTrue(lazy.mounted.values.allSatisfy { $0.view.laidOutFrame.width > 0 && $0.view.laidOutFrame.height > 0 })
            let idle = [lazy.cells.requests, lazy.cells.measurements]
            for _ in 0..<8 { host.step() }
            XCTAssertEqual([lazy.cells.requests, lazy.cells.measurements], idle)
            print("Complex lazy kind \(kind): peak mounted=\(peakMounted), slowest UI step=\(slowestStep)ms, row builds=\(builds.total)")
        }
    }
}
