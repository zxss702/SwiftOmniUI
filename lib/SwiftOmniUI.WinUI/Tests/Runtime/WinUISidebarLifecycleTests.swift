// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

final class WinUISidebarLifecycleTests: XCTestCase {
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

    func testTransitionCompletionsCoalesceAndWaitForNativeLayoutToEnd() {
        onUIThread {
            let split = WinUISplitView()
            let pane = WinUISingleChildView(), detail = WinUISingleChildView()
            split.setItems([WinUILayoutItem(view: pane), WinUILayoutItem(view: detail)])
            WinUIDoorbell.commitPending()
            let revisions = [pane.measurementRevision, detail.measurementRevision]
            split.withNativeArrange {
                split.sidebar.transitionCompleted()
                split.middle.transitionCompleted()
                XCTAssertEqual([pane.measurementRevision, detail.measurementRevision], revisions)
            }
            WinUIDoorbell.commitPending()
            XCTAssertEqual(pane.measurementRevision, revisions[0] + 1)
            XCTAssertEqual(detail.measurementRevision, revisions[1] + 1)
        }
    }

    func testNativePaneCompletionRestoresItsRowsWithoutAnOffsetChange() throws {
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
            let original = split.sidebar.onTransitionCompleted
            var completed = 0
            split.sidebar.onTransitionCompleted = { completed += 1; original?() }
            for open in [false, true, false, true] {
                let before = completed
                shown.wrappedValue = open
                host.step()
                host.settle { completed > before }
                XCTAssertGreaterThan(completed, before, "the native template must report its final state")
                if open {
                    host.settle { !lazy.mounted.isEmpty && lazy.span != nil }
                    host.frame()
                    XCTAssertFalse(lazy.mounted.isEmpty)
                    XCTAssertNotNil(lazy.span)
                    XCTAssertFalse(lazy.isWaitingForViewport)
                    XCTAssertEqual(scroll.scroller.standing.offset.y, 0, accuracy: 1)
                }
            }
        }
    }

    @MainActor private static func read(_ property: String, from view: WinUIView) -> String {
        WinUIStrings.read { swiftomniui_winui_read(view.handle, property, $0, $1) }
    }
}
