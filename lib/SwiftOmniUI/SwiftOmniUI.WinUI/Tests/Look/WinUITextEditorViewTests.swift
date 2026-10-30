// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

/// The application's composer: comparable, with owned focus and a placeholder that disappears on the first edit.
private struct EquatableInputEditor: View, Equatable {
    @Binding var words: String
    @FocusState private var focused: Bool
    let reportedFocus: Binding<Bool>

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.words == rhs.words }

    var body: some View {
        let report = reportedFocus
        return TextEditor(text: $words)
            .scrollContentBackground(.hidden)
            .background(alignment: .topLeading) {
                if words.isEmpty { Text("Write something") }
            }
            .focused($focused)
            .defaultFocus($focused, true)
            .frame(width: 220, height: words.isEmpty ? 40 : 128)
            .onChange(of: focused) { _, focused in report.wrappedValue = focused }
    }
}

final class WinUITextEditorViewTests: XCTestCase {
    /// Every character rebuilds the parent and makes a fresh comparable composer; its owned focus must survive.
    func testTypingIntoAnEquatableComposerKeepsFocusAcrossParentRebuilds() throws {
        try onUIThread {
            let words = State(wrappedValue: "")
            let focused = State(wrappedValue: false)
            let revision = State(wrappedValue: 0)
            let host = WinUIRenderer.running {
                VStack {
                    Text("\(revision.wrappedValue):\(words.wrappedValue.count)")
                    EquatableInputEditor(words: words.projectedValue, reportedFocus: focused.projectedValue).equatable()
                    Button("Other")
                }
            }
            let editor = try XCTUnwrap(host.views(WinUITextEditorView.self).first)
            XCTAssertTrue(swiftomniui_winui_focus(editor.handle, true))
            host.settle { focused.wrappedValue }
            XCTAssertTrue(focused.wrappedValue)

            for expected in ["a", "ab", "ab中", "ab中\n", "ab中\nc"] {
                editor.type(expected)
                host.step()
                host.step()
                XCTAssertEqual(words.wrappedValue, expected)
                XCTAssertEqual(editor.text, expected)
                XCTAssertTrue(host.views(WinUITextEditorView.self).first === editor)
                XCTAssertTrue(swiftomniui_winui_focused(editor.handle), "focus survives typing \(expected)")
                XCTAssertTrue(focused.wrappedValue, "the focus binding stays true")
            }

            let other = try XCTUnwrap(host.views(WinUIButtonView.self).first)
            XCTAssertTrue(swiftomniui_winui_focus(other.handle, true))
            host.settle { !focused.wrappedValue }
            revision.wrappedValue += 1
            host.step()
            host.step()
            XCTAssertFalse(swiftomniui_winui_focused(editor.handle), "a later rebuild does not steal focus back")
            XCTAssertFalse(focused.wrappedValue)
        }
    }

    /// The focused template has its own border thickness: its rendered edges must still match its plain canvas.
    func testTheDefaultCanvasHasNoFocusDecoration() throws {
        try onUIThread {
            let host = WinUIRenderer.running {
                VStack {
                    TextEditor("").frame(width: 220, height: 100)
                    Button("Other")
                }
            }
            let editor = try XCTUnwrap(host.views(WinUITextEditorView.self).first)
            let other = try XCTUnwrap(host.views(WinUIButtonView.self).first)

            for focused in [false, true] {
                XCTAssertTrue(swiftomniui_winui_focus(focused ? editor.handle : other.handle, true))
                host.settle { swiftomniui_winui_focused(editor.handle) == focused }
                let pixels = editor.canvasPixels
                XCTAssertGreaterThan(pixels[0] >> 24, 0, "the ordinary canvas is filled")
                XCTAssertTrue(pixels.allSatisfy { $0 == pixels[0] }, "no border or focus underline: \(pixels)")
            }
        }
    }

    /// The hidden canvas remains transparent after WinUI enters its focused and disabled template states.
    func testAHiddenCanvasStaysClearInEveryState() throws {
        try onUIThread {
            let host = WinUIRenderer.running {
                VStack {
                    TextEditor("").frame(width: 220, height: 100)
                    Button("Other")
                }
                .scrollContentBackground(.hidden)
            }
            let editor = try XCTUnwrap(host.views(WinUITextEditorView.self).first)
            let other = try XCTUnwrap(host.views(WinUIButtonView.self).first)

            for focused in [false, true] {
                XCTAssertTrue(swiftomniui_winui_focus(focused ? editor.handle : other.handle, true))
                host.settle { swiftomniui_winui_focused(editor.handle) == focused }
                XCTAssertEqual(editor.canvasPixels, Array(repeating: 0, count: 5))
            }
            XCTAssertTrue(swiftomniui_winui_focused(editor.handle), "the native caret still takes focus")
            editor.setEnabled(false)
            host.settle { !swiftomniui_winui_focused(editor.handle) }
            XCTAssertEqual(editor.canvasPixels, Array(repeating: 0, count: 5))
        }
    }

    /// A loaded, focused editor takes changes to its canvas without losing its words, binding or selection.
    func testChangingTheCanvasPreservesNativeEditing() throws {
        try onUIThread {
            let background = State<Visibility?>(wrappedValue: nil)
            let words = State(wrappedValue: "")
            let host = WinUIRenderer.running {
                let editor = ModifiedContent(node: TextEditor(words.projectedValue)
                    .frame(width: 220, height: 100).id("editor").node)
                let styled = background.wrappedValue.map { editor.scrollContentBackground($0) } ?? editor
                return VStack { styled; Button("Other") }
            }
            let editor = try XCTUnwrap(host.views(WinUITextEditorView.self).first)
            XCTAssertTrue(swiftomniui_winui_focus(editor.handle, true))
            editor.type("中文\nsecond")
            host.settle { words.wrappedValue == "中文\nsecond" }
            host.layOut()
            editor.select(start: 1, length: 2)
            let before = editor.frame
            let visible = editor.canvasPixels

            for visibility: Visibility? in [.hidden, .visible, .hidden, .automatic, .hidden, nil] {
                background.wrappedValue = visibility
                host.step()
                host.settle {
                    let clear = editor.canvasPixels.allSatisfy { $0 == 0 }
                    return clear == (visibility == .hidden)
                }
                XCTAssertTrue(host.views(WinUITextEditorView.self).first === editor)
                XCTAssertEqual(editor.canvasPixels, visibility == .hidden ? Array(repeating: 0, count: 5) : visible)
                XCTAssertEqual(words.wrappedValue, "中文\nsecond")
                XCTAssertEqual(editor.text, words.wrappedValue)
                XCTAssertTrue(swiftomniui_winui_focused(editor.handle))
                XCTAssertEqual(editor.frame.width, before.width)
                XCTAssertEqual(editor.frame.height, before.height)
                var facts = [Int32](repeating: -1, count: 9)
                swiftomniui_winui_field_facts(editor.handle, &facts)
                XCTAssertEqual(Array(facts[5...6]), [1, 2])
                XCTAssertEqual(facts[8], 1, "Return still starts a new line")
            }
        }
    }
}

private extension WinUITextEditorView {
    /// Empty points at the centre and each edge, away from the caret, text and scrollbar.
    var canvasPixels: [UInt32] {
        let size = frame
        return pixels(at: [(size.width / 2, size.height / 2), (0.5, size.height / 2),
                           (size.width - 0.5, size.height / 2), (size.width / 2, 0.5),
                           (size.width / 2, size.height - 0.5)])
    }
}
