// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

final class WinUISidebarLifecycleTests: XCTestCase {
    func testPreparationDoesNotReplaceANativePagesLiveSafeAreaProvider() {
        onUIThread {
            let navigation = WinUINavigationView()
            let page = WinUISingleChildView()
            navigation.setItems([WinUILayoutItem(view: page)])
            let bounds = Rect(0, 0, 300, 200)
            navigation.setLayoutContext(SafeAreaContext(bounds: bounds, layout: bounds,
                                                       container: Rect(0, 12, 300, 188)))
            XCTAssertTrue(navigation.preparePresentation(in: bounds, viewport: nil))
            XCTAssertNil(page.safeAreaContext)
            XCTAssertEqual(page.layoutSafeArea(in: bounds).safe.y, 12)
            navigation.setLayoutContext(SafeAreaContext(bounds: bounds, layout: bounds,
                                                       container: Rect(0, 32, 300, 168)))
            XCTAssertEqual(page.layoutSafeArea(in: bounds).safe.y, 32,
                           "native chrome changes still reach the page after preparation")
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

    func testPanePresentationHasPreparedRowsBeforeItsFirstVisibleFrame() throws {
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
                    // This is before advancing the native transition, with no
                    // completion callback or scrolling supplied to fill rows.
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

    @MainActor private static func read(_ property: String, from view: WinUIView) -> String {
        WinUIStrings.read { swiftomniui_winui_read(view.handle, property, $0, $1) }
    }
}
