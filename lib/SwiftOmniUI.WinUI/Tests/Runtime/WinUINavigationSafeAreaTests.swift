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

            let proposal = Rect(0, 0, 480, 300)
            let initial = page.layoutSafeArea(in: proposal)
            XCTAssertEqual(initial.layout, proposal)
            XCTAssertEqual(initial.safe, proposal,
                           "an unarranged parent cannot turn its zero size into right/bottom unsafe strips")
            XCTAssertEqual(initial.insets, EdgeInsets(top: 48, leading: 0, bottom: 0, trailing: 0))
            _ = page.measure(width: Double(480), height: Double(300))
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
                let context = page.layoutSafeArea(in: proposal)
                XCTAssertEqual(context.layout, proposal)
                XCTAssertEqual(context.bounds, Rect(0, -48, proposal.width, proposal.height + 48))
                XCTAssertEqual(context.safe, proposal)
                XCTAssertEqual(context.container, proposal)
                XCTAssertEqual(context.insets, EdgeInsets(top: 48, leading: 0, bottom: 0, trailing: 0))
                XCTAssertEqual(context.consumed, EdgeInsets(0))
                XCTAssertEqual(navigation.allocatedBounds, Rect(0, 0, 320, 220),
                               "reading a new proposal must not require changing the parent's committed frame")
            }
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
