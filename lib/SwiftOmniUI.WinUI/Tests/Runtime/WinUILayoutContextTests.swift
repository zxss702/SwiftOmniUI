// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

@MainActor
private final class ContextPage: WinUISingleChildView {
    var nativeMeasureRequests = 0
    override func requestNativeMeasure() {
        nativeMeasureRequests += 1
        super.requestNativeMeasure()
    }
}

@MainActor
private final class ContextSizedRow: WinUILayoutView {
    override func contentSize(width: Double?) -> LayoutSize {
        let safe = layoutSafeArea(in: Rect(0, 0, width ?? 100, 100)).safe
        return LayoutSize(width: safe.width, height: safe.height)
    }
}

final class WinUILayoutContextTests: XCTestCase {
    func testProposalContextsRefreshTheFirstAllocationWithoutContentInvalidation() {
        onUIThread {
            let child = WinUILayoutView()
            let page = ContextPage()
            page.setItems([WinUILayoutItem(view: child)])
            page.prepareMeasure(width: 8, height: 8)
            WinUIDoorbell.commitPending()
            let revision = page.measurementRevision
            let requests = page.nativeMeasureRequests

            for width in [0.0, 8, 0, 8] {
                page.setLayoutContext(SafeAreaContext(bounds: Rect(0, 0, 8, 8),
                                                      container: Rect(0, 0, width, 8)))
                // XAML may reuse the same native 8x8 Measure. SOUI must still
                // prepare the plan belonging to the new context immediately.
                page.prepareMeasure(width: 8, height: 8)
                swiftomniui_winui_arrange(page.handle, 0, 0, 8, 8)
                XCTAssertEqual(child.placedFrame.width, width)
                XCTAssertEqual(page.measurementRevision, revision)
                XCTAssertEqual(page.nativeMeasureRequests, requests,
                               "a selected proposal is not a new content/environment event")
            }
        }
    }

    func testExternalChromeAndKeyboardChangesStillStartLayoutAtTheSameBounds() {
        onUIThread {
            let page = ContextPage()
            page.setItems([WinUILayoutItem(view: WinUILayoutView())])
            page.safeAreaContext = SafeAreaContext(bounds: Rect(0, -48, 300, 248),
                                                   layout: Rect(0, 0, 300, 200),
                                                   container: Rect(0, 0, 300, 200))
            page.prepareMeasure(width: 300, height: 200)
            let beforeChrome = page.nativeMeasureRequests
            page.safeAreaContext = SafeAreaContext(bounds: Rect(0, -80, 300, 280),
                                                   layout: Rect(0, 0, 300, 200),
                                                   container: Rect(0, 0, 300, 200))
            XCTAssertGreaterThan(page.nativeMeasureRequests, beforeChrome,
                                 "outside chrome strips remain environment dependencies")
            page.prepareMeasure(width: 300, height: 200)
            let beforeKeyboard = page.nativeMeasureRequests
            page.safeAreaContext = SafeAreaContext(bounds: Rect(0, -80, 300, 280),
                                                   layout: Rect(0, 0, 300, 200),
                                                   container: Rect(0, 0, 300, 200),
                                                   keyboard: Rect(0, 0, 300, 160))
            XCTAssertGreaterThan(page.nativeMeasureRequests, beforeKeyboard)
            page.prepareMeasure(width: 300, height: 200)
            swiftomniui_winui_arrange(page.handle, 0, 0, 300, 200)
            XCTAssertEqual(page.items.first?.view.placedFrame.height, 160)
        }
    }

    func testAttachedLabelCorrectionsCrossTheirNativeButtonOwner() {
        onUIThread {
            let face = WinUISingleChildView()
            let text = WinUITextView()
            text.setText("Label whose font is resolved on attachment")
            face.setItems([WinUILayoutItem(view: text)])
            let button = WinUIButtonView()
            button.setFace(face)
            let row = WinUIStackView(axis: .horizontal)
            row.setItems([WinUILayoutItem(view: button)])
            row.prepareMeasure(width: 320, height: 40)
            let revisions = [button.measurementRevision, row.measurementRevision]
            let identity = button.handle

            WinUILayoutView.commitAttachedTextMeasurements([face])

            XCTAssertNil(face.placingLayout)
            XCTAssertTrue(face.nativeContentOwner === button)
            XCTAssertGreaterThan(button.measurementRevision, revisions[0])
            XCTAssertGreaterThan(row.measurementRevision, revisions[1])
            XCTAssertEqual(button.handle, identity)
        }
    }

    func testDirectTextFaceCorrectionsAlsoInvalidateTheOwningButton() {
        onUIThread {
            let text = WinUITextView()
            text.setText("Direct native label")
            let button = WinUIButtonView()
            button.setFace(text)
            let row = ContextPage()
            row.setItems([WinUILayoutItem(view: button)])
            row.prepareMeasure(width: 240, height: 40)
            let before = [button.measurementRevision, row.measurementRevision]
            let starting: WinUIView? = text.placingLayout ?? text.nativeContentOwner
            WinUILayoutView.commitAttachedTextMeasurements(starting.map { [$0] } ?? [])
            XCTAssertGreaterThan(button.measurementRevision, before[0])
            XCTAssertGreaterThan(row.measurementRevision, before[1])
        }
    }

    func testLazyRowMeasurementsFollowContextWithoutInventingAContentChange() throws {
        try onUIThread {
            let host = WinUIRenderer.running(reducesMotion: true) {
                ScrollView { LazyVStack { Text("Row") } }.frame(width: 100, height: 100)
            }
            let lazy = try XCTUnwrap(host.views(WinUILazyStackView.self).first)
            let identity = try XCTUnwrap(lazy.mounted.keys.first)
            let row = ContextSizedRow()
            let item = WinUILayoutItem(view: row)
            lazy.setItems([(identity: identity, item: item)])
            let revision = row.measurementRevision
            for height in [20.0, 60, 20] {
                row.setLayoutContext(SafeAreaContext(bounds: Rect(0, 0, 100, 100),
                                                     container: Rect(0, 0, 100, height)))
                let size = lazy.rowSize(identity, item: item, proposedWidth: 100)
                XCTAssertEqual(size.height, height)
                XCTAssertEqual(row.measurementRevision, revision)
                XCTAssertTrue(lazy.needsRowMeasurements,
                              "a context change names its dirty row without waiting for a scroll")
            }
        }
    }

    func testSidebarRestoresScrollRowsAndNativeItemsWithoutScrolling() throws {
        try onUIThread {
            for grid in [false, true] {
                let presented = State(wrappedValue: true)
                let host = WinUIRenderer.running(reducesMotion: true, room: WinUITestHost.wideRoom) {
                    NavigationSplitView(presented.projectedValue) {
                        VStack(spacing: 0) {
                            List(0..<3) { number in Text("Item \(number)") }.frame(height: 120)
                            ScrollView {
                                if grid {
                                    LazyVGrid(columns: [GridItem(.flexible())], spacing: 0) {
                                        ForEach(0..<100) { number in
                                            Button {} label: { Text("Entry \(number)").frame(height: 28) }
                                        }
                                    }
                                } else {
                                    LazyVStack(spacing: 0) {
                                        ForEach(0..<100) { number in
                                            Button {} label: { Text("Entry \(number)").frame(height: 28) }
                                        }
                                    }
                                }
                            }
                        }
                    } detail: { Text("Detail") }
                }
                let lazy = try XCTUnwrap(host.views(WinUILazyView.self).first)
                let scroll = try XCTUnwrap(host.views(WinUIScrollView.self).first)
                let items = try XCTUnwrap(host.views(WinUIItemsView.self).first)
                let identities = [lazy.handle, scroll.handle, items.handle]
                for _ in 0..<3 {
                    presented.wrappedValue = false
                    host.step()
                    host.frame()
                    presented.wrappedValue = true
                    host.step()
                    host.frame()
                    // Wait for the native pane transition and requested row
                    // patch, never for an offset or a user's scroll event.
                    host.settle { lazy.span != nil && !lazy.mounted.isEmpty }
                    host.frame()
                    XCTAssertEqual([lazy.handle, scroll.handle, items.handle], identities)
                    XCTAssertTrue(items.isAttached)
                    XCTAssertGreaterThan(items.laidOutFrame.width, 0)
                    XCTAssertGreaterThan(items.laidOutFrame.height, 0)
                    XCTAssertEqual(scroll.scroller.standing.offset.y, 0, accuracy: 1)
                    var viewport = [Double](repeating: .nan, count: 6)
                    XCTAssertEqual(swiftomniui_winui_scroller_viewport(scroll.scroller.handle, lazy.handle, &viewport),
                                   SwiftOmniUIViewportReady)
                    XCTAssertGreaterThan(viewport[2], 0)
                    XCTAssertGreaterThan(viewport[3], 0)
                    for item in lazy.mounted.values where !item.departing {
                        XCTAssertTrue(item.view.isAttached)
                        XCTAssertGreaterThan(item.view.laidOutFrame.width, 0)
                        XCTAssertGreaterThan(item.view.laidOutFrame.height, 0)
                    }
                }
            }
        }
    }

    func testLazyStackAndGridAllocationDoNotRestoreAnOldNativeMeasureConstraint() throws {
        try onUIThread {
            for grid in [false, true] {
                let host = WinUIRenderer.running(reducesMotion: true) {
                    ScrollView {
                        if grid {
                            LazyVGrid(columns: [GridItem(.flexible())], spacing: 0) {
                                ForEach(0..<20) { number in
                                    Button {} label: { Text("Row \(number)").frame(height: 28) }
                                }
                            }
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(0..<20) { number in
                                    Button {} label: { Text("Row \(number)").frame(height: 28) }
                                }
                            }
                        }
                    }.frame(width: 223, height: 180)
                }
                let lazy = try XCTUnwrap(host.views(WinUILazyView.self).first)
                let button = try XCTUnwrap(lazy.mounted.values.first?.view as? WinUIButtonView)
                let height = lazy.laidOutFrame.height
                let revision = button.measurementRevision
                for _ in 0..<3 {
                    lazy.prepareMeasure(width: 0, height: height)
                    let measured = button.desiredSize
                    lazy.prepareAllocation(in: Rect(0, 0, 223, height))
                    swiftomniui_winui_arrange(lazy.handle, 0, 0, 223, height)
                    XCTAssertEqual(button.desiredSize, measured,
                                   "an allocation plan cannot rewrite a native control's completed DesiredSize")
                    XCTAssertEqual(button.placedFrame.width, 223, accuracy: 1)
                    XCTAssertGreaterThan(button.laidOutFrame.height, 0)
                    XCTAssertEqual(button.measurementRevision, revision)
                }
            }
        }
    }
}
