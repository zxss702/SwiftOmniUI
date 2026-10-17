// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

private struct MaskBubble: Shape {
    var right: Bool
    func path(in rect: Rect) -> Path {
        let w = rect.width, h = rect.height
        func p(_ x: Double, _ y: Double) -> Point { Point(right ? x : w - x, y) }
        return Path {
            $0.move(to: p(10, 0)); $0.addLine(to: p(w - 10, 0))
            $0.addQuadCurve(to: p(w, 10), control: p(w, 0))
            $0.addLine(to: p(w, h - 20))
            $0.addCurve(to: p(w - 2, h), control1: p(w, h - 8), control2: p(w, h))
            $0.addCurve(to: p(w - 22, h - 10), control1: p(w - 12, h), control2: p(w - 10, h - 10))
            $0.addLine(to: p(10, h - 10))
            $0.addQuadCurve(to: p(0, h - 20), control: p(0, h - 10))
            $0.addLine(to: p(0, 10))
            $0.addQuadCurve(to: p(10, 0), control: p(0, 0)); $0.closeSubpath()
        }
    }
}

/// Read the presented desktop: bitmap capture does not include Composition
/// child visuals. These tests require a visible, unobscured native window.
final class WinUIMaskTests: XCTestCase {
    private static let red: UInt32 = 0xFFFF_0000
    private static let blue: UInt32 = 0xFF00_00FF

    @MainActor private static func native(_ view: WinUIView, _ property: String) -> String {
        let count = Int(swiftomniui_winui_read(view.handle, property, nil, 0))
        var bytes = [CChar](repeating: 0, count: count + 1)
        _ = swiftomniui_winui_read(view.handle, property, &bytes, Int32(bytes.count))
        return String(decoding: bytes.prefix(count).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    func testAllBuilderLayersMaskByTheirLocalAlphaWithoutAGeometricClip() throws {
        try onUIThread {
            let host = WinUIRenderer.running {
                ZStack {
                    Color("#0000FF")
                    Rectangle().fill(Color("#FF0000")).mask {
                        Path(Rect(5, 5, 25, 25)).fill(.black)
                        Path(Rect(70, 30, 20, 20)).fill(.white)
                    }
                }.frame(width: 100, height: 60)
            }
            let window = try XCTUnwrap(host.window)
            let root = try XCTUnwrap(host.views(WinUIZStackView.self).first)
            let masked = try XCTUnwrap(host.views(WinUIMaskedView.self).first)
            let points: [(Double, Double)] = [(10, 10), (75, 35), (50, 30), (1, 1)]
            let expected = [Self.red, Self.red, Self.blue, Self.blue]
            host.settle { root.presentedPixels(at: points, in: window) == expected }
            XCTAssertEqual(root.presentedPixels(at: points, in: window), expected)
            XCTAssertEqual(Self.native(masked,"alphaMasked"), "1")
            XCTAssertEqual(Self.native(masked,"clipped"), "0")
        }
    }

    func testMaskAlphaMultipliesAuthoredOpacityAndUpdatesWithoutReplacingControls() throws {
        try onUIThread {
            let opacity = State(wrappedValue: 0.5)
            let host = WinUIRenderer.running(reducesMotion: true) {
                VStack(spacing: 0) {
                    ZStack {
                        Color("#0000FF")
                        Rectangle().fill(Color("#FF0000")).mask {
                            Rectangle().fill(.black.opacity(0.5)).opacity(opacity.wrappedValue)
                        }
                    }.frame(width: 100, height: 60)
                    ZStack {
                        Color("#0000FF")
                        Rectangle().fill(Color("#FF0000")).opacity(0.5 * opacity.wrappedValue)
                    }.frame(width: 100, height: 60)
                }.frame(width: 100, height: 120)
            }
            let window = try XCTUnwrap(host.window)
            let root = try XCTUnwrap(host.views(WinUIStackView.self).first)
            let masked = try XCTUnwrap(host.views(WinUIMaskedView.self).first)
            let alpha = try XCTUnwrap(masked.items.last?.view)
            let alphaShape = try XCTUnwrap((alpha as? WinUIZStackView)?.items.first?.view)
            let reference = try XCTUnwrap(root.items.last?.view)
            let points: [(Double, Double)] = [(50, 30), (50, 90)]
            for value in [0.5, 1.0, 0.0, 0.75] {
                opacity.wrappedValue = value
                host.step()
                // Capture only the ordinary XAML reference row. Its current
                // pixels keep two stale, equal desktop rows from passing.
                let expected = try XCTUnwrap(reference.pixels(at: [(50, 30)]).first)
                host.settle {
                    let samples = root.presentedPixels(at: points, in: window)
                    return samples.count == 2 && Self.close(samples[0], samples[1])
                        && Self.close(samples[1], expected)
                        && alphaShape.drawnOpacity == value
                }
                let samples = root.presentedPixels(at: points, in: window)
                XCTAssertEqual(samples.count, 2)
                if samples.count == 2 {
                    XCTAssertTrue(Self.close(samples[0], samples[1]), "mask alpha equals native opacity: \(samples)")
                    XCTAssertTrue(Self.close(samples[0], expected))
                    if value > 0 {
                        XCTAssertNotEqual(samples[0], Self.red)
                        XCTAssertNotEqual(samples[0], Self.blue)
                    } else { XCTAssertEqual(samples[0], Self.blue) }
                }
                XCTAssertEqual(alphaShape.drawnOpacity, value)
                XCTAssertTrue(host.views(WinUIMaskedView.self).first === masked)
                XCTAssertTrue(masked.items.last?.view === alpha)
            }
        }
    }

    func testCurvedMaskTailAndConcavityFollowParametersAndResize() throws {
        try onUIThread {
            let right = State(wrappedValue: true), width = State(wrappedValue: 100.0)
            let host = WinUIRenderer.running(reducesMotion: true) {
                ZStack {
                    Color("#0000FF")
                    Rectangle().fill(Color("#FF0000")).mask { MaskBubble(right: right.wrappedValue).fill(.black) }
                }.frame(width: width.wrappedValue, height: 60)
            }
            let window = try XCTUnwrap(host.window)
            let root = try XCTUnwrap(host.views(WinUIZStackView.self).first)
            let masked = try XCTUnwrap(host.views(WinUIMaskedView.self).first)
            let path = try XCTUnwrap(host.views(WinUIPathView.self).first)
            let points: [(Double, Double)] = [(50, 25), (94, 56), (83, 56), (6, 56)]
            let outgoing = [Self.red, Self.red, Self.blue, Self.blue]
            host.settle { root.presentedPixels(at: points, in: window) == outgoing }
            XCTAssertEqual(root.presentedPixels(at: points, in: window), outgoing)
            right.wrappedValue = false
            let incoming = [Self.red, Self.blue, Self.blue, Self.red]
            host.settle { root.presentedPixels(at: points, in: window) == incoming }
            XCTAssertEqual(root.presentedPixels(at: points, in: window), incoming)
            width.wrappedValue = 140
            host.settle { root.presentedPixels(at: [(130, 25)], in: window) == [Self.red] }
            XCTAssertEqual(root.presentedPixels(at: [(130, 25)], in: window), [Self.red])
            XCTAssertTrue(host.views(WinUIMaskedView.self).first === masked)
            XCTAssertTrue(host.views(WinUIPathView.self).first === path)
        }
    }

    func testEvenOddHoleAndEmptyPathUpdateTheLiveMask() throws {
        try onUIThread {
            let mode = State(wrappedValue: 0)
            let host = WinUIRenderer.running(reducesMotion: true) {
                var path = Path()
                if mode.wrappedValue != 2 {
                    path.addRect(Rect(5, 5, 90, 50))
                    if mode.wrappedValue == 0 { path.addEllipse(in: Rect(30, 10, 40, 40)) }
                }
                return ZStack {
                    Color("#0000FF")
                    Rectangle().fill(Color("#FF0000")).mask {
                        path.fill(.black, style: FillStyle(eoFill: true, antialiased: true))
                    }
                }.frame(width: 100, height: 60)
            }
            let window = try XCTUnwrap(host.window)
            let root = try XCTUnwrap(host.views(WinUIZStackView.self).first)
            let masked = try XCTUnwrap(host.views(WinUIMaskedView.self).first)
            let points: [(Double, Double)] = [(10, 30), (50, 30), (1, 1)]
            for (value, expected) in [(0, [Self.red, Self.blue, Self.blue]),
                                      (1, [Self.red, Self.red, Self.blue]),
                                      (2, [Self.blue, Self.blue, Self.blue]),
                                      (0, [Self.red, Self.blue, Self.blue])] {
                mode.wrappedValue = value
                host.settle { root.presentedPixels(at: points, in: window) == expected }
                XCTAssertEqual(root.presentedPixels(at: points, in: window), expected)
                XCTAssertTrue(host.views(WinUIMaskedView.self).first === masked)
            }
        }
    }

    func testGradientMaskPreservesIntermediateAlpha() throws {
        try onUIThread {
            let host = WinUIRenderer.running {
                ZStack {
                    Color("#0000FF")
                    Rectangle().fill(Color("#FF0000")).mask {
                        LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                    }
                }.frame(width: 100, height: 60)
            }
            let window = try XCTUnwrap(host.window)
            let root = try XCTUnwrap(host.views(WinUIZStackView.self).first)
            let points: [(Double, Double)] = [(10, 30), (50, 30), (90, 30)]
            host.settle {
                let samples = root.presentedPixels(at: points, in: window)
                return samples.count == 3 && (samples[0] >> 16 & 255) < (samples[1] >> 16 & 255)
                    && (samples[1] >> 16 & 255) < (samples[2] >> 16 & 255)
            }
            let samples = root.presentedPixels(at: points, in: window)
            XCTAssertEqual(samples.count, 3)
            guard samples.count == 3 else { return }
            XCTAssertLessThan(samples[0] >> 16 & 255, samples[1] >> 16 & 255)
            XCTAssertLessThan(samples[1] >> 16 & 255, samples[2] >> 16 & 255)
            XCTAssertGreaterThan(samples[0] & 255, samples[1] & 255)
            XCTAssertGreaterThan(samples[1] & 255, samples[2] & 255)
            XCTAssertNotEqual(samples[1], Self.red)
            XCTAssertNotEqual(samples[1], Self.blue)
        }
    }

    func testCanvasAndImageAlphaUseTheirDrawingInsteadOfTheirBoxes() throws {
        try onUIThread {
            let host = WinUIRenderer.running {
                VStack(spacing: 0) {
                    ZStack {
                        Color("#0000FF")
                        Rectangle().fill(Color("#FF0000")).mask {
                            Canvas { context, _ in
                                context.fill(Path(Rect(10, 10, 20, 20)), with: .color(.black))
                                context.fill(Path(Rect(70, 30, 20, 20)), with: .color(.white))
                            }
                        }
                    }.frame(width: 100, height: 60)
                    ZStack {
                        Color("#0000FF")
                        Rectangle().fill(Color("#FF0000")).mask {
                            Image("test_wide.svg").resizable().scaledToFit()
                        }
                    }.frame(width: 100, height: 100)
                }.frame(width: 100, height: 160)
            }
            let window = try XCTUnwrap(host.window)
            let root = try XCTUnwrap(host.views(WinUIStackView.self).first)
            let points: [(Double, Double)] = [(15, 15), (75, 35), (50, 30),
                                            (50, 110), (50, 65), (50, 155)]
            let expected = [Self.red, Self.red, Self.blue, Self.red, Self.blue, Self.blue]
            host.settle { root.presentedPixels(at: points, in: window) == expected }
            XCTAssertEqual(root.presentedPixels(at: points, in: window), expected)
        }
    }

    func testMaskDescendantsCannotTakeKeyboardFocus() throws {
        try onUIThread {
            let host = WinUIRenderer.running {
                TextEditor("").frame(width: 220, height: 80).mask { Button("Alpha source") }
            }
            let editor = try XCTUnwrap(host.views(WinUITextEditorView.self).first)
            let button = try XCTUnwrap(host.views(WinUIButtonView.self).first)
            XCTAssertTrue(swiftomniui_winui_focus(editor.handle, true))
            XCTAssertFalse(swiftomniui_winui_focus(button.handle, true))
            XCTAssertTrue(swiftomniui_winui_focused(editor.handle))
        }
    }

    func testSourceKeepsFocusTextSelectionAndIdentityWhenTheMaskChanges() throws {
        try onUIThread {
            let opacity = State(wrappedValue: 1.0), words = State(wrappedValue: "")
            let host = WinUIRenderer.running {
                TextEditor(text: words.projectedValue).scrollContentBackground(.hidden)
                    .frame(width: 220, height: 80)
                    .mask { Rectangle().fill(.black).opacity(opacity.wrappedValue) }
            }
            let masked = try XCTUnwrap(host.views(WinUIMaskedView.self).first)
            let editor = try XCTUnwrap(host.views(WinUITextEditorView.self).first)
            XCTAssertTrue(swiftomniui_winui_focus(editor.handle, true))
            editor.type("中文\nsecond")
            host.settle { words.wrappedValue == "中文\nsecond" }
            editor.select(start: 1, length: 2)
            for value in [0.5, 0.0, 1.0] {
                opacity.wrappedValue = value
                host.step()
                host.step()
                XCTAssertTrue(host.views(WinUIMaskedView.self).first === masked)
                XCTAssertTrue(host.views(WinUITextEditorView.self).first === editor)
                XCTAssertTrue(swiftomniui_winui_focused(editor.handle))
                XCTAssertEqual(editor.text, "中文\nsecond")
                var facts = [Int32](repeating: -1, count: 9)
                swiftomniui_winui_field_facts(editor.handle, &facts)
                XCTAssertEqual(Array(facts[5...6]), [1, 2])
            }
            masked.detach()
            XCTAssertEqual(Self.native(masked,"alphaMasked"), "0", "detaching releases the redirected visual trees")
        }
    }

    private static func close(_ a: UInt32, _ b: UInt32) -> Bool {
        [0, 8, 16].allSatisfy { shift in
            abs(Int(a >> shift & 255) - Int(b >> shift & 255)) <= 3
        }
    }
}
