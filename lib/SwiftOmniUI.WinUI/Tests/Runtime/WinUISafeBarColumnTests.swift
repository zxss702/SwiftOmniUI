// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

final class WinUISafeBarColumnTests: XCTestCase {
    func testWideSidebarIsOpenBeforeTheWindowFirstActivates() {
        onUIThread {
            let window = WinUIWindow()
            defer { window.close() }
            let split = WinUISplitView()
            let sidebar = WinUISingleChildView()
            let detail = WinUISingleChildView()
            split.setItems([WinUILayoutItem(view: sidebar), WinUILayoutItem(view: detail)])

            let pending = sidebar.rootSafeAreaContext?(Rect(0, 0, 256, 600))
            XCTAssertEqual(pending?.safe.width, 256, "an unattached pane has no native origin yet")

            window.show(split, present: false)
            window.request(WindowFrame(width: WinUISidebarView.expandsAt + 8, height: 700))
            window.prepareFirstPresentation(split: split)
            XCTAssertTrue(split.isPresented)
            XCTAssertEqual(WinUIStrings.read {
                swiftomniui_winui_read(split.sidebar.handle, "paneOpen", $0, $1)
            }, "1", "the pane must already be open before the first native frame")

            window.presentContent()
            WinUITestHost.pump()
            XCTAssertTrue(sidebar.isAttached, "the first frame must include the sidebar page")
        }
    }

    func testNarrowPreflightDoesNotConsumeTheFirstWideRoom() {
        onUIThread {
            let window = WinUIWindow()
            defer { window.close() }
            let split = WinUISplitView()
            split.setItems([WinUILayoutItem(view: WinUISingleChildView()),
                            WinUILayoutItem(view: WinUISingleChildView())])
            window.show(split, present: false)
            window.request(WindowFrame(width: 560, height: 440))
            window.prepareFirstPresentation(split: split)
            XCTAssertFalse(split.isPresented)
            window.request(WindowFrame(width: WinUISidebarView.expandsAt + 8, height: 700))
            window.prepareFirstPresentation(split: split)
            XCTAssertTrue(split.isPresented)
        }
    }

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

    func testSidebarPageSwitchReappliesTopAndBottomSafeInsetsWithoutResize() throws {
        try onUIThread {
            let visible = State(wrappedValue: true)
            let page = State(wrappedValue: 0)
            let host = WinUIRenderer.running(reducesMotion: true, room: WinUITestHost.wideRoom) {
                NavigationSplitView(visible.projectedValue) {
                    VStack {
                        if page.wrappedValue == 0 {
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(0..<100, id: \.self) { row in
                                        Text("File \(row)").frame(height: 30).id("file-\(row)")
                                    }
                                }
                            }
                            .id("files-scroll")
                            .safeAreaInset(edge: .bottom, spacing: 0) {
                                Text("Search").frame(height: 40).id("search")
                            }
                            .transition(.opacity)
                        } else {
                            ScrollView { Text("Other page") }
                                .transition(.opacity)
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        Text("Tabs").frame(maxWidth: .infinity).frame(height: 44).id("tabs")
                    }
                    .navigationSplitViewColumnWidth(220)
                } detail: {
                    Text("Detail")
                }
            }
            let tabs = try XCTUnwrap(host.view(id: .manual("tabs")))
            func checkInsets() throws {
                let first = try XCTUnwrap(host.view(id: .manual("file-0")))
                let search = try XCTUnwrap(host.view(id: .manual("search")))
                let scroll = try XCTUnwrap(host.views(WinUIScrollView.self).first)
                XCTAssertGreaterThanOrEqual(first.origin.y, tabs.origin.y + tabs.frame.height - 1)
                scroll.scroller.move(to: Point(0, scroll.scroller.standing.reach.y))
                host.settle { host.view(id: .manual("file-99")) != nil }
                let last = try XCTUnwrap(host.view(id: .manual("file-99")))
                XCTAssertLessThanOrEqual(last.origin.y + last.frame.height, search.origin.y + 1)
                scroll.scroller.move(to: .zero)
                host.settle { host.view(id: .manual("file-0")) != nil }
            }
            host.settle { host.view(id: .manual("file-0")) != nil }
            try checkInsets()
            page.wrappedValue = 1
            host.settle { host.view(id: .manual("file-0")) == nil }
            page.wrappedValue = 0
            host.settle { host.view(id: .manual("file-0")) != nil }
            try checkInsets()
        }
    }

    func testNativeSplitRearrangesNestedSafeBarsWhenSidebarContentChangesAtTheSameSize() throws {
        try onUIThread {
            let shown = State(wrappedValue: true)
            let page = State(wrappedValue: 0)
            let host = WinUIRenderer.running(reducesMotion: true, room: WinUITestHost.wideRoom) {
                NavigationSplitView(shown.projectedValue) {
                    VStack {
                        if page.wrappedValue == 0 {
                            ScrollView { Text("Files") }
                                .id("files")
                                .safeAreaInset(edge: .bottom, spacing: 0) {
                                    Text("Search").frame(height: 40).id("search-bar")
                                }
                        } else {
                            ScrollView { Text("Git") }
                                .id("git")
                                .safeAreaInset(edge: .bottom, spacing: 0) {
                                    Text("Graph").frame(height: 96).id("graph-bar")
                                }
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        Text("Tabs").frame(height: 44).id("sidebar-tabs")
                    }
                    .navigationSplitViewColumnWidth(220)
                } detail: { Text("Detail") }
            }
            let tabs = try XCTUnwrap(host.view(id: .manual("sidebar-tabs")))
            let split = try XCTUnwrap(host.views(WinUISplitView.self).first)
            let originalSize = split.laidOutFrame
            let nativePages = host.views(WinUISingleChildView.self).filter { $0.nativeLayoutOwner === split }
            XCTAssertEqual(nativePages.count, 2)
            XCTAssertTrue(nativePages.allSatisfy { $0.rootSafeAreaContext != nil },
                          "native SplitView pages must inherit the window's safe-area proposal")
            let sidebarPage = try XCTUnwrap(nativePages.first { $0.origin.x < split.origin.x + 1 })
            XCTAssertGreaterThan(sidebarPage.layoutSafeArea(in: sidebarPage.allocatedBounds).insets.top, 0,
                                 "the sidebar page must inherit the title-bar's unsafe strip")
            for index in [1, 0, 1, 0] {
                page.wrappedValue = index
                let contentID = index == 0 ? "files" : "git"
                let bottomID = index == 0 ? "search-bar" : "graph-bar"
                host.settle {
                    guard let content = host.view(id: .manual(contentID)),
                          let bottom = host.view(id: .manual(bottomID)) else { return false }
                    return content.origin.y >= tabs.origin.y + tabs.frame.height - 1
                        && content.origin.y + content.frame.height <= bottom.origin.y + 1
                }
                host.layOut()
                let content = try XCTUnwrap(host.view(id: .manual(contentID)))
                let bottom = try XCTUnwrap(host.view(id: .manual(bottomID)))
                XCTAssertEqual(split.laidOutFrame.width, originalSize.width, accuracy: 1)
                XCTAssertEqual(split.laidOutFrame.height, originalSize.height, accuracy: 1)
                XCTAssertGreaterThan(sidebarPage.layoutSafeArea(in: sidebarPage.allocatedBounds).insets.top, 0)
                XCTAssertGreaterThanOrEqual(content.origin.y, tabs.origin.y + tabs.frame.height - 1)
                XCTAssertLessThanOrEqual(content.origin.y + content.frame.height,
                                         bottom.origin.y + 1)
            }
        }
    }
}
