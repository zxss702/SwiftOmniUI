// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

final class WinUINavigationSafeAreaTests: XCTestCase {
    func testFirstPageMeasurementUsesItsProposalBeforeNavigationHasAnAllocation() throws {
        try onUIThread {
            let (host, navigation, page) = try Self.detachedNavigationPage()
            _ = host
            XCTAssertEqual(navigation.allocatedBounds, Rect(0, 0, 0, 0))
            XCTAssertEqual(page.allocatedBounds, Rect(0, 0, 0, 0))
            XCTAssertTrue(page.sourceElement?.observesSafeArea == true)

            navigation.prepareMeasure(width: 480, height: 300)
            let proposal = Rect(0, 0, 480, 348)
            let initial = page.layoutSafeArea(in: proposal)
            XCTAssertEqual(initial.layout, proposal)
            XCTAssertEqual(initial.bounds, proposal)
            XCTAssertEqual(initial.safe, Rect(0, 48, 480, 300),
                           "the extended native page reserves chrome once, before its first allocation")
            XCTAssertEqual(initial.insets, EdgeInsets(top: 48, leading: 0, bottom: 0, trailing: 0))
            _ = page.measure(width: Double(480), height: Double(348))
            XCTAssertEqual(navigation.allocatedBounds, Rect(0, 0, 0, 0),
                           "this regression covers Measure before the first native Arrange")
            XCTAssertEqual(page.layoutSafeArea(in: proposal), initial)
        }
    }

    func testChangingPageProposalsPreservesWindowEdgesRatherThanTheLastFrameSize() throws {
        try onUIThread {
            let (host, navigation, page) = try Self.detachedNavigationPage()
            _ = host
            // Set a previous native allocation, then offer sizes on both sides
            // of it. Each page proposal describes its complete native frame.
            navigation.prepareMeasure(width: 320, height: 220)
            swiftomniui_winui_arrange(navigation.handle, 0, 0, 320, 220)
            XCTAssertEqual(navigation.allocatedBounds, Rect(0, 0, 320, 220))

            for proposal in [Rect(0, 0, 700, 500), Rect(0, 0, 80, 20),
                             Rect(0, 0, 320, 220), Rect(0, 0, 700, 500)] {
                navigation.prepareMeasure(width: proposal.width, height: proposal.height)
                let extended = Rect(0, 0, proposal.width, proposal.height + 48)
                let context = page.layoutSafeArea(in: extended)
                XCTAssertEqual(context.layout, extended)
                XCTAssertEqual(context.bounds, extended)
                XCTAssertEqual(context.safe, Rect(0, 48, proposal.width, proposal.height))
                XCTAssertEqual(context.container, context.safe)
                XCTAssertEqual(context.insets, EdgeInsets(top: 48, leading: 0, bottom: 0, trailing: 0))
                XCTAssertEqual(context.consumed, EdgeInsets(0))
                XCTAssertEqual(navigation.allocatedBounds, Rect(0, 0, 320, 220),
                               "reading a new proposal must not require changing the parent's committed frame")
            }
        }
    }

    func testMultiChildLayoutsForwardChromeOnlyToTheChildTouchingItsEdge() {
        onUIThread {
            let container = WinUIStackView(axis: .vertical)
            let nested = WinUIZStackView()
            // The viewport is above a footer, so the container is deliberately
            // not an uninterrupted single-child wrapper.
            container.setItems([WinUILayoutItem(view: nested), WinUILayoutItem(view: WinUILabelView())])
            container.rootSafeAreaContext = { bounds in
                SafeAreaContext(bounds: Rect(0, -48, bounds.width, bounds.height + 48),
                                layout: bounds, container: bounds)
            }
            container.prepareMeasure(width: 300, height: 200)
            swiftomniui_winui_arrange(container.handle, 0, 0, 300, 200)
            let top = container.context(for: nested, at: Rect(0, 0, 300, 160))
            XCTAssertEqual(top.bounds, Rect(0, -48, 300, 208))
            let lower = container.context(for: nested, at: Rect(0, 40, 300, 120))
            XCTAssertEqual(lower.bounds, Rect(0, 0, 300, 120),
                           "a child below another header cannot acquire the window's top strip")
        }
    }

    /// A real native-owned page whose ScrollView preserves the incoming safe
    /// environment, detached so its first Measure has no previous window frame.
    @MainActor private static func detachedNavigationPage()
        throws -> (WinUIRenderer, WinUINavigationView, WinUILayoutView) {
        let host = WinUIRenderer.bare(reducesMotion: true)
        var text = HostPatch(id: .manual("text"), type: .text)
        text.properties = [.text: .string("Content")]
        var scroll = HostPatch(id: .manual("scroll"), type: .scrollView)
        scroll.children = .arranged([text])
        var page = HostPatch(id: .manual("page"), type: .page)
        page.children = .arranged([scroll])
        var stack = HostPatch(id: .manual("navigation"), type: .navigationStack)
        stack.children = .arranged([page])
        host.runtime.tree.apply(stack, complete: true)
        let navigation = try XCTUnwrap(host.views(WinUINavigationView.self).first)
        let view = try XCTUnwrap(host.view(id: .manual("page")) as? WinUILayoutView)
        navigation.rootSafeAreaContext = { bounds in
            SafeAreaContext(bounds: Rect(bounds.x, bounds.y - 48, bounds.width, bounds.height + 48),
                            layout: bounds, container: bounds)
        }
        return (host, navigation, view)
    }
}
