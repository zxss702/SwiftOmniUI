// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

private final class WindowLayoutProbe: WinUILayoutView {
    var measures = 0
    var arrangements = 0
    var extent = 40.0

    override func measure(width: Double, height: Double) -> LayoutSize {
        measures += 1
        return super.measure(width: width, height: height)
    }

    override func contentSize(width: Double?) -> LayoutSize {
        LayoutSize(width: width ?? 80, height: extent)
    }

    override func arrange(in bounds: Rect) { arrangements += 1 }
}

final class WinUIWindowLayoutTests: XCTestCase {
    func testDefaultMicaAndExplicitTranslucencySurviveTraitUpdatesAndRootFills() {
        onUIThread {
            let window = WinUIWindow()
            defer { window.close() }
            var frame = [Double](repeating: 0, count: 13)
            swiftomniui_winui_window_frame(window.handle, &frame)
            XCTAssertEqual(frame[10], 0, "ordinary windows start with Mica, not Desktop Acrylic")
            for translucent in [false, true, false] {
                swiftomniui_winui_window_set_traits(window.handle, true, true, true, translucent, false)
                swiftomniui_winui_window_frame(window.handle, &frame)
                XCTAssertEqual(frame[10], translucent ? 1 : 0,
                               "only explicitly translucent windows opt into Desktop Acrylic")
            }
            swiftomniui_winui_window_set_background(window.handle, true, 0xff123456)
            var background: UInt32 = 0
            XCTAssertTrue(swiftomniui_winui_window_background(window.handle, &background))
            XCTAssertEqual(background, 0xff123456, "authored opaque root colours still cover the default backdrop")
            swiftomniui_winui_window_set_background(window.handle, false, 0)
            XCTAssertFalse(swiftomniui_winui_window_background(window.handle, &background))
            swiftomniui_winui_window_frame(window.handle, &frame)
            XCTAssertEqual(frame[10], 0)
        }
    }

    func testFirstAllocationIncludesTheDeclaredChromeBeforeActivation() {
        onUIThread {
            let window = WinUIWindow()
            defer { window.close() }
            let page = WindowLayoutProbe()
            page.extent = 400
            let chrome = window.chromeHeight
            XCTAssertGreaterThan(window.titleBar.layoutHeight, 0,
                                 "the template's height is available without a live XAML Measure")
            XCTAssertGreaterThanOrEqual(chrome, window.titleBar.layoutHeight)
            window.boundContent(WindowBounds(minimumWidth: 560, minimumHeight: 400), chromeHeight: chrome)
            window.requestContent(WindowFrame(width: 560, height: 400), chromeHeight: chrome)
            window.show(page)
            WinUITestHost.pump()

            XCTAssertEqual(window.chromeHeight, chrome, accuracy: 0.01)
            XCTAssertEqual(window.titleBar.laidOutFrame.height, window.titleBar.layoutHeight, accuracy: 1)
            XCTAssertEqual(page.laidOutFrame.height, 400, accuracy: 1,
                           "the first frame must not borrow pixels from content for the caption")
            XCTAssertEqual(window.contentSize.height, 400, accuracy: 1)
        }
    }

    func testReadingChromeDoesNotFlushPendingPageLayout() {
        onUIThread {
            let window = WinUIWindow()
            defer { window.close() }
            let page = WindowLayoutProbe()
            window.request(WindowFrame(width: 560, height: 440))
            // The native template's declaration is available before activation.
            let initialChrome = window.chromeHeight
            XCTAssertGreaterThan(initialChrome, 0)
            window.show(page)
            WinUITestHost.pump()
            XCTAssertEqual(window.chromeHeight, initialChrome, accuracy: 1,
                           "the first caption height must not need a later navigation to settle")
            XCTAssertGreaterThan(page.measures, 0)
            XCTAssertGreaterThan(page.arrangements, 0)

            page.extent = 96
            page.invalidateMeasurements()
            let measures = page.measures
            let arrangements = page.arrangements
            for _ in 0..<3 {
                let height = window.chromeHeight
                window.boundContent(WindowBounds(minimumWidth: 80, minimumHeight: 96), chromeHeight: height)
            }
            XCTAssertEqual(page.measures, measures, "caption reads must leave the pending page measure to XAML")
            XCTAssertEqual(page.arrangements, arrangements, "caption reads must not synchronously arrange the page")

            WinUITestHost.pump()
            XCTAssertGreaterThan(page.measures, measures, "the scheduled native pass still measures changed content")
            XCTAssertGreaterThan(page.arrangements, arrangements)
        }
    }

    func testReadingChromeDoesNotRealizeAChangedLazyWindow() throws {
        try onUIThread {
            let host = WinUIRenderer.running(reducesMotion: true) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(0..<10_000) { number in Text("Row \(number)").frame(height: 32) }
                    }
                }
                .frame(width: 480, height: 320)
            }
            for _ in 0..<8 { host.step() }
            let lazy = try XCTUnwrap(host.views(WinUILazyStackView.self).first)
            let window = try XCTUnwrap(host.window)
            let built = lazy.cells.built
            let requests = lazy.cells.requests
            lazy.spacing = 80

            for _ in 0..<3 { _ = window.chromeHeight }
            XCTAssertEqual(lazy.cells.requests, requests, "reading chrome must not dispatch realizedChanged")
            XCTAssertEqual(lazy.cells.built, built)
            for _ in 0..<8 { host.step() }
            XCTAssertLessThan(lazy.cells.built.count, built.count, "the normal viewport pass still follows changed geometry")
            XCTAssertLessThan(lazy.mounted.count, 80)
        }
    }

    func testWindowWritesFollowActualNativeBoundsAndClientSize() {
        onUIThread {
            let window = WinUIWindow()
            defer { window.close() }
            window.request(WindowFrame(width: 560, height: 440))
            var frame = [Double](repeating: 0, count: 13)
            var client = [0.0, 0.0]
            swiftomniui_winui_window_frame(window.handle, &frame)
            swiftomniui_winui_window_client_size(window.handle, &client)
            XCTAssertEqual(client, [frame[2], frame[3]])

            let bounds = WindowBounds(minimumWidth: 200, minimumHeight: 160, maximumWidth: 800, maximumHeight: 700)
            window.bound(bounds)
            window.bound(bounds)
            // Native changes must still be corrected: suppressing duplicate writes
            // must not rely on a stale Swift snapshot of the presenter or its scale.
            swiftomniui_winui_window_set_limits(window.handle, [100, 100, 900, 900])
            window.bound(bounds)
            swiftomniui_winui_window_frame(window.handle, &frame)
            for (actual, expected) in zip(frame[4..<8], [200.0, 160, 800, 700]) {
                XCTAssertEqual(actual, expected, accuracy: 1)
            }
        }
    }
}
