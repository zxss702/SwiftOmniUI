// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

/// One label, its words in spans until a button takes them away.
private struct SpannedPage: View {
    @State private var spanned = true

    var body: some View {
        VStack {
            if spanned {
                Text("own").spans { TextSpan("runs") }.id("words")
            } else {
                Text("own").id("words")
            }
            Button("Plain").onClicked { spanned = false }
        }
    }
}

@MainActor private final class AttachmentMeasuredText: WinUITextView {
    var queries = 0
    override var cachesIntrinsicMeasurements: Bool { true }
    override func measure(width: Double?, height: Double?) -> LayoutSize {
        queries += 1
        return super.measure(width: width, height: height)
    }
}

final class WinUILabelViewTests: XCTestCase {
    func testAttachmentRefreshKeepsProposalsAlreadyMeasuredInTheLiveTree() throws {
        onUIThread {
            let host = WinUIRenderer.bare(reducesMotion: true)
            let text = AttachmentMeasuredText()
            text.setTextFont(size: 14, attributes: nil, family: nil)
            text.setText("A filename with enough words to wrap differently at each width")
            let detached = text.measure(width: 80, height: nil)
            WinUITestHost.window.show(text)
            for _ in 0..<4 { host.step() }
            XCTAssertTrue(text.isAttached)
            let wide = text.measure(width: 240, height: nil)
            let narrow = text.measure(width: 60, height: nil)
            XCTAssertGreaterThan(narrow.height, wide.height)
            let before = text.queries
            XCTAssertFalse(text.refreshMeasurementsAfterAttachment())
            XCTAssertEqual(text.queries, before,
                           "Loaded must not repeat proposals already measured after attachment")
            // Explicit revalidation remains available to newly attached inline
            // paragraphs, even while their enclosing Border stays loaded.
            XCTAssertFalse(text.refreshMeasurementsAfterAttachment(includingAttached: true))
            XCTAssertGreaterThan(text.queries, before)
            XCTAssertEqual(text.measure(width: 80, height: nil), detached)
            WinUITestHost.window.show(nil)
        }
    }

    func testAnActuallyNarrowLabelStillUsesNativeEllipsis() throws {
        try onUIThread {
            let host = WinUIRenderer.running(reducesMotion: true) {
                Text("负责人").lineLimit(1).frame(width: 14)
            }
            let label = try XCTUnwrap(host.views(WinUILabelView.self).first)
            var result = [CChar](repeating: 0, count: 8)
            let count = swiftomniui_winui_read(label.handle, "isTextTrimmed", &result, Int32(result.count))
            XCTAssertEqual(count, 1)
            XCTAssertEqual(result[0], 49, "a genuinely constrained label still reports native trimming")
        }
    }

    func testForegroundPatchDoesNotReadOrResetTypography() throws {
        try onUIThread {
            let host = WinUIRenderer.running { Text("words") }
            let label = try XCTUnwrap(host.views(WinUILabelView.self).first)
            label.setTextFont(size: 23, attributes: .bold, family: nil)
            let revision = label.measurementRevision
            let foreground = TextStyleElementContract.foregroundStyle.token
            var reads: Set<Prop> = []
            let values = ElementValues<TextContract>(changed: [foreground], reading: { key in
                reads.insert(key)
                return key == foreground ? Brush.solidColor(Color("#FF0000")).propValue : nil
            })

            WinUIRegistrations.applyText(label, values)

            XCTAssertEqual(reads, [foreground])
            XCTAssertEqual(label.wordsStyle.size, 23)
            XCTAssertEqual(label.wordsStyle.weight, 700)
            XCTAssertEqual(label.wordsStyle.color, 0xFFFF0000)
            XCTAssertEqual(label.measurementRevision, revision)

            // Updating a different property group must preserve the installed brush.
            let font = ElementValues<TextContract>(changed: [FontElementContract.fontSize.token], reading: { key in
                key == FontElementContract.fontSize.token ? 31.0.propValue : nil
            })
            WinUIRegistrations.applyText(label, font)
            XCTAssertEqual(label.wordsStyle.size, 31)
            XCTAssertEqual(label.wordsStyle.color, 0xFFFF0000)
        }
    }

    func testUnchangedAndRecoloredRunsKeepTheirMeasurement() throws {
        try onUIThread {
            let host = WinUIRenderer.running { Text("own") }
            let label = try XCTUnwrap(host.views(WinUILabelView.self).first)
            var look = TextLook()
            look.color = Color("#FF0000").propValue
            look.background = Color("#FFFF00").propValue
            let original = [TextRun(text: "中文🙂", look: look), TextRun(text: " tail", look: TextLook())]
            label.setRuns(original)
            let revision = label.measurementRevision
            label.setRuns(original)
            XCTAssertEqual(label.measurementRevision, revision)

            look.color = Color("#0000FF").propValue
            look.background = Color("#00FF00").propValue
            label.setRuns([TextRun(text: "中文🙂", look: look), original[1]])
            var native = [Double](repeating: 0, count: 12)
            XCTAssertEqual(swiftomniui_winui_text_runs(label.handle, &native, 12), 2)
            XCTAssertEqual(native[0], Double(0xFF0000FF as UInt32))
            XCTAssertEqual(native[5], Double(0xFF00FF00 as UInt32))
            XCTAssertEqual(label.text, "中文🙂 tail")
            XCTAssertEqual(label.measurementRevision, revision)

            look.color = nil
            look.background = nil
            label.setRuns([TextRun(text: "中文🙂", look: look), original[1]])
            _ = swiftomniui_winui_text_runs(label.handle, &native, 12)
            XCTAssertEqual(native[0], 0, "removing span colour restores inheritance")
            XCTAssertEqual(native[5], 0, "removing span background removes its highlighter")
            XCTAssertEqual(label.measurementRevision, revision)
        }
    }

    func testRunTextAndFontChangesStillInvalidateMeasurement() throws {
        try onUIThread {
            let host = WinUIRenderer.running { Text("own") }
            let label = try XCTUnwrap(host.views(WinUILabelView.self).first)
            label.setRuns([TextRun(text: "short", look: TextLook())])
            let beforeText = label.measurementRevision
            label.setRuns([TextRun(text: "a longer line", look: TextLook())])
            XCTAssertGreaterThan(label.measurementRevision, beforeText)
            XCTAssertEqual(label.text, "a longer line")

            var look = TextLook()
            look.size = 28
            let beforeFont = label.measurementRevision
            label.setRuns([TextRun(text: "a longer line", look: look)])
            XCTAssertGreaterThan(label.measurementRevision, beforeFont)
            var native = [Double](repeating: 0, count: 6)
            XCTAssertEqual(swiftomniui_winui_text_runs(label.handle, &native, 6), 1)
            XCTAssertEqual(native[1], 28)
        }
    }

    func testInheritedSpacingIsReencodedWhenTheBaseFontChanges() throws {
        try onUIThread {
            let host = WinUIRenderer.running { Text("own") }
            let label = try XCTUnwrap(host.views(WinUILabelView.self).first)
            let runs = [TextRun(text: "spaced", look: TextLook())]
            label.setTextFont(size: 14, attributes: nil, family: nil)
            label.setRuns(runs)
            label.setLetterSpacing(2)
            let beforeSpacing = label.measurementRevision
            label.setRuns(runs)
            XCTAssertGreaterThan(label.measurementRevision, beforeSpacing)
            label.setTextFont(size: 28, attributes: nil, family: nil)
            let beforeFont = label.measurementRevision
            label.setRuns(runs)
            XCTAssertGreaterThan(label.measurementRevision, beforeFont)
            let complete = label.measurementRevision
            label.setRuns(runs)
            XCTAssertEqual(label.measurementRevision, complete)
        }
    }

    func testRaisedInlineKeepsItsFullUpdatePath() throws {
        try onUIThread {
            let host = WinUIRenderer.running { Text("own") }
            let label = try XCTUnwrap(host.views(WinUILabelView.self).first)
            var look = TextLook()
            look.baselineOffset = 2
            label.setRuns([TextRun(text: "raised", look: look)])
            let revision = label.measurementRevision
            look.color = Color("#FF0000").propValue
            label.setRuns([TextRun(text: "raised", look: look)])
            XCTAssertGreaterThan(label.measurementRevision, revision)
        }
    }

    /// A label with nothing said stands as WinUI's own body text, in the color scheme's colour.
    func testALabelWithNothingSaidIsWinUIsOwnText() throws {
        try onUIThread {
            let host = WinUIRenderer.running { VStack { Text("plain") } }
            let style = try XCTUnwrap(host.views(WinUILabelView.self).first).wordsStyle

            XCTAssertEqual(style.size, WinUITextView.platformFontSize)
            XCTAssertEqual(style.weight, 400)
        }
    }

    /// A label whose spans are taken away shows its own words again.
    func testALabelWithoutItsSpansShowsItsOwnWords() throws {
        try onUIThread {
            let host = WinUIRenderer.running { SpannedPage() }
            let label = try XCTUnwrap(host.views(WinUILabelView.self).first)
            XCTAssertEqual(label.text, "runs")

            try XCTUnwrap(host.views(WinUIButtonView.self).first).invoke()

            XCTAssertTrue(host.views(WinUILabelView.self).first === label, "the same label, its spans gone")
            XCTAssertEqual(label.text, "own")
        }
    }
}
