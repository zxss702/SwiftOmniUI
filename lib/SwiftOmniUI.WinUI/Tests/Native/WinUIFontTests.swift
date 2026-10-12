// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

final class WinUIFontTests: XCTestCase {
    func testTextAndSymbolsReuseTheSystemStyleReaderAcrossRepeatedRows() throws {
        try onUIThread {
            let before = swiftomniui_winui_font_probes()
            var expected: (size: Double, weight: Int)?
            for _ in 0..<100 {
                let label = WinUITextView()
                label.setFont(size: nil, attributes: nil, family: nil, textStyle: .headline)
                let style = label.wordsStyle
                if let expected {
                    XCTAssertEqual(style.size, expected.size)
                    XCTAssertEqual(style.weight, expected.weight)
                } else {
                    expected = (style.size, style.weight)
                }
                var look = TextLook()
                look.textStyle = .headline
                let image = WinUIImageView()
                image.apply(source: .symbol("\u{E8B7}"), aspect: .center, font: look)
                XCTAssertTrue(image.found)
                XCTAssertEqual(image.measure(width: nil, height: nil).height, style.size)
            }
            XCTAssertLessThanOrEqual(swiftomniui_winui_font_probes() - before, 1,
                                     "200 font applications share one native style reader")
            let explicit = WinUITextView()
            explicit.setFont(size: 21, attributes: .italic, family: nil, textStyle: .headline, weight: 650)
            XCTAssertEqual(explicit.wordsStyle.size, 21)
            XCTAssertEqual(explicit.wordsStyle.weight, 650)
            explicit.setFont(size: nil, attributes: nil, family: nil, textStyle: .headline)
            let system = try XCTUnwrap(expected)
            XCTAssertEqual(explicit.wordsStyle.size, system.size)
            XCTAssertEqual(explicit.wordsStyle.weight, system.weight)
        }
    }
}
