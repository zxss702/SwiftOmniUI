// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@_spi(Host) @testable import SwiftOmniUIHost

final class DiagnosticTimingsTests: XCTestCase {
    @MainActor
    func testDisabledTimingRunsTheBodyOnceAndWritesNothing() {
        var lines: [String] = []
        var calls = 0
        let diagnostics = DiagnosticText(tallies: false, inspects: false) { lines.append($0) }
        let result = diagnostics.measure("core.render") { calls += 1; return 42 }
        diagnostics.writeTimings(now: 0)
        XCTAssertEqual(result, 42)
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(lines.isEmpty)
    }

    @MainActor
    func testCopiesShareNativeCostsAndRecursiveCallsDoNotDoubleChargeTime() throws {
        var lines: [String] = []
        let diagnostics = DiagnosticText(tallies: true, inspects: false) { lines.append($0) }
        let native = diagnostics
        let result = diagnostics.measure("winui.nativeMeasure") {
            native.measure("winui.nativeMeasure") {
                native.measure("winui.panelMeasure") { 42 }
            }
        }
        native.measure("winui.nativeMeasure") {}
        diagnostics.writeTimings(now: 0)
        let line = try XCTUnwrap(lines.first)
        XCTAssertEqual(result, 42)
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(line.contains("winui.nativeMeasure calls 3 roots 2"))
        XCTAssertTrue(line.contains("winui.panelMeasure calls 1 roots 1"))
        XCTAssertFalse(line.contains("nan"))
        XCTAssertFalse(line.contains("inf"))
    }

    @MainActor
    func testBurstOutputIsBoundedAndKeepsUnprintedSamples() {
        var lines: [String] = []
        let diagnostics = DiagnosticText(tallies: true, inspects: false) { lines.append($0) }
        diagnostics.measure("core.render") {}
        diagnostics.writeTimings(now: 0)
        for now in [1.0, 20, 99] {
            diagnostics.measure("core.render") {}
            diagnostics.writeTimings(now: now)
        }
        XCTAssertEqual(lines.count, 1)
        diagnostics.writeTimings(now: 100)
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[1].contains("core.render calls 4 roots 4"))
        diagnostics.writeTimings(now: 200)
        XCTAssertEqual(lines.count, 2, "an idle runtime writes no more samples")
    }
}
