// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

final class WinUISafeBarColumnTests: XCTestCase {
    func testTheFileBarStaysInItsDetailColumnAndIdleLayoutConverges() throws {
        try onUIThread {
            let visible = State(wrappedValue: true)
            let host = WinUIRenderer.running(reducesMotion: true, room: WinUITestHost.wideRoom) {
                NavigationSplitView(visible.projectedValue) {
                    Text("Sidebar").navigationSplitViewColumnWidth(160)
                } detail: {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(0..<500, id: \.self) { number in Text("Row \(number)").frame(height: 30) }
                        }
                    }.safeAreaInset(edge: .top, spacing: 0) {
                        HStack {
                            Menu { MenuItem("Item") } label: { Text("Breadcrumb") }.buttonStyle(.plain)
                        }.frame(maxWidth: .infinity).frame(height: 32).id("bar")
                    }
                }
            }
            let window = try XCTUnwrap(host.window)
            let bar = try XCTUnwrap(host.view(id: .manual("bar")))
            let scroll = try XCTUnwrap(host.views(WinUIScrollView.self).first)
            host.settle { bar.origin.x > 0 && abs(bar.origin.x - scroll.origin.x) < 1 }
            XCTAssertGreaterThan(bar.origin.x, 0, "the breadcrumb must not cover the sidebar")
            XCTAssertEqual(bar.origin.x, scroll.origin.x, accuracy: 1)
            XCTAssertEqual(bar.frame.width, scroll.frame.width, accuracy: 1)
            XCTAssertGreaterThanOrEqual(bar.origin.y, window.chromeHeight - 1)
            visible.wrappedValue = false
            host.settle { abs(bar.origin.x - scroll.origin.x) < 1 && bar.frame.width == scroll.frame.width }
            XCTAssertTrue(host.view(id: .manual("bar")) === bar)
            XCTAssertEqual(bar.origin.x, scroll.origin.x, accuracy: 1)
            XCTAssertEqual(bar.frame.width, scroll.frame.width, accuracy: 1)
            for _ in 0..<10 { host.step(); host.layOut() }
            let lazy = try XCTUnwrap(host.views(WinUILazyView.self).first)
            let requests = lazy.cells.requests, sizings = WinUILayoutView.sizings
            XCTAssertLessThan(lazy.cells.built.count, 100)
            for _ in 0..<8 { host.step(); host.layOut() }
            XCTAssertEqual(lazy.cells.requests, requests)
            XCTAssertEqual(WinUILayoutView.sizings, sizings, "stable proposals must not keep invalidating their ancestors")
        }
    }
}
