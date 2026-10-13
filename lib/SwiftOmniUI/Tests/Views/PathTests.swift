// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) @testable import SwiftOmniUICore
import XCTest

/// `Path`'s imperative face: statements retain structured geometry, SVG export
/// round-trips it, and the arcs' ends land where the angles put them.
@MainActor final class PathTests: XCTestCase {
    /// Lines and quadratic curves write the commands they name.
    func testLinesAndQuadCurvesParseBack() throws {
        var path = Path()
        path.move(to: Point(0, 0))
        path.addLines([Point(10, 0), Point(10, 10)])
        path.addQuadCurve(to: Point(20, 20), control: Point(15, 15))
        path.closeSubpath()

        XCTAssertCommands(path, [
            .move(Point(0, 0)),
            .line(Point(10, 0)),
            .line(Point(10, 10)),
            .quadratic(control: Point(15, 15), end: Point(20, 20)),
            .close,
        ])
    }

    /// Rects come out closed, singly or in a run; the `Rect` initialiser
    /// writes the same outline `addRect` does.
    func testRectsDrawTheirOutline() throws {
        var path = Path()
        path.addRect(Rect(1, 2, 30, 40))
        path.addRects([Rect(0, 0, 1, 1), Rect(2, 2, 1, 1)])

        XCTAssertCommands(path, [
            .move(Point(1, 2)), .line(Point(31, 2)), .line(Point(31, 42)),
            .line(Point(1, 42)), .close,
            .move(Point(0, 0)), .line(Point(1, 0)), .line(Point(1, 1)),
            .line(Point(0, 1)), .close,
            .move(Point(2, 2)), .line(Point(3, 2)), .line(Point(3, 3)),
            .line(Point(2, 3)), .close,
        ])
        XCTAssertEqual(
            Path(Rect(1, 2, 30, 40)).svg,
            "M 1.0,2.0 L 31.0,2.0 L 31.0,42.0 L 1.0,42.0 Z")
    }

    /// An ellipse and a rounded rect join a path as their own closed
    /// subpaths, each bend an arc; a corner that stays square writes a line.
    func testEllipsesAndRoundedRectsJoinAsSubpaths() throws {
        var path = Path()
        path.addEllipse(in: Rect(0, 0, 20, 10))
        path.addRoundedRect(in: Rect(0, 0, 10, 10), cornerSize: Size(4, 2))

        let commands = try XCTUnwrap(HostPath(svg: path.svg)).commands
        XCTAssertEqual(commands.first, .move(Point(10, 0)))
        XCTAssertEqual(commands.filter { $0 == .close }.count, 2)
        XCTAssertEqual(commands.filter {
            if case .line = $0 { return true }; return false
        }.count, 4)
        XCTAssertEqual(commands.filter {
            if case .arc = $0 { return true }; return false
        }.count, 6, "two half turns of the ellipse, four corner bends")

        XCTAssertCommands(
            Path(roundedRect: Rect(0, 0, 10, 10),
                 cornerRadii: RectangleCornerRadii(topTrailing: 2)),
            [
                .move(Point(0, 0)),
                .line(Point(8, 0)),
                .arc(
                    radiusX: 2, radiusY: 2, rotation: 0,
                    largeArc: false, sweep: true, end: Point(10, 2)),
                .line(Point(10, 10)),
                .line(Point(0, 10)),
                .line(Point(0, 0)),
                .close,
            ])
    }

    /// `addArc` reaches the arc's start with a move - or a line where the
    /// outline already stands - then turns the way `clockwise` says, `false`
    /// growing the angle, which reads clockwise with y pointing down.
    func testArcsReachTheirStartAndTurnAsTold() {
        var quarter = Path()
        quarter.addArc(
            center: Point(10, 10), radius: 10,
            startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        XCTAssertCommands(quarter, [
            .move(Point(20, 10)),
            .arc(
                radiusX: 10, radiusY: 10, rotation: 0,
                largeArc: false, sweep: true, end: Point(10, 20)),
        ])

        var turned = Path()
        turned.addArc(
            center: Point(10, 10), radius: 10,
            startAngle: .degrees(0), endAngle: .degrees(90), clockwise: true)
        XCTAssertCommands(turned, [
            .move(Point(20, 10)),
            .arc(
                radiusX: 10, radiusY: 10, rotation: 0,
                largeArc: true, sweep: false, end: Point(10, 20)),
        ])

        var joined = Path()
        joined.move(to: Point(0, 0))
        joined.addRelativeArc(
            center: Point(10, 10), radius: 5,
            startAngle: .degrees(180), delta: .degrees(90))
        XCTAssertCommands(joined, [
            .move(Point(0, 0)),
            .line(Point(5, 10)),
            .arc(
                radiusX: 5, radiusY: 5, rotation: 0,
                largeArc: false, sweep: true, end: Point(10, 5)),
        ])
    }

    /// A full turn is two half turns meeting back at the start; a zero delta
    /// only reaches the start; a negative one turns the other way.
    func testFullCirclesEmptyArcsAndNegativeTurns() {
        var whole = Path()
        whole.addRelativeArc(
            center: Point(10, 10), radius: 5,
            startAngle: .degrees(0), delta: .degrees(360))
        XCTAssertCommands(whole, [
            .move(Point(15, 10)),
            .arc(radiusX: 5, radiusY: 5, rotation: 0, largeArc: true, sweep: true, end: Point(5, 10)),
            .arc(radiusX: 5, radiusY: 5, rotation: 0, largeArc: true, sweep: true, end: Point(15, 10)),
        ])

        var empty = Path()
        empty.addRelativeArc(
            center: Point(10, 10), radius: 5,
            startAngle: .degrees(0), delta: .zero)
        XCTAssertCommands(empty, [.move(Point(15, 10))])

        var back = Path()
        back.addRelativeArc(
            center: Point(10, 10), radius: 10,
            startAngle: .degrees(0), delta: .degrees(-90))
        XCTAssertCommands(back, [
            .move(Point(20, 10)),
            .arc(
                radiusX: 10, radiusY: 10, rotation: 0,
                largeArc: false, sweep: false, end: Point(10, 0)),
        ])
    }

    /// A tangent arc lands its bend between the two tangent lines - here the
    /// run right, then down, rounds clockwise.
    func testTangentArcsRoundTheCorner() {
        var path = Path()
        path.move(to: Point(0, 0))
        path.addArc(tangent1End: Point(10, 0), tangent2End: Point(10, 10), radius: 5)

        XCTAssertCommands(path, [
            .move(Point(0, 0)),
            .line(Point(5, 0)),
            .arc(
                radiusX: 5, radiusY: 5, rotation: 0,
                largeArc: false, sweep: true, end: Point(10, 5)),
        ])

        // Nowhere to bend from: the corner is only arrived at.
        var nowhere = Path()
        nowhere.addArc(tangent1End: Point(10, 0), tangent2End: Point(10, 10), radius: 5)
        XCTAssertCommands(nowhere, [.move(Point(10, 0))])
    }

    /// `addPath` takes the other outline as it is, subpaths and all.
    func testAPathTakesAnotherWhole() throws {
        var path = Path("M 0,0 L 1,1")
        path.addPath(Path(ellipseIn: Rect(0, 0, 20, 10)))
        path.addPath(Path())

        let commands = try XCTUnwrap(HostPath(svg: path.svg)).commands
        XCTAssertEqual(Array(commands.prefix(2)), [.move(Point(0, 0)), .line(Point(1, 1))])
        XCTAssertEqual(commands[2], .move(Point(10, 0)))
        XCTAssertEqual(commands.count, 6)
    }

    /// `applying` moves every point, sizes an arc's radii under an even or
    /// axis-square sizing, and turns an arc's ellipse under a turn.
    func testApplyingTransformsEveryPoint() throws {
        XCTAssertCommands(Path("M 1,2 L 3,4").applying(.translate(10, 20)), [
            .move(Point(11, 22)),
            .line(Point(13, 24)),
        ])

        XCTAssertCommands(Path(ellipseIn: Rect(0, 0, 20, 10)).applying(.scale(2)), [
            .move(Point(20, 0)),
            .arc(
                radiusX: 20, radiusY: 10, rotation: 0,
                largeArc: true, sweep: true, end: Point(20, 20)),
            .arc(
                radiusX: 20, radiusY: 10, rotation: 0,
                largeArc: true, sweep: true, end: Point(20, 0)),
            .close,
        ])

        let turned = try XCTUnwrap(
            HostPath(svg: Path("M 0,0 A 5,3 0 0 1 10,0").applying(.rotate(45)).svg))
        guard case .arc(_, _, let rotation, _, _, _) = turned.commands[1] else {
            return XCTFail("\(turned.commands)")
        }
        XCTAssertEqual(rotation, 45, accuracy: 1e-9)
    }

    /// Under a lean an arc is no ellipse a host can draw directly, so the
    /// transformed path draws it as the curves it flattens to.
    func testApplyingALeanDrawsArcsAsCurves() throws {
        let leaned = Path("M 0,0 A 5,5 0 0 1 10,0").applying(.skew(45, 0))
        let commands = try XCTUnwrap(HostPath(svg: leaned.svg)).commands

        XCTAssertFalse(commands.contains {
            if case .arc = $0 { return true }; return false
        })
        XCTAssertEqual(commands.filter {
            if case .cubic = $0 { return true }; return false
        }.count, 2, "the half turn as two quarter-turn curves")
    }

    /// `offsetBy` is the translate form of `applying`.
    func testOffsetByMovesEveryPoint() {
        XCTAssertCommands(Path("M 1,2 L 3,4").offsetBy(dx: 10, dy: 20), [
            .move(Point(11, 22)),
            .line(Point(13, 24)),
        ])
    }

    /// An empty path is empty and stands nowhere; a closed one stands back
    /// where its subpath began.
    func testIsEmptyAndCurrentPoint() {
        XCTAssertTrue(Path().isEmpty)
        XCTAssertNil(Path().currentPoint)

        var path = Path()
        path.move(to: Point(1, 1))
        path.addLine(to: Point(2, 2))
        XCTAssertFalse(path.isEmpty)
        XCTAssertEqual(path.currentPoint, Point(2, 2))
        path.closeSubpath()
        XCTAssertEqual(path.currentPoint, Point(1, 1))
    }

    /// The path's commands as parsed back, each kind equal and its numbers to
    /// drawing accuracy.
    private func XCTAssertCommands(
        _ path: Path, _ expected: [HostPathCommand],
        accuracy: Double = 1e-9,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        guard let commands = HostPath(svg: path.svg)?.commands else {
            return XCTFail("unparseable: \(path.svg)", file: file, line: line)
        }
        XCTAssertEqual(commands.count, expected.count, "\(path.svg)", file: file, line: line)
        for (command, wanted) in zip(commands, expected) {
            XCTAssertTrue(command.matches(wanted, accuracy: accuracy),
                          "\(command) != \(wanted)", file: file, line: line)
        }
    }
}

extension HostPathCommand {
    /// The same command to drawing accuracy: kinds equal, numbers near.
    fileprivate func matches(_ other: HostPathCommand, accuracy: Double) -> Bool {
        func near(_ a: Point, _ b: Point) -> Bool {
            abs(a.x - b.x) <= accuracy && abs(a.y - b.y) <= accuracy
        }
        switch (self, other) {
        case (.move(let a), .move(let b)):
            return near(a, b)
        case (.line(let a), .line(let b)):
            return near(a, b)
        case (.cubic(let a1, let a2, let ae), .cubic(let b1, let b2, let be)):
            return near(a1, b1) && near(a2, b2) && near(ae, be)
        case (.quadratic(let ac, let ae), .quadratic(let bc, let be)):
            return near(ac, bc) && near(ae, be)
        case (
            .arc(let aX, let aY, let aRotation, let aLarge, let aSweep, let aEnd),
            .arc(let bX, let bY, let bRotation, let bLarge, let bSweep, let bEnd)):
            return abs(aX - bX) <= accuracy && abs(aY - bY) <= accuracy
                && abs(aRotation - bRotation) <= accuracy
                && aLarge == bLarge && aSweep == bSweep && near(aEnd, bEnd)
        case (.close, .close):
            return true
        default:
            return false
        }
    }
}
