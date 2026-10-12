// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIGTK
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIGTK
import XCTest

final class GTKTextEditorViewTests: XCTestCase {
    /// The default canvas is filled, but its edges stay the canvas's colour even with the keyboard inside it.
    func testTheDefaultCanvasHasNoFocusDecoration() throws {
        try onUIThread {
            let host = GTKRenderer.running {
                VStack {
                    TextEditor("").frame(width: 220, height: 100)
                    Button("Other")
                }
            }
            let editor = try XCTUnwrap(host.views(GTKTextEditorView.self).first)
            let other = try XCTUnwrap(host.views(GTKButtonView.self).first)

            for focused in [false, true] {
                XCTAssertNotEqual(gtk_widget_grab_focus(focused ? editor.textView : other.widget), 0)
                host.step()
                let pixels = editor.canvasPixels
                XCTAssertGreaterThan(pixels[0] >> 24, 0, "the ordinary canvas is filled")
                XCTAssertTrue(pixels.allSatisfy { near($0, pixels[0]) }, "no border or focus ring: \(pixels)")
            }
        }
    }

    /// A hidden canvas stays clear while focused, pointed at or disabled. An inherited modifier reaches it too.
    func testAHiddenCanvasStaysClearInEveryState() throws {
        try onUIThread {
            let host = GTKRenderer.running {
                VStack {
                    TextEditor("").frame(width: 220, height: 100)
                    Button("Other")
                }
                .scrollContentBackground(.hidden)
            }
            let editor = try XCTUnwrap(host.views(GTKTextEditorView.self).first)
            let other = try XCTUnwrap(host.views(GTKButtonView.self).first)

            XCTAssertNotEqual(gtk_widget_grab_focus(other.widget), 0)
            host.step()
            XCTAssertEqual(editor.canvasPixels, Array(repeating: 0, count: 5))
            XCTAssertNotEqual(gtk_widget_grab_focus(editor.textView), 0)
            host.step()
            XCTAssertNotEqual(gtk_widget_has_focus(editor.textView), 0, "the native caret still takes focus")
            XCTAssertEqual(editor.canvasPixels, Array(repeating: 0, count: 5))

            for widget in [editor.widget, editor.textView] {
                gtk_widget_set_state_flags(widget, GTK_STATE_FLAG_PRELIGHT, 0)
            }
            host.step()
            XCTAssertEqual(editor.canvasPixels, Array(repeating: 0, count: 5))
            for widget in [editor.widget, editor.textView] {
                gtk_widget_unset_state_flags(widget, GTK_STATE_FLAG_PRELIGHT)
            }
            editor.setEnabled(false)
            host.step()
            XCTAssertEqual(editor.canvasPixels, Array(repeating: 0, count: 5))
        }
    }

    /// Changing and removing the modifier restores the fill without recreating the editor or moving its selection.
    func testChangingTheCanvasPreservesNativeEditing() throws {
        try onUIThread {
            let background = State<Visibility?>(wrappedValue: nil)
            let words = State(wrappedValue: "")
            let host = GTKRenderer.running {
                let editor = ModifiedContent(node: TextEditor(words.projectedValue)
                    .frame(width: 220, height: 100).id("editor").node)
                let styled = background.wrappedValue.map { editor.scrollContentBackground($0) } ?? editor
                return VStack { styled; Button("Other") }
            }
            let editor = try XCTUnwrap(host.views(GTKTextEditorView.self).first)
            let textView = editor.textView
            let buffer = gtk_text_view_get_buffer(textView.of())
            XCTAssertNotEqual(gtk_widget_grab_focus(textView), 0)
            GTKTestHost.emit(OpaquePointer(textView), "insert-at-cursor", words: "中文\nsecond")
            host.settle { words.wrappedValue == "中文\nsecond" }
            host.step()
            host.layOut()
            editor.select(start: 1, length: 2)
            let before = editor.frame
            let visible = editor.canvasPixels

            for visibility: Visibility? in [.hidden, .visible, .hidden, .automatic, .hidden, nil] {
                background.wrappedValue = visibility
                host.step()
                host.layOut()
                host.settle {
                    let clear = editor.canvasPixels.allSatisfy { $0 == 0 }
                    return clear == (visibility == .hidden)
                }
                XCTAssertTrue(host.views(GTKTextEditorView.self).first === editor)
                XCTAssertEqual(editor.canvasPixels, visibility == .hidden ? Array(repeating: 0, count: 5) : visible)
                XCTAssertEqual(words.wrappedValue, "中文\nsecond")
                XCTAssertEqual(editor.text, words.wrappedValue)
                XCTAssertNotEqual(gtk_widget_has_focus(textView), 0)
                XCTAssertEqual(editor.frame.width, before.width)
                XCTAssertEqual(editor.frame.height, before.height)
                var start = GtkTextIter()
                var end = GtkTextIter()
                XCTAssertNotEqual(gtk_text_buffer_get_selection_bounds(buffer, &start, &end), 0)
                XCTAssertEqual([gtk_text_iter_get_offset(&start), gtk_text_iter_get_offset(&end)], [1, 3])
            }
        }
    }
}

private extension GTKTextEditorView {
    var textView: GTKWidget { gtk_scrolled_window_get_child(widget.opaque)! }

    /// Empty points at the centre and each edge, away from the caret, text and scrollbar.
    var canvasPixels: [UInt32] {
        let size = frame
        return pixels(at: [(size.width / 2, size.height / 2), (0.5, size.height / 2),
                           (size.width - 0.5, size.height / 2), (size.width / 2, 0.5),
                           (size.width / 2, size.height - 0.5)])
    }
}
