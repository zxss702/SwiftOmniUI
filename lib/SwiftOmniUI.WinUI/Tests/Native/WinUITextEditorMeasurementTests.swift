// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import SwiftOmniUIConformance
import XCTest

final class WinUITextEditorMeasurementTests: XCTestCase {
    func testFocusedEditorKeepsSOUIHeightOwnershipAcrossNativeSizeChangedDelivery() throws {
        try onUIThread {
            let height = State(wrappedValue: 40.0)
            let clock = TestClock()
            let host = WinUIRenderer.running(clock: clock) {
                TextEditor("Editable text")
                    .safeAreaPadding(.vertical, 12)
                    .frame(height: height.wrappedValue)
                    .id("height-owner")
            }
            let editor = try XCTUnwrap(host.views(WinUITextEditorView.self).first)
            let input = try XCTUnwrap(host.view(id: .manual("height-owner")))
            XCTAssertTrue(swiftomniui_winui_focus(editor.handle, true))
            editor.select(start: 1, length: 3)
            for target in [128.0, 40, 128] {
                let began = clock.now
                withAnimation(.eased(200, .linear)) { height.wrappedValue = target }
                host.step()
                for elapsed in [0.0, 16, 50, 100, 150, 200] {
                    clock.now = began + elapsed
                    host.frame()
                    let expected = try XCTUnwrap(input.sourceElement?.number(.height)) - 24
                    // SizeChanged runs as XAML delivers layout, outside the
                    // synchronous Arrange call. TextBox must see a finite
                    // Height there, or it launches an independent storyboard.
                    XCTAssertEqual(swiftomniui_winui_editor_allocated_height(editor.handle), expected, accuracy: 0.001)
                    XCTAssertEqual(editor.laidOutFrame.height, expected, accuracy: 0.001)
                    XCTAssertEqual(editor.laidOutFrame.y, 0, accuracy: 0.001)
                    XCTAssertEqual(editor.controlFrame.height, expected, accuracy: 0.001)
                    XCTAssertEqual(editor.controlFrame.y, 0, accuracy: 0.001)
                    XCTAssertTrue(swiftomniui_winui_focused(editor.handle))
                    var facts = [Int32](repeating: -1, count: 9)
                    swiftomniui_winui_field_facts(editor.handle, &facts)
                    XCTAssertEqual(Array(facts[5...6]), [1, 3])
                }
            }
            XCTAssertFalse(host.runtime.animator.isMoving)
        }
    }

    func testReplayedMeasureDoesNotReplaceTheEditorsFinalAllocation() throws {
        try onUIThread {
            let host = WinUIRenderer.running { TextEditor("Text").frame(width: 240, height: 128) }
            let editor = try XCTUnwrap(host.views(WinUITextEditorView.self).first)
            let parent = try XCTUnwrap(editor.placingLayout)
            XCTAssertTrue(swiftomniui_winui_focus(editor.handle, true))
            for (width, height) in [(220.0, 16.0), (268, 29.021526), (220, 82.93654),
                                    (268, 104), (220, 45.69025), (268, 16)] {
                parent.withNativeArrange { editor.layout(Rect(0, 0, width, height)) }
                let allocated = editor.controlFrame
                // XAML can replay the previous Measure constraint while
                // retaining a newer final rectangle. It must not prepare the
                // internal TextBox at that unrelated proposal.
                editor.prepareMeasure(width: width - 48, height: 128)
                XCTAssertEqual(editor.controlFrame, allocated)
                XCTAssertEqual(editor.desiredSize, LayoutSize(width: 0, height: 0))
                parent.withNativeArrange { editor.layout(Rect(0, 0, width, height)) }
                XCTAssertEqual(swiftomniui_winui_editor_allocated_height(editor.handle), height, accuracy: 0.001)
                XCTAssertEqual(editor.laidOutFrame.height, height, accuracy: 0.001)
                XCTAssertEqual(editor.laidOutFrame.width, width, accuracy: 0.001)
                XCTAssertEqual(editor.laidOutFrame.y, 0, accuracy: 0.001)
                XCTAssertEqual(editor.controlFrame.width, width, accuracy: 0.001)
                XCTAssertEqual(editor.controlFrame.height, height, accuracy: 0.001)
                // Natural size questions retain the selected native Height.
                _ = WinUILayoutView.querySize { editor.measure(width: 40, height: nil) }
                XCTAssertEqual(swiftomniui_winui_editor_allocated_height(editor.handle), height, accuracy: 0.001)
            }
        }
    }

    func testArithmeticQueriesNeverReplaceTheLiveEditorsPreparedMeasure() throws {
        try onUIThread {
            let host = WinUIRenderer.running { TextEditor("A long editor line and more words").frame(width: 240, height: 128) }
            let editor = try XCTUnwrap(host.views(WinUITextEditorView.self).first)
            XCTAssertTrue(swiftomniui_winui_focus(editor.handle, true))
            editor.select(start: 2, length: 4)
            editor.prepareMeasure(width: 240, height: 104)
            let nativeDesired = editor.desiredSize
            for growing in [false, true] {
                editor.growsWithText = growing
                // The policy setter invalidates measurement, so prepare its
                // actual native slot before probing the alternate proposals.
                editor.prepareMeasure(width: 240, height: 104)
                let prepared = editor.desiredSize
                let revision = editor.measurementRevision
                XCTAssertGreaterThan(editor.measure(width: nil, height: 104).width, 0,
                                     "a pure query retains the words' unconstrained ideal width")
                for width in [nil, 40.0, 480, 240] as [Double?] {
                    for height in [nil, 16.0, 128] as [Double?] {
                        _ = WinUILayoutView.querySize { editor.measure(width: width, height: height) }
                        XCTAssertEqual(editor.desiredSize, prepared,
                                       "an arithmetic question must not change XAML's prepared Measure result")
                        XCTAssertEqual(editor.measurementRevision, revision)
                    }
                }
                swiftomniui_winui_arrange(editor.presentationHandle, 0, 0, 240, 104)
                XCTAssertEqual(editor.laidOutFrame.height, 104, accuracy: 1)
                XCTAssertEqual(editor.controlFrame.height, 104, accuracy: 1)
                XCTAssertEqual(editor.text, "A long editor line and more words")
                XCTAssertTrue(swiftomniui_winui_focused(editor.handle))
                var facts = [Int32](repeating: -1, count: 9)
                swiftomniui_winui_field_facts(editor.handle, &facts)
                XCTAssertEqual(Array(facts[5...6]), [2, 4])
            }
            XCTAssertEqual(nativeDesired, LayoutSize(width: 0, height: 0))
        }
    }

    func testNewConversationFirstInputKeepsItsExpandedHeightWhileControlsReflow() throws {
        try onUIThread {
            let words = State(wrappedValue: "")
            let clock = TestClock()
            let host = WinUIRenderer.running(clock: clock) {
                ScrollView { Text("New conversation") }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        HStack(alignment: .bottom) {
                            Button("Attach") {}.frame(width: 40, height: 40)
                            ZStack(alignment: .bottom) {
                                TextEditor(words.projectedValue.transaction(.init(animation: .snappy)))
                                    .scrollContentBackground(.hidden)
                                    .background(alignment: .topLeading) {
                                        if words.wrappedValue.isEmpty {
                                            Text("Placeholder for a new conversation").padding(.top, 1).padding(.leading, 4)
                                        }
                                    }
                                    .animation(nil, value: words.wrappedValue.isEmpty)
                                    .safeAreaPadding(.vertical, 12)
                                    .safeAreaPadding(.leading, 12)
                                    .frame(height: 128)
                                    .background {
                                        RoundedRectangle(cornerRadius: 20).fill(Color.white).id("new-fill")
                                    }
                                    .contentShape(RoundedRectangle(cornerRadius: 20))
                                Rectangle().fill(Color.clear).frame(height: 16).offset(y: -120)
                            }.frame(height: 128).id("new-composer")
                            if words.wrappedValue.isEmpty {
                                HStack {
                                    Button("Send") {}.frame(width: 40, height: 40).id("new-send")
                                    Button("Pause") {}.frame(width: 40, height: 40).id("new-pause")
                                }
                            } else {
                                VStack {
                                    Button("Send") {}.frame(width: 40, height: 40).id("new-send")
                                    Button("Pause") {}.frame(width: 40, height: 40).id("new-pause")
                                }
                            }
                        }
                        .transition(.blur.combined(with: .offset(x: 0, y: 128)).animation(.snappy))
                        .padding(16).buttonStyle(.plain).id("new-composer-row")
                    }
            }
            let editor = try XCTUnwrap(host.views(WinUITextEditorView.self).first)
            let composer = try XCTUnwrap(host.view(id: .manual("new-composer")))
            let row = try XCTUnwrap(host.view(id: .manual("new-composer-row")))
            let fill = try XCTUnwrap(host.view(id: .manual("new-fill")))
            let emptyWidth = composer.laidOutFrame.width
            let bottom = composer.origin.y + composer.laidOutFrame.height
            for text in ["a", "more input", "", "again"] {
                editor.type(text)
                host.step()
                let began = clock.now
                for elapsed in [0.0, 16, 50, 100, 200, 400, 800, 1600] {
                    clock.now = began + elapsed
                    host.frame()
                    XCTAssertEqual(composer.laidOutFrame.height, 128, accuracy: 1)
                    XCTAssertEqual(composer.origin.y + composer.laidOutFrame.height, bottom, accuracy: 1)
                    XCTAssertEqual(editor.laidOutFrame.height, 104, accuracy: 1)
                    XCTAssertEqual(editor.controlFrame.height, 104, accuracy: 1)
                    XCTAssertEqual(swiftomniui_winui_editor_allocated_height(editor.handle), 104, accuracy: 0.001)
                    XCTAssertGreaterThan(editor.laidOutFrame.width, 40)
                    XCTAssertGreaterThan(composer.laidOutFrame.width, 52)
                    XCTAssertEqual(fill.committedFrame?.width ?? -1, composer.laidOutFrame.width, accuracy: 0.001,
                                   "the rounded background must cover this sample's full input allocation")
                    XCTAssertEqual(fill.committedFrame?.height ?? -1, 128, accuracy: 0.001)
                    XCTAssertEqual(editor.laidOutFrame.width, composer.laidOutFrame.width - 12, accuracy: 1,
                                   "native width must follow the currently allocated composer, including animation samples")
                    XCTAssertEqual(editor.controlFrame.width, editor.laidOutFrame.width, accuracy: 0.001)
                    XCTAssertTrue(host.views(WinUITextEditorView.self).first === editor)
                    XCTAssertEqual(host.views(WinUITextEditorView.self).count, 1)
                    XCTAssertEqual(editor.text, text)
                    for identity in ["new-send", "new-pause"] {
                        let button = try XCTUnwrap(host.view(id: .manual(identity)))
                        XCTAssertEqual(button.laidOutFrame.width, 40, accuracy: 1)
                        XCTAssertEqual(button.laidOutFrame.height, 40, accuracy: 1)
                        XCTAssertGreaterThanOrEqual(button.origin.x, row.origin.x - 1)
                        XCTAssertLessThanOrEqual(button.origin.x + button.laidOutFrame.width,
                                                 row.origin.x + row.laidOutFrame.width + 1)
                        XCTAssertGreaterThanOrEqual(button.origin.y, row.origin.y - 1)
                        XCTAssertLessThanOrEqual(button.origin.y + button.laidOutFrame.height,
                                                 row.origin.y + row.laidOutFrame.height + 1)
                    }
                }
                XCTAssertEqual(composer.laidOutFrame.width, emptyWidth + (text.isEmpty ? 0 : 48), accuracy: 1,
                               "the editor must receive the width released by changing two buttons from a row to a column")
                let send = try XCTUnwrap(host.view(id: .manual("new-send")))
                XCTAssertEqual(send.origin.x - (composer.origin.x + composer.laidOutFrame.width), 8, accuracy: 1,
                               "a fixed-height composer must close the old controls' horizontal space")
                // The 48 DIP strip released by the old HStack must be painted,
                // rather than merely included in the TextBox's logical frame.
                let window = try XCTUnwrap(host.window)
                host.settle {
                    fill.presentedPixels(at: [(composer.laidOutFrame.width - 2, 64)], in: window) == [0xFFFF_FFFF]
                }
                XCTAssertEqual(fill.presentedPixels(at: [(composer.laidOutFrame.width - 2, 64)], in: window), [0xFFFF_FFFF])
            }
        }
    }

    func testNestedComposerUsesOneHeightThroughExpansionReversalAndEmptyInput() throws {
        try onUIThread {
            let words = State(wrappedValue: "")
            let emptySession = State(wrappedValue: false)
            let clock = TestClock()
            let host = WinUIRenderer.running(clock: clock) {
                let height = !words.wrappedValue.isEmpty || emptySession.wrappedValue ? 128.0 : 40.0
                return ScrollView { Text("Conversation") }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        HStack(alignment: .bottom) {
                            Button("Attach") {}.frame(width: 40, height: 40)
                            ZStack(alignment: .bottom) {
                                TextEditor(words.projectedValue)
                                    .scrollContentBackground(.hidden)
                                    .background(alignment: .topLeading) {
                                        if emptySession.wrappedValue && words.wrappedValue.isEmpty {
                                            Text("Placeholder").padding(.top, 1).padding(.leading, 4)
                                        }
                                    }
                                    .animation(nil, value: emptySession.wrappedValue && words.wrappedValue.isEmpty)
                                    .safeAreaPadding(.vertical, 12)
                                    .safeAreaPadding(.leading, 12)
                                    .frame(height: height)
                                    .background { RoundedRectangle(cornerRadius: 20).fill(Color.white).id("nested-fill") }
                                    .clipShape(RoundedRectangle(cornerRadius: 20))
                                Rectangle().fill(Color.clear).frame(height: 16).offset(y: -height + 8)
                            }
                            .frame(height: height).id("nested-input")
                            if words.wrappedValue.isEmpty {
                                HStack {
                                    Button("Send") {}.frame(width: 40, height: 40)
                                    Button("Pause") {}.frame(width: 40, height: 40)
                                }
                            } else {
                                VStack {
                                    Button("Send") {}.frame(width: 40, height: 40)
                                    Button("Pause") {}.frame(width: 40, height: 40)
                                }
                            }
                        }.padding(16).buttonStyle(.plain).id("nested-row")
                    }
            }
            let editor = try XCTUnwrap(host.views(WinUITextEditorView.self).first)
            let input = try XCTUnwrap(host.view(id: .manual("nested-input")))
            let fill = try XCTUnwrap(host.view(id: .manual("nested-fill")))
            XCTAssertEqual(input.laidOutFrame.height, 40, accuracy: 1)
            XCTAssertEqual(editor.laidOutFrame.height, 16, accuracy: 1)
            let bottom = input.origin.y + input.laidOutFrame.height
            XCTAssertTrue(swiftomniui_winui_focus(editor.handle, true))

            // Reverse the first expansion halfway, then complete both directions.
            for (value, through) in [("a", 100.0), ("", 200), ("again", 200), ("", 200)] {
                let start = input.laidOutFrame.height
                let target = value.isEmpty ? 40.0 : 128.0
                let began = clock.now
                withAnimation(.eased(200, .linear)) { words.wrappedValue = value }
                host.step()
                for elapsed in [0.0, 16, 50, 100, 150, 200] where elapsed <= through {
                    clock.now = began + elapsed
                    host.frame()
                    // A reversal carries velocity and can follow a Hermite
                    // segment. Geometry must follow the presented property,
                    // rather than adding another placement curve to it.
                    let expected = try XCTUnwrap(input.sourceElement?.number(.height))
                    if elapsed == 0 { XCTAssertEqual(expected, start, accuracy: 1) }
                    if elapsed == 200 { XCTAssertEqual(expected, target, accuracy: 1) }
                    XCTAssertEqual(editor.laidOutFrame.height, expected - 24, accuracy: 1,
                                   "the first frame must already have the right native allocation")
                    for _ in 0..<3 {
                        host.layOut()
                        XCTAssertEqual(input.laidOutFrame.height, expected, accuracy: 1)
                        XCTAssertEqual(fill.committedFrame?.height ?? -1, expected, accuracy: 1)
                        XCTAssertEqual(editor.laidOutFrame.height, expected - 24, accuracy: 1,
                                       "the native control must honor the padded slot, including an empty 16 DIP slot")
                        XCTAssertEqual(input.origin.y + input.laidOutFrame.height, bottom, accuracy: 1)
                    }
                    XCTAssertTrue(host.views(WinUITextEditorView.self).first === editor)
                    XCTAssertTrue(swiftomniui_winui_focused(editor.handle))
                }
            }
            XCTAssertFalse(host.runtime.animator.isMoving)
            emptySession.wrappedValue = true
            host.step()
            host.layOut()
            XCTAssertEqual(input.laidOutFrame.height, 128, accuracy: 1,
                           "an empty session keeps its expanded editor even with empty text")
            XCTAssertEqual(editor.laidOutFrame.height, 104, accuracy: 1)
            XCTAssertTrue(host.views(WinUITextEditorView.self).first === editor)
        }
    }

    func testNativeEditorHonorsShortAllocationsWithoutStockTextBoxChrome() throws {
        try onUIThread {
            let host = WinUIRenderer.running { TextEditor("").frame(width: 240, height: 128) }
            let editor = try XCTUnwrap(host.views(WinUITextEditorView.self).first)
            for focused in [false, true, false] {
                _ = swiftomniui_winui_focus(editor.handle, focused)
                for text in ["", "Text\nSecond line", ""] {
                    editor.setText(text)
                    for height in [16.0, 40, 104, 128, 16] {
                        editor.prepareMeasure(width: 220, height: height)
                        swiftomniui_winui_arrange(editor.presentationHandle, 7, 9, 220, height)
                        XCTAssertLessThanOrEqual(editor.desiredSize.height, height)
                        XCTAssertEqual(editor.laidOutFrame.width, 220, accuracy: 0.01)
                        XCTAssertEqual(editor.laidOutFrame.height, height, accuracy: 0.01,
                                       "DesiredSize alone does not detect a native minimum that enlarges ActualSize")
                        XCTAssertEqual(editor.controlFrame.height, height, accuracy: 0.01)
                        XCTAssertEqual(editor.controlFrame.width, 220, accuracy: 0.01)
                        XCTAssertEqual(editor.laidOutFrame.x, 7, accuracy: 0.01)
                        XCTAssertEqual(editor.laidOutFrame.y, 9, accuracy: 0.01)
                    }
                }
            }
        }
    }

    func testComposerIntermediateFramesShareOneHeightAndBottomEdge() throws {
        try onUIThread {
            let words = State(wrappedValue: "")
            let clock = TestClock()
            let host = WinUIRenderer.running(clock: clock) {
                ScrollView { Text("Conversation") }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        HStack(alignment: .bottom) {
                            Button("Attach") {}.frame(width: 40, height: 40)
                            TextEditor(words.projectedValue)
                                .scrollContentBackground(.hidden)
                                .frame(height: words.wrappedValue.isEmpty ? 40 : 128)
                                .background { RoundedRectangle(cornerRadius: 20).fill(Color.white).id("fill") }
                                .id("input")
                            if words.wrappedValue.isEmpty {
                                HStack {
                                    Button("Send") {}.frame(width: 40, height: 40)
                                    Button("Pause") {}.frame(width: 40, height: 40)
                                }
                            } else {
                                VStack {
                                    Button("Send") {}.frame(width: 40, height: 40)
                                    Button("Pause") {}.frame(width: 40, height: 40)
                                }
                            }
                        }.padding(16).buttonStyle(.plain)
                    }
            }
            let input = try XCTUnwrap(host.view(id: .manual("input")))
            let nativeEditor = try XCTUnwrap(host.views(WinUITextEditorView.self).first)
            let bottom = input.origin.y + input.laidOutFrame.height
            let began = clock.now
            withAnimation(.eased(200, .linear)) { words.wrappedValue = "a" }
            host.step()
            for elapsed in [0.0, 16, 32, 50, 100, 150, 200] {
                clock.now = began + elapsed
                host.frame()
                let expected = 40 + 88 * elapsed / 200
                let fill = try XCTUnwrap(host.view(id: .manual("fill")))
                XCTAssertEqual(input.laidOutFrame.height, expected, accuracy: 1)
                XCTAssertEqual(fill.laidOutFrame.height, expected, accuracy: 1)
                XCTAssertEqual(fill.committedFrame?.height ?? -1, expected, accuracy: 1)
                XCTAssertEqual(input.origin.y + input.laidOutFrame.height, bottom, accuracy: 1)
                XCTAssertTrue(host.views(WinUITextEditorView.self).first === nativeEditor)
                if elapsed == 50 {
                    // A content patch between geometry frames must not acquire
                    // another layout animation or restart the height channel.
                    words.wrappedValue = "additional content while expanding"
                    host.step()
                    host.layOut()
                    XCTAssertEqual(input.laidOutFrame.height, expected, accuracy: 1,
                                   "the content patch itself must not introduce an intermediate jump")
                    XCTAssertEqual(input.origin.y + input.laidOutFrame.height, bottom, accuracy: 1)
                }
            }
            XCTAssertFalse(host.runtime.animator.isMoving)
        }
    }

    func testScrollingEditorAsksForOneNativeLineWithoutAnAllocatedHeight() {
        onUIThread {
            let editor = WinUITextEditorView()
            let empty = editor.measure(width: 180, height: nil)
            editor.setText(Array(repeating: "中文 and words", count: 30).joined(separator: "\n"))
            let full = editor.measure(width: 180, height: nil)
            XCTAssertGreaterThan(empty.height, 0)
            XCTAssertEqual(full.height, empty.height, accuracy: 1,
                           "a scrolling editor's contents do not choose its intrinsic height")

            editor.setFont(size: 36, attributes: nil, family: nil)
            let large = editor.measure(width: 180, height: nil)
            XCTAssertGreaterThan(large.height, empty.height,
                                 "the minimum comes from the native font, not a fixed DIP constant")
            XCTAssertEqual(editor.measure(width: 180, height: .infinity).height, large.height, accuracy: 1)
        }
    }

    func testFiniteEditorHeightSurvivesAlternatingIntrinsicQueries() {
        onUIThread {
            let editor = WinUITextEditorView()
            editor.setText(Array(repeating: "A line of text", count: 30).joined(separator: "\n"))
            let intrinsic = editor.measure(width: 220, height: nil)
            for height in [40.0, 128, 72, 128, 40] {
                let allocated = editor.measure(width: 220, height: height)
                XCTAssertEqual(allocated.height, height, accuracy: 1,
                               "the finite proposal must reach XAML unchanged")
                XCTAssertEqual(editor.measure(width: 220, height: nil).height, intrinsic.height, accuracy: 1)
                editor.growsWithText = true
                XCTAssertEqual(editor.measure(width: 220, height: height).height, allocated.height, accuracy: 1)
                editor.growsWithText = false
            }
            editor.growsWithText = true
            XCTAssertGreaterThan(editor.measure(width: 220, height: nil).height, intrinsic.height)
        }
    }

    func testExplicitZeroHeightIsAnAllocationRatherThanAnIntrinsicQuery() {
        onUIThread {
            let editor = WinUITextEditorView()
            editor.setText("First\nSecond\nThird")
            for growing in [false, true] {
                editor.growsWithText = growing
                XCTAssertEqual(editor.measure(width: 220, height: 0).height, 0)
                XCTAssertGreaterThan(editor.measure(width: 220, height: nil).height, 0)
                XCTAssertEqual(editor.measure(width: 220, height: 0).height, 0)
            }
        }
    }

    func testChangingTheRenderedFontInvalidatesEditorSizeAnswers() throws {
        try onUIThread {
            let fontSize = State(wrappedValue: 14.0)
            let host = WinUIRenderer.running {
                TextEditor("First\nSecond")
                    .font(.system(size: fontSize.wrappedValue))
                    .frame(width: 220, height: 128)
            }
            let editor = try XCTUnwrap(host.views(WinUITextEditorView.self).first)
            let compact = WinUILayoutView.querySize { editor.measure(width: 220, height: nil) }
            let revision = editor.measurementRevision
            fontSize.wrappedValue = 36
            host.settle { editor.wordsStyle.size == 36 }
            XCTAssertGreaterThan(editor.measurementRevision, revision)
            let enlarged = WinUILayoutView.querySize { editor.measure(width: 220, height: nil) }
            XCTAssertGreaterThan(enlarged.height, compact.height)
            XCTAssertTrue(host.views(WinUITextEditorView.self).first === editor)
        }
    }

    func testReadingTheNativeLineDoesNotChangeTextSelectionOrFocus() throws {
        try onUIThread {
            let words = State(wrappedValue: "中文\nsecond line")
            let host = WinUIRenderer.running {
                TextEditor(words.projectedValue).frame(width: 240, height: 128)
            }
            let editor = try XCTUnwrap(host.views(WinUITextEditorView.self).first)
            XCTAssertTrue(swiftomniui_winui_focus(editor.handle, true))
            editor.select(start: 1, length: 3)
            for _ in 0..<4 {
                var lineHeight = Double.nan
                XCTAssertTrue(swiftomniui_winui_editor_intrinsic_height(editor.handle, &lineHeight))
                XCTAssertGreaterThan(lineHeight, 0)
                _ = editor.measure(width: 240, height: nil)
                editor.prepareMeasure(width: 240, height: 128)
                XCTAssertEqual(editor.text, words.wrappedValue)
                XCTAssertTrue(swiftomniui_winui_focused(editor.handle))
                var facts = [Int32](repeating: -1, count: 9)
                swiftomniui_winui_field_facts(editor.handle, &facts)
                XCTAssertEqual(Array(facts[5...6]), [1, 3])
            }
        }
    }

    func testComposerHeightAndControlOrientationChangesKeepTheNativeEditor() throws {
        try onUIThread {
            let words = State(wrappedValue: "")
            let sidebar = State(wrappedValue: true)
            let clock = TestClock()
            let motion = Animation.eased(200, .linear)
            let host = WinUIRenderer.running(clock: clock, room: WinUITestHost.wideRoom) {
                NavigationSplitView(sidebar.projectedValue) {
                    Text("Sidebar")
                } detail: {
                    ScrollView { Text("Conversation") }
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            HStack(alignment: .bottom) {
                                if words.wrappedValue.isEmpty {
                                    HStack {
                                        Button {} label: { Text("A").frame(width: 40, height: 40) }.id("attach-horizontal")
                                        Button {} label: { Text("V").frame(width: 40, height: 40) }
                                    }
                                } else {
                                    VStack {
                                        Button {} label: { Text("A").frame(width: 40, height: 40) }.id("attach-vertical")
                                        Button {} label: { Text("V").frame(width: 40, height: 40) }
                                    }
                                }
                                TextEditor(words.projectedValue.transaction(.init(animation: motion)))
                                    .frame(height: words.wrappedValue.isEmpty ? 40 : 128)
                                    .id("composer")
                                if words.wrappedValue.isEmpty {
                                    HStack {
                                        Button {} label: { Text("S").frame(width: 40, height: 40) }.id("send-horizontal")
                                        Button {} label: { Text("P").frame(width: 40, height: 40) }
                                    }
                                } else {
                                    VStack {
                                        Button {} label: { Text("S").frame(width: 40, height: 40) }.id("send-vertical")
                                        Button {} label: { Text("P").frame(width: 40, height: 40) }
                                    }
                                }
                            }.padding(16).buttonStyle(.plain).id("composer-row")
                        }
                }
            }
            for _ in 0..<8 { host.step(); host.frame() }
            let editor = try XCTUnwrap(host.views(WinUITextEditorView.self).first)
            XCTAssertTrue(swiftomniui_winui_focus(editor.handle, true))

            for value in ["中", "中文\nsecond", "", "another input", ""] {
                editor.type(value)
                host.step()
                let began = clock.now
                for elapsed in [0.0, 16, 33, 50, 100, 150, 200] {
                    clock.now = began + elapsed
                    host.frame()
                    XCTAssertTrue(host.views(WinUITextEditorView.self).first === editor)
                    XCTAssertTrue(swiftomniui_winui_focused(editor.handle))
                    XCTAssertEqual(editor.text, value)
                    let composer = try XCTUnwrap(host.view(id: .manual("composer-row")))
                    let orientation = value.isEmpty ? "horizontal" : "vertical"
                    for name in ["attach", "send"] {
                        let control = try XCTUnwrap(host.view(id: .manual("\(name)-\(orientation)")))
                        XCTAssertTrue(control.isAttached)
                        XCTAssertEqual(control.laidOutFrame.width, 40, accuracy: 1)
                        XCTAssertEqual(control.laidOutFrame.height, 40, accuracy: 1)
                        XCTAssertGreaterThanOrEqual(control.origin.x, composer.origin.x - 1)
                        XCTAssertLessThanOrEqual(control.origin.x + control.laidOutFrame.width,
                                                 composer.origin.x + composer.laidOutFrame.width + 1)
                        XCTAssertGreaterThanOrEqual(control.origin.y, composer.origin.y - 1)
                        XCTAssertLessThanOrEqual(control.origin.y + control.laidOutFrame.height,
                                                 composer.origin.y + composer.laidOutFrame.height + 1)
                    }
                    XCTAssertGreaterThan(editor.laidOutFrame.width, 0)
                    XCTAssertGreaterThanOrEqual(editor.origin.x, composer.origin.x - 1)
                    XCTAssertLessThanOrEqual(editor.origin.x + editor.laidOutFrame.width,
                                             composer.origin.x + composer.laidOutFrame.width + 1)
                }
                XCTAssertEqual(editor.laidOutFrame.height, value.isEmpty ? 40 : 128, accuracy: 1)
                sidebar.wrappedValue.toggle()
                for _ in 0..<8 { host.step(); host.frame() }
                XCTAssertTrue(host.views(WinUITextEditorView.self).first === editor)
                XCTAssertTrue(swiftomniui_winui_focused(editor.handle))
            }
        }
    }

    func testTypingAndReversingAnExpansionKeepsTheEditorSelectionAndLocalBounds() throws {
        try onUIThread {
            let words = State(wrappedValue: "")
            let clock = TestClock()
            let host = WinUIRenderer.running(clock: clock) {
                HStack(alignment: .bottom) {
                    Button {} label: { Text("A").frame(width: 40, height: 40) }
                    TextEditor(words.projectedValue)
                        .frame(height: words.wrappedValue.isEmpty ? 40 : 128)
                        .animation(.linear(duration: 0.2))
                        .id("input")
                    Button {} label: { Text("S").frame(width: 40, height: 40) }
                }.buttonStyle(.plain).frame(width: 480).id("row")
            }
            let editor = try XCTUnwrap(host.views(WinUITextEditorView.self).first)
            let identity = editor.handle
            XCTAssertTrue(swiftomniui_winui_focus(identity, true))
            for (time, value) in [(0.0, "a"), (33, "a second edit"), (50, ""), (66, "resumed")] {
                clock.now = time
                editor.type(value)
                host.step()
                editor.select(start: 0, length: value.isEmpty ? 0 : 1)
                host.frame()
                let row = try XCTUnwrap(host.view(id: .manual("row")))
                XCTAssertEqual(editor.handle, identity)
                XCTAssertTrue(swiftomniui_winui_focused(identity))
                XCTAssertEqual(editor.text, value)
                XCTAssertGreaterThan(editor.laidOutFrame.width, 0)
                XCTAssertGreaterThanOrEqual(editor.origin.x, row.origin.x - 1)
                XCTAssertLessThanOrEqual(editor.origin.x + editor.laidOutFrame.width,
                                         row.origin.x + row.laidOutFrame.width + 1)
                var facts = [Int32](repeating: -1, count: 9)
                swiftomniui_winui_field_facts(identity, &facts)
                XCTAssertEqual(Array(facts[5...6]), [0, value.isEmpty ? 0 : 1])
            }
            clock.now = 266
            host.frame()
            XCTAssertEqual(editor.laidOutFrame.height, 128, accuracy: 1)
        }
    }
}
