// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) @testable import SwiftOmniUICore
import XCTest

/// The SwiftUI drawing surface: a `Path` written point by point, the calls a
/// `GraphicsContext` gathers, and the closure form of `Canvas`.
@MainActor final class CanvasTests: XCTestCase {
    /// A path written point by point reads back as the SVG the string form takes.
    func testAPathWrittenByStatementsReadsAsSVG() {
        var path = Path()
        path.move(to: Point(x: 1, y: 2))
        path.addLine(to: Point(x: 3, y: 4))
        path.addCurve(to: Point(x: 5, y: 6), control1: Point(x: 1, y: 1), control2: Point(x: 4, y: 4))
        path.closeSubpath()

        XCTAssertEqual(path.svg, "M 1.0,2.0 L 3.0,4.0 C 1.0,1.0 4.0,4.0 5.0,6.0 Z")
        XCTAssertEqual(path.node.props[PathContract.commands.token], .numbers(path.geometry.numbers))
        XCTAssertNil(path.node.props[PathContract.data.token])
    }

    /// The closure form writes on an empty path, the way SwiftUI's does.
    func testAPathWrittenByItsClosure() {
        let path = Path { path in
            path.move(to: Point(x: 1, y: 0))
            path.addLine(to: Point(x: 2, y: 0))
        }

        XCTAssertEqual(path.svg, "M 1.0,0.0 L 2.0,0.0")
    }

    /// The geometry initials draw the shape they name: an ellipse closed by
    /// two arcs, a rounded rectangle of four lines and four quarter arcs.
    func testAGeometryPathDrawsTheShapeItNames() throws {
        let ellipse = try XCTUnwrap(HostPath(svg: Path(ellipseIn: Rect(0, 0, 20, 10)).svg)).arcsAsCubics
        XCTAssertEqual(ellipse.first, .move(Point(x: 10, y: 0)))
        XCTAssertEqual(ellipse.last, .close)
        XCTAssertEqual(ellipse.filter { $0 == .close }.count, 1)
        XCTAssertEqual(ellipse.filter {
            if case .cubic = $0 { return true }; return false
        }.count, 4, "two half-turns, a quarter drawn per curve")

        let rounded = try XCTUnwrap(
            HostPath(svg: Path(roundedRect: Rect(0, 0, 10, 10), cornerRadius: 2).svg)).arcsAsCubics
        XCTAssertEqual(rounded.filter {
            if case .line = $0 { return true }; return false
        }.count, 4)
        XCTAssertEqual(rounded.filter {
            if case .cubic = $0 { return true }; return false
        }.count, 4)
        XCTAssertEqual(rounded.last, .close)
    }

    /// A fill gathers colour, rule and path; a stroke colour, style and path -
    /// the same records `Draw` writes.
    func testAGraphicsContextGathersACanvassDrawing() {
        var context = GraphicsContext()
        context.fill(Path("M 0,0 L 4,4"), with: .color(.red))
        context.fill(Path("M 0,0 Z"), with: .color(.red), style: FillStyle(eoFill: true, antialiased: true))
        context.stroke(
            Path("M 0,0 L 1,1"), with: .color(.blue),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        context.stroke(Path("M 2,2 L 3,3"), with: .color(.blue), lineWidth: 1)

        XCTAssertEqual(context.commands, [
            Draw.fillColor(.red), Draw.fillStyle(eoFill: false), Draw.fillGeometry(Path("M 0,0 L 4,4")),
            Draw.fillColor(.red), Draw.fillStyle(eoFill: true), Draw.fillGeometry(Path("M 0,0 Z")),
            Draw.strokeColor(.blue), Draw.completeStrokeStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)),
            Draw.drawGeometry(Path("M 0,0 L 1,1")),
            Draw.strokeColor(.blue), Draw.completeStrokeStyle(StrokeStyle(lineWidth: 1)),
            Draw.drawGeometry(Path("M 2,2 L 3,3")),
        ])
    }

    /// A drawn text is the `drawText` record, the colour and size it wears
    /// written ahead of it under a state saved for them - the same records
    /// `Draw` writes, the `at` anchor standing its box on the point.
    func testAGraphicsContextDrawsAText() {
        var context = GraphicsContext()
        context.draw(
            Text("Hello"),
            in: Rect(0, 0, 120, 40),
            horizontalAlignment: .center, verticalAlignment: .center)
        context.draw(
            Text("!").foregroundStyle(.red).fontSize(20),
            at: Point(x: 10, y: 20), anchor: .topLeading)
        context.draw(Text("a") + Text("b"), at: Point(x: 60, y: 20))

        XCTAssertEqual(context.commands, [
            Draw.drawText(
                "Hello", x: 0, y: 0, width: 120, height: 40,
                horizontalAlignment: .center, verticalAlignment: .center),
            Draw.saveState(),
            Draw.foregroundStyle(.red),
            Draw.fontSize(20),
            Draw.drawText("!", x: 10, y: 20, width: 1_000_000, height: 1_000_000),
            Draw.restoreState(),
            Draw.drawText(
                "ab", x: 60 - 500_000, y: 20 - 500_000, width: 1_000_000, height: 1_000_000,
                horizontalAlignment: .center, verticalAlignment: .center),
        ])
    }

    /// The closure form measures its room first, then draws with the size it
    /// settled - a GeometryReader's report building the drawing.
    func testAClosuredCanvasDrawsFromItsSize() throws {
        let canvas = Canvas { context, size in
            context.fill(
                Path(roundedRect: Rect(0, 0, size.width, 40), cornerRadius: 8),
                with: .color(.cornflowerBlue))
        }

        let renders = Renders()
        let first = renders.render(canvas.node)
        XCTAssertFalse(first.subtree.contains { $0.type == CanvasContract.nodeType }, "no invented zero-size drawing")
        XCTAssertNil(first.events?[ViewContract.frameChanged.token], "drawing has no dependency on window coordinates")
        let frame = try XCTUnwrap(first.events?[ViewContract.drawingSizeChanged.token])
        renders.fire(frame, with: [.numbers([120, 80])])
        let second = renders.render(canvas.node, changed: Renderer.shared.pendingChanges)
        let leaf = try XCTUnwrap(second.subtree.first { $0.type == CanvasContract.nodeType })
        let commands = try XCTUnwrap(leaf.props["drawable"]?.values?.compactMap(DrawCommand.init(propValue:)))
        XCTAssertEqual(commands, [
            Draw.fillColor(.cornflowerBlue), Draw.fillStyle(eoFill: false),
            Draw.fillGeometry(Path(roundedRect: Rect(0, 0, 120, 40), cornerRadius: 8)),
        ])
        Renderer.shared.clearInvalidation()
        renders.fire(frame, with: [.numbers([120, 80])])
        XCTAssertFalse(Renderer.shared.needsRender, "an unchanged local drawing size needs no new drawing")
    }
}
