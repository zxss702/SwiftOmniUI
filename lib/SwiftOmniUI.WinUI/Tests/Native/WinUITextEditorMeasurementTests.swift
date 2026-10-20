// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import SwiftOmniUIConformance
import XCTest

final class WinUITextEditorMeasurementTests: XCTestCase {
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
