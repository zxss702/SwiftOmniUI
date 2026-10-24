// SPDX-License-Identifier: Apache-2.0
import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

final class WinUITextSpacingTests: XCTestCase {
    func testRepeatedPreparationDoesNotReprobeSpacedParagraph() {
        onUIThread {
            let label = WinUITextView()
            label.setTextFont(size: 18, attributes: nil, family: nil)
            label.setText("alpha beta gamma delta 中文内容自动换行")
            label.setLineSpacing(12)
            let before = swiftomniui_winui_text_spacing_probes()
            label.prepareMeasure(width: 90)
            let narrow = label.desiredSize
            label.prepareMeasure(width: 900)
            let wide = label.desiredSize
            XCTAssertGreaterThan(narrow.height, wide.height)
            let prepared = swiftomniui_winui_text_spacing_probes()
            XCTAssertEqual(prepared - before, 2)
            // Parent measurement and destination preparation revisit both
            // widths, with different height constraints, during scrolling.
            for _ in 0..<30 {
                label.prepareMeasure(width: 90)
                XCTAssertEqual(label.desiredSize, narrow)
                label.prepareMeasure(width: 90, height: narrow.height)
                label.prepareMeasure(width: 900)
                XCTAssertEqual(label.desiredSize, wide)
            }
            XCTAssertEqual(swiftomniui_winui_text_spacing_probes(), prepared,
                           "unchanged paragraphs must not toggle MaxLines during every preparation")
        }
    }

    func testFirstMeasureResolvesSpacingWithoutAttachmentSelectionOrScroll() throws {
        onUIThread {
            let label = WinUITextView()
            label.setTextFont(size: 18, attributes: nil, family: nil)
            label.setText("first\nsecond")
            let natural = swiftomniui_winui_text_natural_line_height(label.handle)
            label.setLineSpacing(24)
            // No renderer, Loaded, text geometry, message pump or scroll.
            let measured = label.measure(width: 300, height: nil)
            XCTAssertEqual(measured.height, 2 * natural + 24, accuracy: 1)
            XCTAssertEqual(Self.lineHeight(label), natural + 24, accuracy: 1)

            label.setText("single")
            XCTAssertEqual(label.measure(width: 300, height: nil).height, natural, accuracy: 1)
            XCTAssertEqual(Self.lineHeight(label), 0)

            label.setText("alpha beta gamma delta")
            XCTAssertGreaterThan(label.measure(width: 70, height: nil).height, 2 * natural)
            XCTAssertGreaterThan(Self.lineHeight(label), 24)
            XCTAssertEqual(label.measure(width: 600, height: nil).height, natural, accuracy: 1)
            XCTAssertEqual(Self.lineHeight(label), 0)
        }
    }

    func testSpacingDecisionsFollowTypographyRunsAndLineLimits() {
        onUIThread {
            let label = WinUILabelView()
            label.setTextFont(size: 18, attributes: nil, family: nil)
            label.setText("alpha beta gamma delta")
            label.setLineSpacing(12)
            label.prepareMeasure(width: 90)
            let wrapped = label.desiredSize.height
            label.setLines(breaking: .wordWrap, maximum: 1)
            label.prepareMeasure(width: 90)
            XCTAssertEqual(Self.lineHeight(label), 0)
            XCTAssertLessThan(label.desiredSize.height, wrapped)
            label.setLines(breaking: .wordWrap, maximum: nil)
            label.prepareMeasure(width: 90)
            XCTAssertEqual(label.desiredSize.height, wrapped)

            label.setRuns([TextRun(text: "one", look: TextLook())])
            label.prepareMeasure(width: 90)
            XCTAssertEqual(Self.lineHeight(label), 0)
            var large = TextLook()
            large.size = 60
            label.setRuns([TextRun(text: "one two three", look: large)])
            label.prepareMeasure(width: 90)
            XCTAssertGreaterThan(Self.lineHeight(label), 0)
            XCTAssertGreaterThan(label.desiredSize.height, wrapped)

            label.setRuns(nil)
            label.setTextFont(size: 24, attributes: nil, family: nil)
            label.setLineSpacing(20)
            label.prepareMeasure(width: 90)
            let natural = swiftomniui_winui_text_natural_line_height(label.handle)
            XCTAssertEqual(Self.lineHeight(label), natural + 20, accuracy: 1)
            let before = swiftomniui_winui_text_spacing_probes()
            label.invalidateNativeMeasure()
            label.prepareMeasure(width: 90)
            XCTAssertEqual(swiftomniui_winui_text_spacing_probes(), before + 1)
        }
    }

    @MainActor private static func lineHeight(_ label: WinUITextView) -> Double {
        var buffer = [CChar](repeating: 0, count: 64)
        _ = swiftomniui_winui_read(label.handle, "lineHeight", &buffer, Int32(buffer.count))
        return Double(String(cString: buffer)) ?? -1
    }

    @MainActor private static func geometry(_ label: WinUITextView) -> (lines: Int32, rects: [Rect]) {
        let length = label.text.utf16.count
        var values = [Double](repeating: 0, count: length * 4)
        var lines: Int32 = 0
        let read = swiftomniui_winui_text_character_geometry(label.handle, &values, Int32(length), &lines)
        guard read == length else { return (0, []) }
        return (lines, stride(from: 0, to: values.count, by: 4).map {
            Rect(values[$0], values[$0 + 1], values[$0 + 2], values[$0 + 3])
        }.filter { $0.height > 0 })
    }

    func testInheritedSpacingDoesNotEnlargeSeparateSingleLineTexts() throws {
        try onUIThread {
            let host = WinUIRenderer.running(reducesMotion: true) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) { Text("left"); Text("right") }
                    Text("single")
                    Text("con") + Text("catenated")
                }.font(.system(size: 18)).lineSpacing(24).frame(width: 400)
            }
            let labels = host.views(WinUILabelView.self)
            XCTAssertEqual(labels.count, 4)
            host.settle { labels.allSatisfy { Self.geometry($0).lines == 1 && Self.lineHeight($0) == 0 } }
            for label in labels {
                XCTAssertEqual(Self.geometry(label).lines, 1)
                XCTAssertEqual(Self.lineHeight(label), 0)
                XCTAssertEqual(label.laidOutFrame.height,
                               swiftomniui_winui_text_natural_line_height(label.handle), accuracy: 1)
            }
        }
    }

    func testConcatenatedTextUsesNativeWrapsAndLeavesGapsOutsideSelection() throws {
        try onUIThread {
            let width = State(wrappedValue: 400.0)
            let host = WinUIRenderer.running(reducesMotion: true) {
                (Text("alpha beta ").foregroundStyle(.red) + Text("gamma delta"))
                    .font(.system(size: 18)).lineSpacing(24).frame(width: width.wrappedValue)
            }
            let label = try XCTUnwrap(host.views(WinUILabelView.self).first)
            host.settle { Self.geometry(label).lines == 1 && Self.lineHeight(label) == 0 }
            XCTAssertEqual(Self.lineHeight(label), 0)

            width.wrappedValue = 90
            host.settle { Self.geometry(label).lines > 1 && Self.lineHeight(label) > 0 }
            let native = Self.geometry(label)
            XCTAssertGreaterThan(native.lines, 1)
            let first = try XCTUnwrap(native.rects.first)
            let next = try XCTUnwrap(native.rects.first { $0.y > first.y + first.height })
            XCTAssertEqual(next.y - first.y - first.height, 24, accuracy: 1)
            let natural = swiftomniui_winui_text_natural_line_height(label.handle)
            XCTAssertEqual(label.laidOutFrame.height,
                           Double(native.lines) * natural + Double(native.lines - 1) * 24, accuracy: 1)

            width.wrappedValue = 400
            host.settle { Self.geometry(label).lines == 1 && Self.lineHeight(label) == 0 }
            XCTAssertEqual(Self.geometry(label).lines, 1)
            XCTAssertEqual(Self.lineHeight(label), 0)
            XCTAssertEqual(label.laidOutFrame.height, natural, accuracy: 1)
        }
    }

    func testPlainTextAndExplicitNewlinesLeaveSelectionGaps() throws {
        try onUIThread {
            let host = WinUIRenderer.running(reducesMotion: true) {
                VStack(spacing: 0) {
                    Text("alpha beta gamma delta").frame(width: 90)
                    Text("first\nsecond").frame(width: 300)
                }.font(.system(size: 18)).lineSpacing(24)
            }
            let labels = host.views(WinUILabelView.self)
            XCTAssertEqual(labels.count, 2)
            host.settle { labels.allSatisfy { Self.geometry($0).lines > 1 && Self.lineHeight($0) > 0 } }
            for label in labels {
                let native = Self.geometry(label)
                let first = try XCTUnwrap(native.rects.first)
                let next = try XCTUnwrap(native.rects.first { $0.y > first.y + first.height })
                XCTAssertEqual(next.y - first.y - first.height, 24, accuracy: 1)
            }
            XCTAssertEqual(Self.geometry(try XCTUnwrap(labels.last)).lines, 2)
        }
    }
}
