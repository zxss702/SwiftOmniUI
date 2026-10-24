// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

/// A spinner a click stops.
private struct SpinnerPage: View {
    @State private var running = true

    var body: some View {
        VStack {
            ActivityIndicator(running)
            Button("Stop").onClicked { running = false }
        }
    }
}

final class WinUIIndicatorViewTests: XCTestCase {
    /// Bare and labelled progress views share the native spinner's compact size.
    func testSpinnersMeasureAndDrawAt24Points() throws {
        try onUIThread {
            let host = WinUIRenderer.running {
                VStack {
                    ProgressView()
                    ProgressView("Loading")
                    ActivityIndicator(true)
                    ProgressView().frame(width: 64, height: 64)
                }
                .horizontalAlignment(.start)
                .verticalAlignment(.start)
            }
            let spinners = host.views(WinUIActivityIndicatorView.self)
            XCTAssertEqual(spinners.count, 4)
            for spinner in spinners {
                let measured = spinner.measure(width: nil, height: nil)
                XCTAssertEqual(measured.width, 24, accuracy: 0.01)
                XCTAssertEqual(measured.height, 24, accuracy: 0.01)
                XCTAssertEqual(spinner.laidOutFrame.width, 24, accuracy: 0.01)
                XCTAssertEqual(spinner.laidOutFrame.height, 24, accuracy: 0.01)
                XCTAssertTrue(spinner.isRunning)
            }
            let label = try XCTUnwrap(host.views(WinUILabelView.self).first)
            let labelledSpinner = try XCTUnwrap(spinners.dropFirst().first)
            XCTAssertEqual(label.text, "Loading")
            XCTAssertEqual(labelledSpinner.origin.y - label.origin.y - label.laidOutFrame.height, 6, accuracy: 0.01)
        }
    }

    /// The native ring keeps its tint and responds to a state change after sizing.
    func testACompactSpinnerKeepsItsTintAndStops() throws {
        try onUIThread {
            let host = WinUIRenderer.running(reducesMotion: true) { SpinnerPage() }
            let spinner = try XCTUnwrap(host.views(WinUIActivityIndicatorView.self).first)
            XCTAssertTrue(spinner.isRunning)
            spinner.setTint(.color(red: 255, green: 0, blue: 0, alpha: 255))
            var bytes = [CChar](repeating: 0, count: 32)
            let length = swiftomniui_winui_read(spinner.handle, "tint", &bytes, Int32(bytes.count))
            XCTAssertGreaterThan(length, 0)
            let tint = String(decoding: bytes.prefix(Int(max(0, length))).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            XCTAssertEqual(tint, "#FFFF0000")

            try XCTUnwrap(host.views(WinUIButtonView.self).first).invoke()
            host.settle { !spinner.isRunning }
            XCTAssertFalse(spinner.isRunning)
            XCTAssertTrue(host.views(WinUIActivityIndicatorView.self).first === spinner)
        }
    }

    /// A bar fills in its tint as far as its work went, and no further; a fraction past the end is the end.
    func testABarFillsInItsTintAsFarAsItsWorkWent() {
        onUIThread {
            let host = WinUIRenderer.running {
                VStack {
                    ProgressBar(0.5).tint(Color("#FF0000")).frame(width: 200).frame(height: 8)
                    ProgressBar(1.5).frame(width: 200).frame(height: 8)
                }
                .horizontalAlignment(.start)
                .verticalAlignment(.start)
            }
            let bars = host.views(WinUIProgressBarView.self)
            host.settle { bars[0].pixels(at: [(20, 4)]) == [0xFFFF_0000] }

            XCTAssertEqual(bars[0].pixels(at: [(20, 4), (180, 4)]).map { $0 == 0xFFFF_0000 }, [true, false])
        }
    }
}
