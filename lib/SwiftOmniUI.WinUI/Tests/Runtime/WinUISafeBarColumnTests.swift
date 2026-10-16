// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import SwiftOmniUIConformance
import XCTest

@MainActor private final class NativePageOwner: WinUILayoutView {
    var arrangementRequests = 0
    override func invalidateArrange() {
        arrangementRequests += 1
        super.invalidateArrange()
    }
}

final class WinUISafeBarColumnTests: XCTestCase {
    func testIntrinsicInvalidationReachesBothNativeOwnershipBoundaries() {
        onUIThread {
            let owner = NativePageOwner()
            let page = WinUISingleChildView()
            page.nativeLayoutOwner = owner
            let content = WinUIStackView(axis: .vertical)
            page.setItems([WinUILayoutItem(view: content)])
            let before = owner.arrangementRequests
            content.invalidateMeasurements()
            XCTAssertGreaterThan(owner.arrangementRequests, before,
                                 "unchanged child identities can still change page geometry")

            let bar = WinUIStackView(axis: .vertical)
            let promoted = WinUISafeAreaBarHost(bar: bar)
            defer { promoted.releaseBar() }
            let revision = promoted.measurementRevision
            bar.invalidateMeasurements()
            XCTAssertGreaterThan(promoted.measurementRevision, revision)
            let after = promoted.measurementRevision
            bar.setOpacity(0.5)
            XCTAssertEqual(promoted.measurementRevision, after, "paint does not change a bar's contribution")
        }
    }

    func testPromotedBarFollowsAncestorDrawingUntilReleased() throws {
        try onUIThread {
            let host = WinUIRenderer.running(reducesMotion: true) {
                ScrollView { Text("Content") }
                    .safeAreaInset(edge: .top, spacing: 0) {
                        Text("Bar").frame(height: 40).id("promoted")
                    }.id("ancestor")
            }
            let ancestor = try XCTUnwrap(host.view(id: .manual("ancestor")))
            let bar = try XCTUnwrap(host.view(id: .manual("promoted")))
            let promoted = try XCTUnwrap(bar.nativeSafeBarOwner as? WinUISafeAreaBarHost)
            ancestor.setOpacity(0.4)
            XCTAssertEqual(bar.drawnOpacity, 0.4, accuracy: 0.01)
            promoted.releaseBar()
            ancestor.setOpacity(0.2)
            XCTAssertEqual(bar.drawnOpacity, 1, accuracy: 0.01,
                           "a released bar must no longer receive its old native promotion's drawing")
        }
    }

    func testBottomEditorDecorationAndControlsFollowHeightAndPageChanges() throws {
        try onUIThread {
            let text = State(wrappedValue: "")
            let history = State(wrappedValue: false)
            let sidebar = State(wrappedValue: true)
            let clock = TestClock()
            let host = WinUIRenderer.running(clock: clock, room: WinUITestHost.wideRoom) {
                NavigationSplitView(sidebar.projectedValue) {
                    Text("Sidebar")
                } detail: {
                    ScrollView { Text(history.wrappedValue ? "History" : "Start") }
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            HStack(alignment: .bottom) {
                                Button("Attach") {}.frame(width: 40, height: 40).id("attach")
                                TextEditor(text: text.projectedValue)
                                    .scrollContentBackground(.hidden)
                                    .frame(height: text.wrappedValue.isEmpty && history.wrappedValue ? 40 : 128)
                                    .background {
                                        RoundedRectangle(cornerRadius: 20).fill(Color.white).id("editor-fill")
                                    }.id("editor")
                                if text.wrappedValue.isEmpty {
                                    HStack {
                                        Button("Send") {}.frame(width: 40, height: 40).id("send-horizontal")
                                    }
                                } else {
                                    VStack {
                                        Button("Send") {}.frame(width: 40, height: 40).id("send-vertical")
                                    }
                                }
                            }.padding(16)
                        }
                }
            }
            let editor = try XCTUnwrap(host.view(id: .manual("editor")))
            for step in 0..<4 {
                withAnimation(.eased(200, .linear)) {
                    history.wrappedValue = step != 3
                    text.wrappedValue = step == 1 ? "输入内容" : ""
                }
                for _ in 0..<12 { host.step(); host.frame() }
                clock.now += 400
                for _ in 0..<12 { host.frame(); host.step() }
                let fill = try XCTUnwrap(host.view(id: .manual("editor-fill")))
                let expected = step == 1 || step == 3 ? 128.0 : 40.0
                XCTAssertEqual(editor.laidOutFrame.height, expected, accuracy: 1)
                XCTAssertEqual(fill.laidOutFrame.height, expected, accuracy: 1)
                XCTAssertTrue(host.view(id: .manual("editor")) === editor)
                for id in ["attach", step == 1 ? "send-vertical" : "send-horizontal"] {
                    let control = try XCTUnwrap(host.view(id: .manual(id)))
                    XCTAssertTrue(control.isAttached)
                    XCTAssertGreaterThan(control.laidOutFrame.width, 0)
                    XCTAssertEqual(control.drawnOpacity, 1, accuracy: 0.01)
                }
            }
        }
    }

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
