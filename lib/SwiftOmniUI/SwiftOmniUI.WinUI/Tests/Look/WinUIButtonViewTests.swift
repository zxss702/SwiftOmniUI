// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import SwiftOmniUIConformance
import XCTest

final class WinUIButtonViewTests: XCTestCase {
    /// A button styled by the application wears its fill, its words' colour and its rounded corners; the corner
    /// outside the rounding shows nothing of it.
    func testAButtonWearsItsFillWordsAndCorners() throws {
        try onUIThread {
            let host = WinUIRenderer.running {
                VStack {
                    Button("Go")
                        .background(Color("#512BD4"))
                        .foregroundStyle(Color("#FFFFFF"))
                        .shape(.roundedRectangle(10))
                        .contentPadding(16, 11)
                        .frame(width: 120)
                        .frame(height: 40)
                        .horizontalAlignment(.start)
                }
            }
            let button = try XCTUnwrap(host.views(WinUIButtonView.self).first)

            XCTAssertEqual(button.pixels(at: [(60, 3), (0.5, 0.5)]), [0xFF51_2BD4, 0], "the fill, a corner cut")
        }
    }

    /// A press on a button that keeps nothing takes its check back whole: the fill the look set is still drawn,
    /// however often it is pressed - a button's third, indeterminate look holds none of it.
    func testAPressOnAButtonThatKeepsNothingLeavesItsFill() throws {
        try onUIThread {
            let host = WinUIRenderer.running {
                VStack {
                    Button("Go")
                        .background(Color("#512BD4"))
                        .frame(width: 120).frame(height: 40)
                        .horizontalAlignment(.start)
                }
            }
            let button = try XCTUnwrap(host.views(WinUIButtonView.self).first)

            button.invoke()
            host.settle { button.pixels(at: [(60, 20)]) == [0xFF51_2BD4] }
            XCTAssertEqual(button.pixels(at: [(60, 20)]), [0xFF51_2BD4], "pressed once, the fill keeps")
            button.invoke()
            host.settle { true }
            XCTAssertEqual(button.pixels(at: [(60, 20)]), [0xFF51_2BD4], "pressed twice, the fill keeps")
        }
    }

    /// A button nothing styles is WinUI's own: the platform's fill, not the application's.
    func testAButtonNothingStylesIsWinUIsOwn() throws {
        try onUIThread {
            let host = WinUIRenderer.running { VStack { Button("Plain").frame(width: 120).frame(height: 40).horizontalAlignment(.start) } }
            let button = try XCTUnwrap(host.views(WinUIButtonView.self).first)

            XCTAssertNotEqual(button.pixels(at: [(60, 3)]), [0xFF51_2BD4])
            XCTAssertNotEqual(button.pixels(at: [(60, 3)]), [0], "WinUI fills its own button")
        }
    }
}
