// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

@MainActor
private final class SplitResizePage: WinUILayoutView {
    var proposals: [ProposedViewSize] = []
    var allocations: [Rect] = []

    override func measure(width: Double, height: Double) -> LayoutSize {
        proposals.append(ProposedViewSize(width: width, height: height))
        return super.measure(width: width, height: height)
    }

    override func contentSize(width: Double?) -> LayoutSize {
        LayoutSize(width: width ?? 400, height: 2000)
    }

    override func arrange(in bounds: Rect) { allocations.append(bounds) }
}

final class WinUISplitResizeTests: XCTestCase {
    func testNativeResizeDoesNotRepeatTheEnclosingMeasure() throws {
        try onUIThread {
            let split = WinUISplitView()
            split.automaticallyOpensSidebar = false
            split.sidebarPaneLength = [200, 256, 500]
            split.detailWidthBounds = [200, 256, 500]
            let sidebar = SplitResizePage()
            let content = SplitResizePage()
            let detail = SplitResizePage()
            split.setItems([WinUILayoutItem(view: sidebar), WinUILayoutItem(view: content), WinUILayoutItem(view: detail)])
            split.present(true)
            let window = WinUIWindow()
            defer { window.close() }
            window.request(WindowFrame(width: 1500, height: 800))
            window.show(split)
            WinUITestHost.pump()
            for trailing in [false, true] {
                sidebar.proposals = []; content.proposals = []; detail.proposals = []
                content.allocations = []
                swiftomniui_winui_split_resize((trailing ? split.middle : split.sidebar).handle, trailing ? -40 : 40)
                swiftomniui_winui_update_layout(split.handle)
                let expected = split.laidOutFrame.width - 296 - (trailing ? 296 : 256)
                XCTAssertEqual(content.proposals.count, 1)
                XCTAssertTrue((trailing ? sidebar : detail).proposals.isEmpty,
                              "resizing one pane must not remeasure the unchanged pane")
                XCTAssertFalse(content.allocations.isEmpty)
                for allocation in content.allocations {
                    XCTAssertEqual(allocation.width, expected, accuracy: 1,
                                   "every native allocation must be correct, including the first frame")
                }
            }
        }
    }

    func testResizingColumnsKeepsConversationAtItsNativeAllocation() throws {
        try onUIThread {
            let columns = State(wrappedValue: NavigationSplitViewVisibility.all)
            let host = WinUIRenderer.running(room: LayoutSize(width: 1500, height: 800)) {
                NavigationSplitView(columnVisibility: columns.projectedValue) {
                    ScrollView {
                        LazyVStack {
                            ForEach(0..<100) { Text("File \($0)").frame(height: 28) }
                        }
                    }.navigationSplitViewColumnWidth(min: 200, ideal: 256, max: 500)
                } content: {
                    NavigationStack {
                        GeometryReader { _ in
                            ScrollView {
                                LazyVStack(spacing: 12) {
                                    ForEach(0..<100) { index in
                                        VStack(alignment: .leading, spacing: 8) {
                                            ForEach(0..<6) { line in
                                                Text("Message \(index).\(line) " + String(repeating: "A wrapping conversation message 中文内容。", count: 6))
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                        }.padding(16)
                                    }
                                }.padding(16)
                            }.id("conversation")
                                .safeAreaInset(edge: .bottom, spacing: 0) {
                                    TextEditor().frame(height: 100).id("composer")
                                }
                        }
                    }
                } detail: {
                    Text("Detail").navigationSplitViewColumnWidth(min: 200, ideal: 256, max: 500)
                }
            }
            for _ in 0..<12 { host.step() }
            let split = try XCTUnwrap(host.views(WinUISplitView.self).first)
            let conversation = try XCTUnwrap(host.view(id: .manual("conversation")))
            let composer = try XCTUnwrap(host.view(id: .manual("composer")))
            let lazy = try XCTUnwrap(host.views(WinUILazyView.self).last)
            for trailing in [false, true] {
                let before = WinUILayoutView.sizings
                let measurements = lazy.cells.measurements
                let start = WinUIFrameClock.monotonic()
                var previousWidth = 256.0
                let widths = Array(stride(from: 260.0, through: 380.0, by: 10))
                    + Array(stride(from: 370.0, through: 260.0, by: -10)) + [256]
                for width in widths {
                    swiftomniui_winui_split_resize((trailing ? split.middle : split.sidebar).handle,
                                                   (trailing ? -1 : 1) * (width - previousWidth))
                    previousWidth = width
                    host.layOut()
                    XCTAssertTrue(host.view(id: .manual("conversation")) === conversation)
                    let expected = split.laidOutFrame.width - width - 256
                    XCTAssertEqual(conversation.laidOutFrame.width, expected, accuracy: 1)
                    XCTAssertEqual(composer.laidOutFrame.width, expected, accuracy: 1)
                    host.step()
                    XCTAssertEqual(conversation.laidOutFrame.width, expected, accuracy: 1)
                    XCTAssertEqual(composer.laidOutFrame.width, expected, accuracy: 1)
                }
                print("SPLIT RESIZE trailing=\(trailing) ms=\(WinUIFrameClock.monotonic() - start) sizings=\(WinUILayoutView.sizings - before) rows=\(lazy.cells.measurements - measurements) mounted=\(lazy.mounted.count)")
            }
        }
    }
}
