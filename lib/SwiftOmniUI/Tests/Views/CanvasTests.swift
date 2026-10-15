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

    /// A closure Canvas is in the first patch. Native allocation asks for its
    /// drawing in that same pass, and an unchanged allocation does no work.
    func testAClosuredCanvasDrawsOnItsFirstAllocation() throws {
        var calls = 0
        let canvas = Canvas { context, size in
            calls += 1
            context.fill(
                Path(roundedRect: Rect(0, 0, size.width, 40), cornerRadius: 8),
                with: .color(.cornflowerBlue))
        }

        let differ = Differ()
        let first = differ.reconcile(nil, with: canvas.node)
        XCTAssertEqual(first.node.type, CanvasContract.nodeType)
        XCTAssertNil(first.patch.properties[.drawable], "allocation, not a later geometry render, draws the first frame")
        XCTAssertEqual(calls, 0)

        let commands = try XCTUnwrap(differ.canvasDrawing(for: first.node.id, size: Size(120, 80)))
        let expected: [DrawCommand] = [
            Draw.fillColor(.cornflowerBlue), Draw.fillStyle(eoFill: false),
            Draw.fillGeometry(Path(roundedRect: Rect(0, 0, 120, 40), cornerRadius: 8)),
        ]
        XCTAssertEqual(commands, expected)
        XCTAssertEqual(first.node.props[.drawable], expected.propValue)
        XCTAssertEqual(calls, 1)

        _ = differ.canvasDrawing(for: first.node.id, size: Size(120, 80))
        XCTAssertEqual(calls, 1, "a repeated native Arrange does not rerun the renderer")
        _ = differ.canvasDrawing(for: first.node.id, size: Size(160, 80))
        XCTAssertEqual(calls, 2, "a new allocation draws with the new local size")
        XCTAssertNil(first.node.events[.drawingSizeChanged], "the drawing does not wait for geometry feedback")
    }

    /// Canvas state reads belong to the drawing, not the surrounding view.
    /// A changed read updates its drawable and an unrelated state does not.
    func testAClosuredCanvasTracksOnlyItsDrawingReads() throws {
        Renderer.shared.clearInvalidation()
        let tint = State(wrappedValue: false)
        let unrelated = State(wrappedValue: false)
        var calls = 0
        let canvas = Canvas { context, size in
            calls += 1
            context.fill(Path(Rect(0, 0, size.width, size.height)),
                         with: .color(tint.wrappedValue ? .blue : .red))
        }
        let differ = Differ()
        let first = differ.reconcile(nil, with: canvas.node)
        let before = try XCTUnwrap(differ.canvasDrawing(for: first.node.id, size: Size(80, 44)))
        XCTAssertEqual(calls, 1)
        XCTAssertNotNil(before.first?.arguments.first?.color,
                        "themed Canvas colours resolve before reaching a native host")

        unrelated.wrappedValue = true
        let unchanged = differ.revisit(first.node, changed: Renderer.shared.pendingChanges)
        XCTAssertTrue(unchanged.patch.properties.isEmpty)
        XCTAssertEqual(calls, 1)
        Renderer.shared.clearInvalidation()

        tint.wrappedValue = true
        let changed = differ.revisit(unchanged.node, changed: Renderer.shared.pendingChanges)
        XCTAssertEqual(calls, 2)
        XCTAssertNotNil(changed.patch.properties[.drawable])
        XCTAssertNotEqual(changed.node.props[.drawable], before.propValue)
        XCTAssertNotNil(changed.node.props[.drawable], "the new drawing remains host-readable")
        XCTAssertEqual(changed.node.id, first.node.id)

        differ.forget(changed.node)
        XCTAssertNil(differ.canvasDrawing(for: first.node.id, size: Size(80, 44)),
                     "an unmounted Canvas cannot keep a drawing request alive")
        Renderer.shared.clearInvalidation()
    }
}
