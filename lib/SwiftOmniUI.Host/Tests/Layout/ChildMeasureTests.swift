// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) @testable import SwiftOmniUICore
@_spi(Host) @testable import SwiftOmniUIHost
import XCTest

/// How a layout measures a child, the same on every host.
final class ChildMeasureTests: XCTestCase {
    /// A stated width is the width a child is measured at, within its bounds; with none, the offer, no wider than
    /// its most width.
    func testAChildIsOfferedItsStatedWidthElseTheOfferWithinItsMost() {
        var values = LayoutValues()
        values.width = 120
        values.maximumWidth = 80
        XCTAssertEqual(values.offer(300), 80)

        values.width = nil
        XCTAssertEqual(values.offer(300), 80)
        XCTAssertEqual(values.offer(50), 50)
        values.maximumWidth = nil
        XCTAssertNil(values.offer(nil))
    }

    /// A child stating a width is measured at the width it is placed at: within its bounds and the room offered,
    /// so its words wrap where they stand - a toolkit measuring until its layout settles (WinUI) gives up on a child
    /// measured at one width and placed at another.
    func testAChildStatingAWidthIsMeasuredAtTheWidthItIsPlacedAt() {
        var values = LayoutValues()
        for stated in [30.0, 120, 416, 504] {
            for (minimum, maximum) in [(nil, nil), (60.0, nil), (nil, 80.0), (60.0, 80.0)] as [(Double?, Double?)] {
                for room in [100.0, 416] {
                    values.width = stated
                    values.minimumWidth = minimum
                    values.maximumWidth = maximum
                    let placed = Extent.of(
                        option: values.horizontal, stated: stated, natural: 0, available: room,
                        minimum: minimum, maximum: maximum)
                    XCTAssertEqual(values.offer(room), placed, "\(stated) stated, \(room) offered")
                }
            }
        }
        values.width = 504
        values.minimumWidth = nil
        values.maximumWidth = nil
        XCTAssertEqual(values.offer(nil), 504, "with no room said, its own width")
    }

    /// A child's size is its stated size before what it measured, within its bounds.
    func testAChildsSizeIsItsStatedSizeBeforeItsMeasuredOne() {
        var values = LayoutValues()
        values.height = 40
        values.minimumWidth = 30
        let size = values.sized(LayoutSize(width: 10, height: 99))
        XCTAssertEqual(size.width, 30)
        XCTAssertEqual(size.height, 40)
    }

    func testNestedViewportFrameKeepsItsBoundThroughContainingStacks() {
        var frame = LayoutValues()
        frame.scrollAxes = .vertical
        frame.maximumHeight = 256
        let bounded = frame.sized(LayoutSize(width: 320, height: 10), offered: 320)
        XCTAssertEqual(bounded.height, 256,
                       "an outer ScrollView's unspecified height must not erase a bounded inner viewport")

        var stack = LayoutValues()
        stack.scrollAxes = .vertical
        let withHeader = LayoutSize(width: bounded.width, height: bounded.height + 24)
        XCTAssertEqual(stack.sized(withHeader, offered: 320), withHeader,
                       "inherited scroll axes describe flexibility, not native viewport identity")

        frame.maximumHeight = 128
        XCTAssertEqual(frame.sized(bounded, offered: 320).height, 128)
        frame.height = 64
        XCTAssertEqual(frame.sized(bounded, offered: 320).height, 64)
    }

    func testHorizontalViewportAndContainingFrameKeepDistinctIdealSizes() {
        var viewport = LayoutValues()
        viewport.isScrollViewport = true
        viewport.scrollAxes = .horizontal
        XCTAssertEqual(viewport.sized(LayoutSize(width: 40_000, height: 48)).width, 10)
        XCTAssertEqual(viewport.sized(LayoutSize(width: 40_000, height: 48), offered: 120).width, 120)

        var frame = viewport
        frame.isScrollViewport = false
        frame.maximumWidth = 192
        XCTAssertEqual(frame.sized(LayoutSize(width: 10, height: 48)).width, 192)
        frame.maximumWidth = nil
        XCTAssertEqual(frame.sized(LayoutSize(width: 96, height: 48)).width, 96)
    }
}
