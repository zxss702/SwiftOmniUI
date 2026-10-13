// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@_spi(Host) @testable import SwiftOmniUICore

@MainActor private final class ShapeProbe {
    var rectangles: [Rect] = []
}

/// A custom Shape declares only its geometry, with no node or body storage.
private struct NotchedShape: Shape {
    var depth: Double
    let probe: ShapeProbe
    func path(in rect: Rect) -> Path {
        probe.rectangles.append(rect)
        return Path {
            $0.move(to: Point(0, 0))
            $0.addLine(to: Point(rect.width, 0))
            $0.addQuadCurve(to: Point(rect.width, rect.height), control: Point(rect.width - depth, rect.height / 2))
            $0.addLine(to: Point(0, rect.height))
            $0.closeSubpath()
        }
    }
}

@MainActor final class CustomShapeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Renderer.shared.clearInvalidation()
        Renderer.shared.clearStates()
    }

    private func report(_ id: Int, _ renders: Renders, width: Double, height: Double, x: Double = 0) {
        renders.fire(id, with: [.numbers([x, 0, width, height, x, 0, 0, 0, width, height])])
    }

    func testOnlyActualSizeBuildsGeometryAndKeepsTheNativePathIdentity() throws {
        let probe = ShapeProbe(), renders = Renders()
        func tree(_ depth: Double = 5) -> Node { NotchedShape(depth: depth, probe: probe).fill(.red).node }
        let first = renders.render(tree())
        XCTAssertEqual(first.type, PathContract.nodeType)
        XCTAssertEqual(first.props[PathContract.commands.token], .numbers([]))
        XCTAssertTrue(probe.rectangles.isEmpty)
        let event = try XCTUnwrap(first.events?[ViewContract.frameChanged.token])
        report(event, renders, width: 100, height: 50)
        let second = renders.render(tree(), changed: Renderer.shared.pendingChanges)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(probe.rectangles, [Rect(0, 0, 100, 50)])
        let original = try XCTUnwrap(second.props[PathContract.commands.token]?.numbers)
        Renderer.shared.clearInvalidation()

        // Changing scroll position/origin is not a shape geometry change.
        report(event, renders, width: 100, height: 50, x: 30)
        XCTAssertTrue(Renderer.shared.pendingChanges.isEmpty)
        report(event, renders, width: 100, height: 50)
        XCTAssertTrue(Renderer.shared.pendingChanges.isEmpty)
        XCTAssertEqual(probe.rectangles.count, 1)

        let parameter = renders.render(tree(20))
        XCTAssertEqual(parameter.id, first.id)
        XCTAssertNotEqual(parameter.props[PathContract.commands.token]?.numbers, original)
        XCTAssertEqual(probe.rectangles.last, Rect(0, 0, 100, 50))
        report(event, renders, width: 140, height: 70)
        let resized = renders.render(tree(20), changed: Renderer.shared.pendingChanges)
        XCTAssertEqual(resized.id, first.id)
        XCTAssertEqual(probe.rectangles.last, Rect(0, 0, 140, 70))
        Renderer.shared.clearInvalidation()
    }

    func testCustomShapeInheritsTheWholeBrushAndExplicitFillWins() throws {
        let probe = ShapeProbe()
        let gradient = LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing)
        let inherited = Renders().render(NotchedShape(depth: 5, probe: probe).foregroundStyle(gradient).node)
        XCTAssertEqual(inherited.props[ShapeContract.fill.token], gradient.brush.propValue)
        let explicit = Renders().render(NotchedShape(depth: 5, probe: probe)
            .fill(.black.opacity(0.03), style: FillStyle(eoFill: true, antialiased: true))
            .foregroundStyle(gradient).node)
        XCTAssertEqual(explicit.props[ShapeContract.fill.token], Color.black.opacity(0.03).brush.propValue)
        XCTAssertEqual(explicit.props[ShapeContract.fillRule.token], FillRule.evenOdd.propValue)
    }

    func testCustomClipUsesTheAllocatedSizeAndEmptyIsDifferentFromNoClip() throws {
        let probe = ShapeProbe(), renders = Renders()
        func tree() -> Node { Rectangle().fill(.red).clipShape(NotchedShape(depth: 10, probe: probe)).node }
        let first = renders.render(tree())
        XCTAssertEqual(first.props[LayoutContract.clipPath.token], .numbers([]))
        let event = try XCTUnwrap(first.events?[ViewContract.frameChanged.token])
        report(event, renders, width: 80, height: 40)
        let second = renders.render(tree(), changed: Renderer.shared.pendingChanges)
        XCTAssertEqual(second.id, first.id)
        XCTAssertFalse(try XCTUnwrap(second.props[LayoutContract.clipPath.token]?.numbers).isEmpty)
        XCTAssertEqual(probe.rectangles.last, Rect(0, 0, 80, 40))
        let empty = Renders().render(Rectangle().clipShape(Path()).node)
        XCTAssertEqual(empty.props[LayoutContract.clipPath.token], .numbers([]))
        XCTAssertNil(Renders().render(Rectangle().node).props[LayoutContract.clipPath.token])
        Renderer.shared.clearInvalidation()
    }

    func testCustomBackgroundUsesTheShapeAdapter() {
        let patch = Renders().render(Text("bubble").background(.red, in: NotchedShape(depth: 10, probe: ShapeProbe())).node)
        let path = patch.subtree.first { $0.type == PathContract.nodeType }
        XCTAssertNotNil(path)
        XCTAssertEqual(path?.props[ShapeContract.fill.token], Color.red.brush.propValue)
    }

    func testCustomStrokeUsesTheSameCompleteStyleAsANativePath() {
        let style = StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .bevel,
                                miterLimit: 3, dash: [8, 4], dashPhase: 2)
        let custom = Renders().render(NotchedShape(depth: 10, probe: ShapeProbe()).stroke(.red, style: style).node)
        let native = Renders().render(Path().stroke(.red, style: style).node)
        for member in [ShapeContract.stroke.token, ShapeContract.strokeWidth.token,
                       ShapeContract.strokeLineCap.token, ShapeContract.strokeLineJoin.token,
                       ShapeContract.strokeMiterLimit.token, ShapeContract.strokeDashPattern.token,
                       ShapeContract.strokeDashOffset.token, ShapeContract.strokeDashInPathUnits.token,
                       ShapeContract.strokePhaseInPathUnits.token] {
            XCTAssertEqual(custom.props[member], native.props[member])
        }
        XCTAssertNil(custom.props[ShapeContract.fill.token])
    }

    func testStructuredGeometryRoundTripsArcsSubpathsAndNegativeCoordinates() throws {
        var path = Path(Rect(-20, 30, 60, 40))
        path.move(to: Point(5, 5))
        path.addQuadCurve(to: Point(40, 40), control: Point(-5, 60))
        path.addCurve(to: Point(80, 10), control1: Point(20, -20), control2: Point(70, 90))
        path.addRelativeArc(center: Point(80, 20), radius: 10, startAngle: .degrees(-90), delta: .degrees(270))
        path.closeSubpath()
        let restored = try XCTUnwrap(HostPath(numbers: path.geometry.numbers))
        XCTAssertEqual(restored, path.geometry)
        XCTAssertEqual(restored, HostPath(svg: path.svg))
        XCTAssertEqual(path.currentPoint, Point(5, 5))
        XCTAssertNil(path.node.props[ShapeContract.aspect.token])
        XCTAssertEqual(path.aspect(.center).node.props[ShapeContract.aspect.token], ContentMode.center.propValue)
        XCTAssertEqual(path.offsetBy(dx: 10, dy: -10).geometry.commands.first, .move(Point(-10, 20)))
    }

    func testSVGAndStructuredReplacementDoNotLeaveStaleGeometry() {
        let path = Path(Rect(10, 20, 30, 40)).fill(.red)
        let replaced = path.data("M -5 -10 l 20 0 z")
        XCTAssertEqual(replaced.geometry.commands, [.move(Point(-5, -10)), .line(Point(15, -10)), .close])
        XCTAssertEqual(replaced.node.props[ShapeContract.fill.token], Color.red.brush.propValue)
        XCTAssertTrue(path.data("M 0 0 L broken").isEmpty)
        XCTAssertTrue(Path("M NaN 0").isEmpty)
        XCTAssertTrue(Path().isEmpty)
        XCTAssertNil(HostPath(numbers: [2, 0, 0]))
        XCTAssertNil(HostPath(numbers: [0, .infinity, 0]))
        XCTAssertNil(HostPath(numbers: [9]))
    }

    func testGeometryModifiersAfterAFrameStillReplaceTheInnerPath() throws {
        let path = Path(Rect(10, 20, 30, 40)).frame(width: 100, height: 60)
            .data("M 2 3 L 4 5").stroke(.red, style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
        XCTAssertEqual(path.geometry.commands, [.move(Point(2, 3)), .line(Point(4, 5))])
        let patch = Renders().render(path.node)
        let inner = try XCTUnwrap(patch.subtree.first { $0.type == PathContract.nodeType })
        XCTAssertEqual(inner.props[PathContract.commands.token], .numbers([0, 2, 3, 1, 4, 5]))
        XCTAssertEqual(inner.props[ShapeContract.stroke.token], Color.red.brush.propValue)
        XCTAssertEqual(inner.props[ShapeContract.strokeDashPattern.token], .numbers([6, 3]))
    }

    func testRotatedArcUnderUnequalAxisScalingUsesTransformedCurves() {
        let path = Path("M 4 8 A 20 10 30 0 1 40 24")
        let transform = ViewTransform.scaleX(2).scaleY(3)
        let transformed = path.applying(transform).geometry.arcsAsCubics
        let flattened = Path { result in
            result.move(to: Point(4, 8))
            for curve in HostPath.arc(from: Point(4, 8), to: Point(40, 24), radiusX: 20, radiusY: 10,
                                     rotation: 30, largeArc: false, sweep: true) {
                if case .cubic(let a, let b, let end) = curve {
                    result.addCurve(to: end, control1: a, control2: b)
                }
            }
        }
        let expected = flattened.applying(transform).geometry.arcsAsCubics
        XCTAssertEqual(transformed, expected)
    }

    func testPublicStrokeWritesPathUnitsAndLegacySPIKeepsWidthUnits() {
        let style = StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .bevel, miterLimit: 3, dash: [8, 4], dashPhase: 2)
        let path = Path("M 0 0 L 100 0").stroke(.red, style: style)
        XCTAssertEqual(path.node.props[ShapeContract.strokeDashPattern.token], .numbers([8, 4]))
        XCTAssertEqual(path.node.props[ShapeContract.strokeDashOffset.token], .number(2))
        XCTAssertEqual(path.node.props[ShapeContract.strokeDashInPathUnits.token], .bool(true))
        let legacy = path.strokeDashPattern([2, 1]).strokeDashOffset(0.5)
        XCTAssertEqual(legacy.node.props[ShapeContract.strokeDashInPathUnits.token], .bool(false))
        XCTAssertEqual(path.node.props[ShapeContract.strokePhaseInPathUnits.token], .bool(true))
        let mixed = path.strokeDashOffset(0.5)
        XCTAssertEqual(mixed.node.props[ShapeContract.strokeDashInPathUnits.token], .bool(true))
        XCTAssertEqual(mixed.node.props[ShapeContract.strokePhaseInPathUnits.token], .bool(false))
        let solid = path.stroke(.red, style: StrokeStyle(lineWidth: 2))
        XCTAssertEqual(solid.node.props[ShapeContract.strokeDashPattern.token], .numbers([]))
        XCTAssertEqual(solid.node.props[ShapeContract.strokeDashOffset.token], .number(0))
    }
}
