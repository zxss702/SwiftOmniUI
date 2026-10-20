// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

final class WinUISidebarLifecycleTests: XCTestCase {
    func testNativePagesKeepALiveSafeAreaProvider() {
        onUIThread {
            let navigation = WinUINavigationView()
            let page = WinUISingleChildView()
            navigation.setItems([WinUILayoutItem(view: page)])
            let bounds = Rect(0, 0, 300, 200)
            navigation.setLayoutContext(SafeAreaContext(bounds: bounds, layout: bounds,
                                                       container: Rect(0, 12, 300, 188)))
            XCTAssertNil(page.safeAreaContext)
            XCTAssertEqual(page.layoutSafeArea(in: bounds).safe.y, 12)
            navigation.setLayoutContext(SafeAreaContext(bounds: bounds, layout: bounds,
                                                       container: Rect(0, 32, 300, 168)))
            XCTAssertEqual(page.layoutSafeArea(in: bounds).safe.y, 32,
                           "native chrome changes reach the existing page")
        }
    }

    func testExplicitlyClosedBindingOwnsTheFirstWidePresentation() throws {
        try onUIThread {
            let shown = State(wrappedValue: false)
            let host = WinUIRenderer.running(room: WinUITestHost.wideRoom) {
                NavigationSplitView(shown.projectedValue) { Text("Files") } detail: { Text("Detail") }
            }
            let split = try XCTUnwrap(host.views(WinUISplitView.self).first)
            XCTAssertFalse(shown.wrappedValue)
            XCTAssertFalse(split.isPresented)
            XCTAssertFalse(split.automaticallyOpensSidebar)
            XCTAssertEqual(Self.read("paneOpen", from: split.sidebar), "0")
            XCTAssertEqual(Self.read("paneDisplayMode", from: split.sidebar), "inline")
            shown.wrappedValue = true
            host.step()
            XCTAssertTrue(split.isPresented, "manual expansion remains available")
        }
    }

    func testExplicitThreeColumnVisibilityIsNotReplacedWithAll() throws {
        try onUIThread {
            let columns = State(wrappedValue: NavigationSplitViewVisibility.doubleColumn)
            let host = WinUIRenderer.running(room: WinUITestHost.wideRoom) {
                NavigationSplitView(columnVisibility: columns.projectedValue) {
                    Text("Files")
                } content: {
                    Text("Conversation")
                } detail: {
                    Text("Auxiliary")
                }
            }
            let split = try XCTUnwrap(host.views(WinUISplitView.self).first)
            XCTAssertEqual(columns.wrappedValue, .doubleColumn)
            XCTAssertFalse(split.isPresented)
            XCTAssertFalse(split.automaticallyOpensSidebar)
            XCTAssertEqual(Self.read("paneOpen", from: split.sidebar), "0")
        }
    }

    func testPreparedInlineModeSurvivesConfigurationBeforeNativeAllocation() {
        onUIThread {
            let split = WinUISplitView()
            split.automaticallyOpensSidebar = false
            split.setItems([WinUILayoutItem(view: WinUISingleChildView()),
                            WinUILayoutItem(view: WinUISingleChildView())])
            split.prepareFirstPresentation(width: 1280)
            XCTAssertEqual(Self.read("paneDisplayMode", from: split.sidebar), "inline")
            split.sidebarPaneLength = [200, 256, 400]
            XCTAssertEqual(split.sidebar.laidOutFrame.width, 0)
            XCTAssertEqual(Self.read("paneDisplayMode", from: split.sidebar), "inline")
            XCTAssertEqual(Self.read("paneOpen", from: split.sidebar), "0")
        }
    }

    func testInlinePaneKeepsItsRowsThroughoutNativeTransitions() throws {
        try onUIThread {
            let shown = State(wrappedValue: true)
            let host = WinUIRenderer.running(room: WinUITestHost.wideRoom) {
                NavigationSplitView(shown.projectedValue) {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(0..<100) { Text("Row \($0)").frame(height: 28) }
                        }
                    }
                } detail: { Text("Detail") }
            }
            let split = try XCTUnwrap(host.views(WinUISplitView.self).first)
            let scroll = try XCTUnwrap(host.views(WinUIScrollView.self).first)
            let lazy = try XCTUnwrap(host.views(WinUILazyView.self).first)
            for open in [false, true, false, true] {
                shown.wrappedValue = open
                host.step()
                XCTAssertEqual(Self.read("paneOpen", from: split.sidebar), open ? "1" : "0")
                if open {
                    // Reopening the same native pane keeps its existing rows.
                    // No scroll or transition completion repair supplies them.
                    XCTAssertFalse(lazy.mounted.isEmpty)
                    let identities = lazy.mounted.mapValues { $0.view.number }
                    for _ in 0..<8 {
                        host.layOut()
                        host.frame()
                        XCTAssertFalse(lazy.mounted.isEmpty)
                        XCTAssertEqual(lazy.mounted.mapValues { $0.view.number }, identities)
                    }
                    XCTAssertEqual(scroll.scroller.standing.offset.y, 0, accuracy: 1)
                }
            }
        }
    }

    func testClosingSidebarRestoresDetailAndComposerToTheActualNativeWidth() throws {
        try onUIThread {
            let shown = State(wrappedValue: true)
            let host = WinUIRenderer.running(reducesMotion: true, room: WinUITestHost.wideRoom) {
                NavigationSplitView(shown.projectedValue) {
                    Text("Sidebar").navigationSplitViewColumnWidth(256)
                } detail: {
                    ScrollView { Text("Detail").frame(maxWidth: .infinity) }
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            HStack {
                                Button("Attach") {}.frame(width: 40, height: 40)
                                TextEditor().frame(height: 128).id("composer")
                                Button("Send") {}.frame(width: 40, height: 40)
                            }.id("composer-row")
                        }.id("detail")
                }
            }
            let detail = try XCTUnwrap(host.view(id: .manual("detail")))
            let composer = try XCTUnwrap(host.view(id: .manual("composer")))
            let row = try XCTUnwrap(host.view(id: .manual("composer-row")))
            let fullWidth = try XCTUnwrap(host.window?.content).laidOutFrame.width
            for open in [false, true, false] {
                shown.wrappedValue = open
                host.step()
                host.layOut()
                let width = fullWidth - (open ? 256 : 0)
                XCTAssertEqual(detail.laidOutFrame.width, width, accuracy: 1)
                XCTAssertEqual(row.laidOutFrame.width, width, accuracy: 1)
                XCTAssertGreaterThan(composer.laidOutFrame.width, width - 120)
                XCTAssertTrue(host.view(id: .manual("composer")) === composer)
            }
        }
    }

    func testPageSafeAreaUsesLayoutOffsetsThroughNativePresentationTransforms() throws {
        try onUIThread {
            let window = WinUIWindow()
            defer { window.close() }
            let split = WinUISplitView()
            split.automaticallyOpensSidebar = false
            let page = WinUISingleChildView()
            split.setItems([WinUILayoutItem(view: WinUISingleChildView()), WinUILayoutItem(view: page)])
            window.request(WindowFrame(width: 1280, height: 700))
            window.show(split)
            WinUITestHost.pump()
            XCTAssertGreaterThan(page.laidOutFrame.width, 0)
            let bounds = Rect(0, 0, page.laidOutFrame.width, page.laidOutFrame.height)
            let before = page.layoutSafeArea(in: bounds)
            for translation in [256.0, -256, 0] {
                swiftomniui_winui_set_transform(page.handle, translation, 0, 0, 1, 1, 0, 0)
                XCTAssertEqual(page.layoutSafeArea(in: bounds), before,
                               "presentation translation cannot consume the page's safe width")
            }
        }
    }

    @MainActor private static func read(_ property: String, from view: WinUIView) -> String {
        WinUIStrings.read { swiftomniui_winui_read(view.handle, property, $0, $1) }
    }
}
