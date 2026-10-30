// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

final class WinUIFontTests: XCTestCase {
    func testClosingAReplayHandleKeepsTheOriginalFontUsable() throws {
        try onUIThread {
            let path = (ProcessInfo.processInfo.environment["WINDIR"] ?? "C:/Windows") + "/Fonts/segoeui.ttf"
            var units = 0.0
            let original = try XCTUnwrap(swiftomniui_winui_font_open(path, &units))
            defer { swiftomniui_winui_font_close(original) }
            let glyph = swiftomniui_winui_font_glyph(original, 0x46)
            for _ in 0..<5 {
                var replayUnits = 0.0
                let replay = try XCTUnwrap(swiftomniui_winui_font_open(path, &replayUnits))
                XCTAssertEqual(replayUnits, units)
                XCTAssertEqual(swiftomniui_winui_font_glyph(replay, 0x46), glyph)
                swiftomniui_winui_font_close(replay)
                XCTAssertEqual(swiftomniui_winui_font_glyph(original, 0x46), glyph)
            }
        }
    }

    func testFileGlyphRasterizationKeepsBaselineColourAndTransparentAntialiasing() throws {
        try onUIThread {
            let path = (ProcessInfo.processInfo.environment["WINDIR"] ?? "C:/Windows") + "/Fonts/segoeui.ttf"
            var units = 0.0
            let font = try XCTUnwrap(swiftomniui_winui_font_open(path, &units))
            defer { swiftomniui_winui_font_close(font) }
            let glyph = swiftomniui_winui_font_glyph(font, 0x46) // F: distinguish top from bottom.
            XCTAssertNotEqual(glyph, 0)
            var metrics = [Double](repeating: 0, count: 5)
            XCTAssertTrue(swiftomniui_winui_font_metrics(font, glyph, &metrics))

            let size = 24.0, baseline = 32.0, rasterScale = 4.0
            let pixels = try XCTUnwrap(WinUICanvasView.bitmap(size: Size(64, 48), scale: rasterScale, drawing: [
                Draw.fillColor(Color("#FF0000")),
                Draw.saveState(),
                Draw.translate(dx: 8, dy: baseline),
                Draw.scale(sx: 1, sy: -1),
                Draw.fontGlyph(path: path, glyph: glyph, size: size),
                Draw.restoreState(),
                Draw.fillColor(Color("#0000FF")),
                Draw.fillRectangle(x: 48, y: 40, width: 4, height: 4),
            ]))
            var minY = pixels.height, maxY = -1, partialAlpha = false
            for y in 0..<pixels.height {
                for x in 0..<Int(40 * rasterScale) {
                    let at = (y * pixels.width + x) * 4
                    let alpha = pixels.rgba[at + 3]
                    guard alpha > 0 else { continue }
                    minY = min(minY, y); maxY = max(maxY, y)
                    partialAlpha = partialAlpha || alpha < 255
                    XCTAssertEqual(pixels.rgba[at], alpha, "Glyph colour stays premultiplied red")
                    XCTAssertEqual(pixels.rgba[at + 1], 0)
                    XCTAssertEqual(pixels.rgba[at + 2], 0, "Grayscale AA must not add coloured ClearType fringes")
                }
            }
            XCTAssertTrue(partialAlpha)
            let expectedTop = (baseline - (metrics[2] + metrics[4]) * size / units) * rasterScale
            let expectedBottom = (baseline - metrics[2] * size / units) * rasterScale
            XCTAssertEqual(Double(minY), expectedTop, accuracy: 2)
            XCTAssertEqual(Double(maxY + 1), expectedBottom, accuracy: 2)
            let after = (Int(42 * rasterScale) * pixels.width + Int(50 * rasterScale)) * 4
            XCTAssertEqual(Array(pixels.rgba[after..<(after + 4)]), [0, 0, 255, 255],
                           "The glyph's axis conversion must not affect the following shape")
            XCTAssertEqual(pixels.rgba[3], 0, "The formula background remains transparent")
        }
    }

    func testTextAndSymbolsReuseTheSystemStyleReaderAcrossRepeatedRows() throws {
        try onUIThread {
            let before = swiftomniui_winui_font_probes()
            var expected: (size: Double, weight: Int)?
            for _ in 0..<100 {
                let label = WinUITextView()
                var labelLook = TextLook()
                labelLook.textStyle = .headline
                label.setTextFont(labelLook)
                let style = label.wordsStyle
                XCTAssertEqual(label.look.size, style.size,
                               "the setter returns the resolved native style size")
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
            XCTAssertEqual(explicit.setFont(size: 21, attributes: .italic, family: nil,
                                           textStyle: .headline, weight: 650), 21)
            XCTAssertEqual(explicit.wordsStyle.size, 21)
            XCTAssertEqual(explicit.wordsStyle.weight, 650)
            let system = try XCTUnwrap(expected)
            XCTAssertEqual(explicit.setFont(size: nil, attributes: nil, family: nil, textStyle: .headline), system.size)
            XCTAssertEqual(explicit.wordsStyle.size, system.size)
            XCTAssertEqual(explicit.wordsStyle.weight, system.weight)
        }
    }
}
