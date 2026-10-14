// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

final class WinUISDKUpgradeTests: XCTestCase {
    func testOptimizationsAreEnabledBeforeXamlStartsAndSurviveRepeatedEmbedding() {
        onUIThread {
            let text = WinUITextView()
            for _ in 0..<3 {
                WinUITestHost.embed()
                for change in ["defaultStyleOptimizations", "iconNoGridOptimization",
                               "optimizeApplyStyles", "deferContextFlyoutInit"] {
                    let enabled = WinUIStrings.read {
                        swiftomniui_winui_read(text.handle, "xaml.\(change)", $0, $1)
                    }
                    XCTAssertEqual(enabled, "1", "\(change) must be selected before XAML locks its configuration")
                }
            }
        }
    }

    func testDetachedTextUsesSystemStyleMetricsWithDeferredStyleApplication() {
        onUIThread {
            let window = WinUIWindow()
            defer { window.close() }
            let label = WinUITextView()
            label.setText("Title 中")
            // The native styles in the pinned SDK, including BaseTextBlockStyle's
            // inherited weight. Off-tree measurement must not see the unstyled
            // TextBlock defaults (14/400) for every semantic font.
            label.setFont(size: nil, attributes: nil, family: nil, textStyle: .largeTitle)
            XCTAssertEqual(label.wordsStyle.size, 40)
            XCTAssertEqual(label.wordsStyle.weight, 600)
            let detached = label.measure(width: nil, height: nil)
            XCTAssertGreaterThan(detached.height, 30)

            window.show(label)
            WinUITestHost.pump()
            XCTAssertEqual(label.wordsStyle.size, 40)
            XCTAssertEqual(label.wordsStyle.weight, 600)
            XCTAssertEqual(label.measure(width: nil, height: nil).height, detached.height)

            label.setFont(size: nil, attributes: nil, family: nil, textStyle: .body)
            XCTAssertEqual(label.wordsStyle.size, 14)
            XCTAssertEqual(label.wordsStyle.weight, 400, "the derived style overrides its BasedOn weight")
            XCTAssertLessThan(label.measure(width: nil, height: nil).height, detached.height)
            label.setFont(size: nil, attributes: nil, family: nil, textStyle: .headline)
            XCTAssertEqual(label.wordsStyle.size, 14)
            XCTAssertEqual(label.wordsStyle.weight, 600)
        }
    }
}
