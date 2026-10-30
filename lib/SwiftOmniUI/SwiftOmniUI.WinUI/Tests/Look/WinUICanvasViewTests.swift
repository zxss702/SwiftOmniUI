// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

/// A canvas that says where a press on it went, a switch that widens it, and one that takes it away.
private struct PressPage: View {
    @State private var said = ""
    @State private var wide = false
    @State private var shown = true

    var body: some View {
        VStack {
            Text(said)
            if shown {
                Canvas {
                    Draw.fillColor(Color("#FF0000"))
                    Draw.fillRectangle(x: 0, y: 0, width: 300, height: 20)
                }
                .frame(width: wide ? 200 : 100)
                .frame(height: 20)
                .horizontalAlignment(.start)
                .onPressed { point in said += "pressed \(Int(point.x)),\(Int(point.y)); " }
                .onDragged { point in said += "dragged \(Int(point.x)),\(Int(point.y)); " }
                .onReleased { point in said += "released \(Int(point.x)),\(Int(point.y)); " }
            }
            Button("Widen").onClicked { wide = true }
            Button("Hide").onClicked { shown = false }
        }
        .frame(width: 300)
        .horizontalAlignment(.start)
        .verticalAlignment(.start)
    }
}

/// A canvas a click shows.
private struct ShowingPage: View {
    @State private var shown = false

    var body: some View {
        VStack {
            if shown {
                Canvas {
                    Draw.fillColor(Color("#FF0000"))
                    Draw.fillRectangle(x: 0, y: 0, width: 300, height: 20)
                }
                .frame(width: 100)
                .frame(height: 20)
            }
            Button("Show").onClicked { shown = true }
        }
        .horizontalAlignment(.start)
        .verticalAlignment(.start)
    }
}

/// Keeps one native canvas while its drawing changes, then repaints the same
/// commands into a larger surface.
private struct ResourcePage: View {
    @State private var changed = false
    @State private var wide = false

    var body: some View {
        VStack {
            Canvas {
                Draw.fillColor(Color("#FF0000"))
                Draw.fillPath(changed
                    ? "M 30 0 L 50 0 L 50 20 L 30 20 Z"
                    : "M 0 0 L 20 0 L 20 20 L 0 20 Z")
                Draw.fillPath("M 70 0 L 90 0 L 90 20 L 70 20 Z")
                Draw.fillPath("M 110 0 L 130 0 L 130 20 L 110 20 Z")
                Draw.foregroundStyle(Color("#0000FF"))
                Draw.fontSize(18)
                Draw.drawText("MMMM", x: changed ? 55 : 0, y: 28, width: 45, height: 25)
            }
            .frame(width: wide ? 140 : 100)
            .frame(height: 55)
            .horizontalAlignment(.start)
            Button("Change").onClicked { changed = true }
            Button("Widen").onClicked { wide = true }
        }
        .frame(width: 160)
        .horizontalAlignment(.start)
        .verticalAlignment(.start)
    }
}

/// The size-dependent renderer must contribute its first drawing during the
/// initial native allocation, without a follow-up geometry feedback render.
private struct FirstFrameCanvasPage: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(Rect(0, 0, size.width, size.height)),
                         with: .color(Color("#FF0000")))
        }
        .frame(width: 100, height: 40)
    }
}

final class WinUICanvasViewTests: XCTestCase {
    private static let red: UInt32 = 0xFFFF_0000
    private static let blue: UInt32 = 0xFF00_00FF

    func testSizeDependentCanvasDrawsFromItsFirstNativeAllocation() throws {
        try onUIThread {
            let host = WinUIRenderer.running { FirstFrameCanvasPage() }
            let canvas = try XCTUnwrap(host.views(WinUICanvasView.self).first)
            host.settle { canvas.pixels(at: [(10, 10), (90, 30)]) == [Self.red, Self.red] }
            XCTAssertEqual(canvas.pixels(at: [(10, 10), (90, 30)]), [Self.red, Self.red])
        }
    }

    func testCommandsAndResizePublishOneFinalSurfacePerRenderingPhase() throws {
        try onUIThread {
            let version = State(wrappedValue: 0)
            let host = WinUIRenderer.running {
                Canvas {
                    Draw.fillColor(Color(version.wrappedValue == 2 ? "#0000FF" : "#FF0000"))
                    Draw.fillRectangle(x: 0, y: 0, width: 200, height: 40)
                }
                .frame(width: 100 + Double(version.wrappedValue) * 20, height: 40)
            }
            let canvas = try XCTUnwrap(host.views(WinUICanvasView.self).first)
            host.settle { canvas.pixels(at: [(10, 10)]) == [Self.red] }
            let before = swiftomniui_winui_canvas_paints(canvas.handle)
            for value in [1, 2] {
                version.wrappedValue = value
                host.runtime.pump.turn()
                host.layOut()
            }
            XCTAssertEqual(swiftomniui_winui_canvas_paints(canvas.handle), before,
                           "command submission and arrangement do not synchronously replay obsolete surfaces")
            host.settle { canvas.pixels(at: [(10, 10), (130, 10)]) == [Self.blue, Self.blue] }
            XCTAssertEqual(canvas.pixels(at: [(10, 10), (130, 10)]), [Self.blue, Self.blue])
            XCTAssertEqual(swiftomniui_winui_canvas_paints(canvas.handle), before + 1)
            XCTAssertTrue(host.views(WinUICanvasView.self).first === canvas)
        }
    }

    /// The instructions run in order: a colour holds until the next, and a later shape paints over an earlier one.
    func testInstructionsRunInOrder() throws {
        let colours = try drawn(width: 100, height: 40, at: [(10, 20), (60, 20), (95, 20)]) {
            Draw.fillColor(Color("#FF0000"))
            Draw.fillRectangle(x: 0, y: 0, width: 80, height: 40)
            Draw.fillColor(Color("#0000FF"))
            Draw.fillRectangle(x: 50, y: 0, width: 20, height: 40)
        }
        XCTAssertEqual(colours, [Self.red, Self.blue, 0])
    }

    /// A transform moves what is drawn after it, and restoreState puts back what saveState kept: the colour and
    /// the transform alike.
    func testRestoreStatePutsBackTheColourAndTheTransform() throws {
        let colours = try drawn(width: 100, height: 20, at: [(5, 10), (45, 10), (85, 10), (25, 10)]) {
            Draw.fillColor(Color("#FF0000"))
            Draw.saveState()
            Draw.translate(dx: 40, dy: 0)
            Draw.fillColor(Color("#0000FF"))
            Draw.fillRectangle(x: 0, y: 0, width: 10, height: 20)
            Draw.restoreState()
            Draw.fillRectangle(x: 0, y: 0, width: 10, height: 20)
            Draw.fillRectangle(x: 80, y: 0, width: 10, height: 20)
        }
        XCTAssertEqual(colours, [Self.red, Self.blue, Self.red, 0])
    }

    /// A drawing reaching past the canvas is cut at its edge: nothing beside the canvas is painted.
    func testADrawingIsCutAtTheCanvasEdge() throws {
        let colours = try drawn(width: 40, height: 40, at: [(20, 20), (60, 20), (20, 60)]) {
            Draw.fillColor(Color("#FF0000"))
            Draw.fillRectangle(x: -50, y: -50, width: 200, height: 200)
        }
        XCTAssertEqual(colours, [Self.red, 0, 0])
    }

    /// A wedge is filled from the middle of its oval, from its start round to its end the way it turns.
    func testAWedgeTurnsTheWayItIsTold() throws {
        let clockwise = try drawn(width: 100, height: 100, at: [(75, 75), (25, 25), (75, 25), (25, 75)]) {
            Draw.fillColor(Color("#FF0000"))
            Draw.fillArc(x: 0, y: 0, width: 100, height: 100, startAngle: 0, endAngle: 90, clockwise: true)
        }
        XCTAssertEqual(clockwise, [Self.red, 0, 0, 0], "a quarter, down from the right")

        let counter = try drawn(width: 100, height: 100, at: [(25, 25), (75, 75), (75, 25), (25, 75)]) {
            Draw.fillColor(Color("#FF0000"))
            Draw.fillArc(x: 0, y: 0, width: 100, height: 100, startAngle: 0, endAngle: 90, clockwise: false)
        }
        XCTAssertEqual(counter, [Self.red, 0, Self.red, Self.red], "the three quarters up from the right")
    }

    /// A path is drawn from its own numbers, and an outline follows its edge without filling it.
    func testAPathIsFilledAndAnEllipseOutlined() throws {
        let path = try drawn(width: 40, height: 40, at: [(5, 5), (35, 35)]) {
            Draw.fillColor(Color("#FF0000"))
            Draw.fillPath("M 0 0 L 40 0 L 0 40 Z")
        }
        XCTAssertEqual(path, [Self.red, 0])

        let outline = try drawn(width: 40, height: 40, at: [(20, 1), (20, 20)]) {
            Draw.strokeColor(Color("#0000FF"))
            Draw.strokeWidth(4)
            Draw.drawEllipse(x: 0, y: 0, width: 40, height: 40)
        }
        XCTAssertEqual(outline, [Self.blue, 0])
    }

    /// Text is written inside its box, set to its end; what wraps past the box is cut.
    func testTextIsWrittenInItsBox() throws {
        let row = (0..<100).map { (Double($0), 10.0) }
        let set = try drawn(width: 100, height: 20, at: row) {
            Draw.foregroundStyle(Color("#000000"))
            Draw.fontSize(16)
            Draw.drawText("WW", x: 0, y: 0, width: 100, height: 20, horizontalAlignment: .end)
        }
        XCTAssertTrue(set[0..<50].allSatisfy { $0 == 0 }, "set to its end, the text leaves the start empty")
        XCTAssertTrue(set[50..<100].contains { $0 != 0 }, "and is written at the end")

        let lines = [10.0, 30.0].flatMap { y in (0..<40).map { (Double($0), y) } }
        let wrapped = try drawn(width: 40, height: 40, at: lines) {
            Draw.foregroundStyle(Color("#000000"))
            Draw.fontSize(16)
            Draw.drawText("WWW WWW WWW", x: 0, y: 0, width: 40, height: 20)
        }
        XCTAssertTrue(wrapped[0..<40].contains { $0 != 0 }, "the first line is written in its box")
        XCTAssertTrue(wrapped[40..<80].allSatisfy { $0 == 0 }, "the lines wrapped past the box are cut")
    }

    /// A command update must replace both path and text resources. A later
    /// surface resize replays the unchanged commands from their kept resources.
    func testPathAndTextResourcesFollowDrawingChangesAndResize() throws {
        try onUIThread {
            let host = WinUIRenderer.running { ResourcePage() }
            let canvas = try XCTUnwrap(host.views(WinUICanvasView.self).first)
            let leftText = (30..<50).flatMap { y in (0..<45).map { x in (Double(x), Double(y)) } }
            let rightText = (30..<50).flatMap { y in (55..<100).map { x in (Double(x), Double(y)) } }

            host.settle { canvas.pixels(at: [(5, 5), (80, 5)]) == [Self.red, Self.red] }
            XCTAssertTrue(canvas.pixels(at: leftText).contains { $0 != 0 })
            XCTAssertTrue(canvas.pixels(at: rightText).allSatisfy { $0 == 0 })

            try XCTUnwrap(host.views(WinUIButtonView.self).first).invoke()
            host.settle { canvas.pixels(at: [(5, 5), (35, 5), (80, 5)]) == [0, Self.red, Self.red] }
            XCTAssertTrue(canvas.pixels(at: leftText).allSatisfy { $0 == 0 })
            XCTAssertTrue(canvas.pixels(at: rightText).contains { $0 != 0 })

            try XCTUnwrap(host.views(WinUIButtonView.self).last).invoke()
            host.settle { canvas.pixels(at: [(35, 5), (80, 5), (120, 5)]) == [Self.red, Self.red, Self.red] }
            XCTAssertTrue(canvas.pixels(at: rightText).contains { $0 != 0 })
            XCTAssertTrue(host.views(WinUICanvasView.self).first === canvas, "the resource owner stays mounted")
        }
    }

    /// A canvas WinUI takes out and puts back before it has loaded - as a tabbed view holds its page again when
    /// the window takes its tabs - is drawn: the unloading WinUI tells after the loading stops nothing.
    func testACanvasPutBackBeforeItLoadsIsDrawn() throws {
        try onUIThread {
            let host = WinUIRenderer.running { ShowingPage() }
            try XCTUnwrap(host.views(WinUIButtonView.self).first).invoke()
            _ = host.runtime.core.runJobs()
            let stack = try XCTUnwrap(host.views(WinUIStackView.self).first)
            let held = stack.heldViews()
            stack.setChildren([])
            stack.setChildren(held)

            let canvas = try XCTUnwrap(host.views(WinUICanvasView.self).first)
            host.settle { canvas.pixels(at: [(50, 10)]) == [Self.red] }
            XCTAssertEqual(canvas.pixels(at: [(50, 10)]), [Self.red])
        }
    }

    /// A canvas given more room draws again at its new size.
    func testACanvasDrawsAgainAtANewSize() throws {
        try onUIThread {
            let host = WinUIRenderer.running { PressPage() }
            let canvas = try XCTUnwrap(host.views(WinUICanvasView.self).first)
            host.settle { canvas.pixels(at: [(50, 10)]) == [Self.red] }
            XCTAssertEqual(canvas.pixels(at: [(50, 10), (150, 10)]), [Self.red, 0])

            try XCTUnwrap(host.views(WinUIButtonView.self).first).invoke()
            host.settle { canvas.pixels(at: [(150, 10)]) == [Self.red] }
            XCTAssertEqual(canvas.pixels(at: [(150, 10)]), [Self.red], "drawn again, wider")
        }
    }

    /// A canvas that leaves the tree is let go of, drawn and shown as it was.
    func testACanvasThatLeavesIsLetGoOf() throws {
        try onUIThread {
            let host = WinUIRenderer.running { PressPage() }
            host.settle { host.views(WinUICanvasView.self).first?.pixels(at: [(50, 10)]) == [Self.red] }
            let canvases = swiftomniui_winui_canvases()

            try XCTUnwrap(host.views(WinUIButtonView.self).last).invoke()
            host.settle { swiftomniui_winui_canvases() == canvases - 1 }

            XCTAssertEqual(swiftomniui_winui_canvases(), canvases - 1, "the canvas outlived its element")
        }
    }

    /// The colours at `points` of a canvas `width` by `height` showing `drawing`, standing at the corner of a
    /// stack larger than it, once the drawing paints one of them.
    private func drawn(
        width: Double, height: Double, at points: [(Double, Double)],
        @DrawingBuilder _ drawing: @escaping @Sendable () -> [DrawCommand]
    ) throws -> [UInt32] {
        try onUIThread {
            let host = WinUIRenderer.running {
                VStack {
                    Canvas(drawing)
                        .frame(width: width)
                        .frame(height: height)
                        .horizontalAlignment(.start)
                }
                .frame(width: width + 40)
                .frame(height: height + 40)
                .horizontalAlignment(.start)
                .verticalAlignment(.start)
            }
            let stack = try XCTUnwrap(host.views(WinUIStackView.self).first)
            XCTAssertEqual(host.views(WinUICanvasView.self).count, 1, "one canvas")
            host.settle { stack.pixels(at: points).contains { $0 != 0 } }
            return stack.pixels(at: points)
        }
    }
}
