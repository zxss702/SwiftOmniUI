// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) @testable import SwiftOmniUICore
@_spi(Host) @testable import SwiftOmniUIHost
import XCTest

@MainActor final class StructuredPathDrawingTests: XCTestCase {
    func testShapePathAndCanvasUseTheSameGeometryAndArcConversion() throws {
        let path = Path("M -10 20 Q 5 -5 20 20 C 40 50 60 -10 80 20 A 10 20 30 0 1 100 40 Z")
        var context = GraphicsContext()
        context.fill(path, with: .color(.red), style: FillStyle(eoFill: true, antialiased: true))
        let decoded = CanvasInstruction.instructions(context.commands)
        XCTAssertEqual(decoded.last, .fillPath(path.geometry.arcsAsCubics))
        XCTAssertEqual(try XCTUnwrap(HostPath(numbers: path.node.props[PathContract.commands.token]!.numbers!)), path.geometry)
        let relay = HostDrawing(context.commands)
        XCTAssertEqual(Array(relay.ints.suffix(2)), [16, Int32(path.geometry.arcsAsCubics.count)])
        XCTAssertEqual(relay.numbers, path.geometry.arcsAsCubics.flatMap(\.numbers))
    }

    func testCompleteStrokeStyleCrossesTheRelayAndSavedStateWithoutLosingUnits() {
        let style = StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .bevel, miterLimit: 3, dash: [8, 4], dashPhase: 2)
        var context = GraphicsContext()
        context.stroke(Path("M 10 20 L 90 20"), with: .color(.blue), style: style)
        let instructions = CanvasInstruction.instructions(context.commands)
        XCTAssertEqual(instructions[1], .completeStrokeStyle(style))
        let relay = HostDrawing(context.commands)
        XCTAssertEqual(Array(relay.ints.dropFirst(2).prefix(4)), [27, 1, 1, 2])
        XCTAssertEqual(Array(relay.numbers.prefix(5)), [4, 3, 2, 8, 4])
        var pen = CanvasPen()
        XCTAssertTrue(pen.take(instructions[1]))
        XCTAssertTrue(pen.take(.saveState))
        XCTAssertTrue(pen.take(.completeStrokeStyle(StrokeStyle(lineWidth: 1))))
        XCTAssertTrue(pen.take(.restoreState))
        XCTAssertEqual(pen.strokeWidth, 4)
        XCTAssertEqual(pen.strokeDash, [8, 4])
        XCTAssertEqual(pen.strokePhase, 2)
        XCTAssertEqual(pen.strokeMiter, 3)
        XCTAssertEqual(pen.strokeCap, .round)
        XCTAssertEqual(pen.strokeJoin, .bevel)
    }

    func testLegacySVGAndStrokeRecordsKeepTheirNumbersAndMeaning() {
        let instructions = CanvasInstruction.instructions([
            Draw.strokeStyle(width: 3, cap: .square, join: .round), Draw.drawPath("M 0 0 L 20 0"),
        ])
        XCTAssertEqual(instructions, [.strokeStyle(width: 3, cap: .square, join: .round),
            .drawPath([.move(.zero), .line(Point(20, 0))])])
        let relay = HostDrawing([Draw.strokeStyle(width: 3, cap: .square, join: .round)])
        XCTAssertEqual(relay.ints, [23, 2, 2])
        XCTAssertEqual(relay.numbers, [3])
    }
}
