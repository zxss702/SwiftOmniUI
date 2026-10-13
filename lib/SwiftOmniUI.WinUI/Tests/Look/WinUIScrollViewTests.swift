// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import SwiftOmniUIConformance
import XCTest
import CSwiftOmniUIWinUI

final class WinUIScrollViewTests: XCTestCase {
    func testBounceConfigurationNeverEnablesAnUnrequestedAxis() throws {
        try onUIThread {
            for axis in [Axis.vertical, .horizontal, .both, .neither] {
                let axes: Axis.Set = axis == .vertical ? .vertical : axis == .horizontal ? .horizontal
                    : axis == .both ? [.vertical, .horizontal] : []
                let host = WinUIRenderer.running {
                    ScrollView(axes) { Color("#FF0000").frame(width: 1_000, height: 1_000) }
                        .frame(width: 240, height: 240)
                }
                let scroll = try XCTUnwrap(host.views(WinUIScrollView.self).first)
                for bounce in [ScrollBounceBehavior.always, .basedOnSize] {
                    scroll.apply(orientation: axis, padding: EdgeInsets(0), verticalBar: .automatic,
                                 horizontalBar: .automatic, defaultAnchor: nil, offset: nil,
                                 bounce: bounce, bounceAxes: [.vertical, .horizontal])
                    var modes = [Int32](repeating: -1, count: 2)
                    swiftomniui_winui_scroller_read_modes(scroll.scroller.handle, &modes)
                    let allowed: Int32 = bounce == .basedOnSize ? 2 : 1
                    XCTAssertEqual(modes[0], axis == .horizontal || axis == .neither ? 0 : allowed)
                    XCTAssertEqual(modes[1], axis == .vertical || axis == .neither ? 0 : allowed)
                }
            }
        }
    }

    /// A scroller shows its content through its viewport: what is scrolled away is cut off at its edges, where any
    /// other SwiftOmniUI layout draws past them.
    func testAScrollerCutsItsContentOffAtItsEdges() throws {
        try onUIThread {
            let host = WinUIRenderer.running {
                VStack {
                    ScrollView { Rectangle().fill(Color("#FF0000")).frame(height: 2000) }.frame(height: 100)
                }
                .frame(height: 300, alignment: .top)
                .verticalAlignment(.start)
            }
            let stack = try XCTUnwrap(host.views(WinUIStackView.self).first)

            XCTAssertEqual(stack.pixels(at: [(5, 50), (5, 150)]), [0xFFFF_0000, 0], "red inside, nothing below")
        }
    }

    /// A scroller outlines itself on its shape and cuts what it shows to that shape.
    func testAScrollerOutlinesItselfAndCutsWhatItShowsToItsShape() throws {
        try onUIThread {
            let host = WinUIRenderer.running {
                ScrollView {
                    Rectangle().fill(Color("#FF0000")).frame(height: 400)
                }
                .contentPadding(10)
                .shape(.roundedRectangle(20))
                .stroke(Color("#0000FF"))
                .strokeWidth(2)
                .frame(width: 100)
                .frame(height: 80)
                .horizontalAlignment(.start)
                .verticalAlignment(.start)
            }

            let scroll = try XCTUnwrap(host.views(WinUIScrollView.self).first)
            XCTAssertEqual(
                scroll.pixels(at: [(50, 0.5), (50, 40), (0.5, 0.5)]), [0xFF00_00FF, 0xFFFF_0000, 0],
                "the outline at the top edge, the content inside, the corner cut")
        }
    }
}
