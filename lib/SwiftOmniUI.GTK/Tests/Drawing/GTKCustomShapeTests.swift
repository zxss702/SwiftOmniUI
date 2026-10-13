// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIGTK
import XCTest

// A concave bubble with a cubic tail, mirrored for incoming messages.
private struct NativeBubbleShape: Shape {
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

private struct NativeHoleShape: Shape {
    var hole: Bool
    func path(in rect: Rect) -> Path {
        var path = Path(Rect(5, 5, rect.width - 10, rect.height - 10))
        if hole { path.addEllipse(in: Rect(30, 10, 40, 40)) }
        return path
    }
}

final class GTKCustomShapeTests: XCTestCase {
    private static let red: UInt32 = 0xFFFF_0000

    func testLocalCoordinatesRetainMarginsAndNegativeCoordinatesAreDrawn() throws {
        try onUIThread {
            let host = GTKRenderer.running {
                VStack {
                    Path(Rect(-10, 10, 40, 20)).fill(.red).frame(width: 100, height: 60)
                }.frame(width: 100, height: 60)
            }
            let stack = try XCTUnwrap(host.views(GTKStackView.self).first)
            let points: [(Double, Double)] = [(5, 20), (25, 20), (50, 30), (10, 5)]
            host.settle { stack.pixels(at: points) == [Self.red, Self.red, 0, 0] }
            XCTAssertEqual(stack.pixels(at: points), [Self.red, Self.red, 0, 0])
        }
    }

    func testBubbleTailsConcavityParameterChangesAndResizeKeepTheControl() throws {
        try onUIThread {
            let right = State(wrappedValue: true), width = State(wrappedValue: 100.0)
            let host = GTKRenderer.running(reducesMotion: true) {
                VStack {
                    NativeBubbleShape(right: right.wrappedValue).fill(.red).frame(width: width.wrappedValue, height: 60)
                }.horizontalAlignment(.start).verticalAlignment(.start)
            }
            let shape = try XCTUnwrap(host.views(GTKShapeView.self).first)
            let stack = try XCTUnwrap(host.views(GTKStackView.self).first)
            let points: [(Double, Double)] = [(50, 25), (94, 56), (83, 56), (6, 56)]
            host.settle { stack.pixels(at: points) == [Self.red, Self.red, 0, 0] }
            XCTAssertEqual(stack.pixels(at: points), [Self.red, Self.red, 0, 0])
            right.wrappedValue = false
            host.settle { stack.pixels(at: points) == [Self.red, 0, 0, Self.red] }
            XCTAssertEqual(stack.pixels(at: points), [Self.red, 0, 0, Self.red])
            width.wrappedValue = 140
            host.settle { stack.pixels(at: [(130, 25)]) == [Self.red] }
            XCTAssertEqual(stack.pixels(at: [(130, 25)]), [Self.red])
            XCTAssertTrue(host.views(GTKShapeView.self).first === shape)
        }
    }

    func testCustomShapeKeepsItsGradientAndLowOpacityWhileSpacerStaysTransparent() throws {
        try onUIThread {
            let host = GTKRenderer.running {
                VStack(spacing: 0) {
                    NativeBubbleShape(right: true)
                        .foregroundStyle(LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing))
                        .frame(width: 100, height: 60)
                    NativeBubbleShape(right: false).fill(.black.opacity(0.03)).foregroundStyle(.red)
                        .frame(width: 100, height: 60)
                    Spacer().frame(width: 100, height: 20).background { Color.blue }.foregroundStyle(.red)
                }.horizontalAlignment(.start).verticalAlignment(.start)
            }
            let stack = try XCTUnwrap(host.views(GTKStackView.self).first)
            let points: [(Double, Double)] = [(5, 25), (95, 25), (50, 85), (1, 61), (50, 130)]
            host.settle {
                let samples = stack.pixels(at: points)
                return samples.count == 5 && samples[0] >> 24 == 255 && samples[2] >> 24 > 0
                    && samples[4] == 0xFF00_00FF
            }
            let samples = stack.pixels(at: points)
            XCTAssertGreaterThan(samples[0] >> 16 & 0xFF, 0xE0)
            XCTAssertGreaterThan(samples[1] & 0xFF, 0xE0)
            XCTAssertEqual(Double(samples[2] >> 24), 8, accuracy: 1)
            XCTAssertEqual(samples[2] & 0x00FF_FFFF, 0)
            XCTAssertEqual(samples[3], 0)
            XCTAssertEqual(samples[4], 0xFF00_00FF)
        }
    }

    func testEvenOddFillAndPathClipLeaveAHoleAndUpdateInPlace() throws {
        try onUIThread {
            let hole = State(wrappedValue: true)
            let host = GTKRenderer.running(reducesMotion: true) {
                VStack {
                    Rectangle().fill(.red).frame(width: 100, height: 60)
                        .clipShape(NativeHoleShape(hole: hole.wrappedValue), style: FillStyle(eoFill: true, antialiased: true))
                }.horizontalAlignment(.start).verticalAlignment(.start)
            }
            let clip = try XCTUnwrap(host.views(GTKZStackView.self).first)
            let stack = try XCTUnwrap(host.views(GTKStackView.self).first)
            let points: [(Double, Double)] = [(10, 30), (50, 30), (1, 1)]
            host.settle { stack.pixels(at: points) == [Self.red, 0, 0] }
            XCTAssertEqual(stack.pixels(at: points), [Self.red, 0, 0])
            hole.wrappedValue = false
            host.settle { stack.pixels(at: points) == [Self.red, Self.red, 0] }
            XCTAssertEqual(stack.pixels(at: points), [Self.red, Self.red, 0])
            XCTAssertTrue(host.views(GTKZStackView.self).first === clip)
            clip.setPathClip([], evenOdd: false)
            host.settle { stack.pixels(at: points) == [0, 0, 0] }
            XCTAssertEqual(stack.pixels(at: points), [0, 0, 0])
            clip.setPathClip(nil, evenOdd: false)
            host.settle { stack.pixels(at: points) == [Self.red, Self.red, Self.red] }
            XCTAssertEqual(stack.pixels(at: points), [Self.red, Self.red, Self.red])
        }
    }

    func testASegmentAfterCloseStartsAtTheClosedSubpathOrigin() throws {
        try onUIThread {
            let host = GTKRenderer.running {
                VStack(spacing: 0) {
                    Path("M 10 10 L 40 10 L 10 40 Z L 90 40").fill(.red).frame(width: 100, height: 60)
                    Canvas { context, _ in
                        context.fill(Path("M 10 10 L 40 10 L 10 40 Z L 90 40"), with: .color(.red))
                    }.frame(width: 100, height: 60)
                }.horizontalAlignment(.start).verticalAlignment(.start)
            }
            let stack = try XCTUnwrap(host.views(GTKStackView.self).first)
            let points: [(Double, Double)] = [(15, 15), (50, 35), (15, 75), (50, 95)]
            let expected = [Self.red, 0, Self.red, 0]
            host.settle { stack.pixels(at: points) == expected }
            XCTAssertEqual(stack.pixels(at: points), expected)
        }
    }

    func testPublicDashLengthsAndPhaseAgreeAcrossWidthsAndCanvas() throws {
        for width in [2.0, 4.0] {
            try onUIThread {
                let host = GTKRenderer.running {
                    VStack(spacing: 0) {
                        Path("M 0 10 L 100 10").stroke(.red,
                            style: StrokeStyle(lineWidth: width, dash: [8, 4], dashPhase: 0))
                            .frame(width: 100, height: 20)
                        Canvas { context, _ in
                            context.stroke(Path("M 0 10 L 100 10"), with: .color(.red),
                                style: StrokeStyle(lineWidth: width, dash: [8, 4], dashPhase: 0))
                        }.frame(width: 100, height: 20)
                        Path("M 0 10 L 100 10").stroke(.red,
                            style: StrokeStyle(lineWidth: width, dash: [8, 4], dashPhase: 6))
                            .frame(width: 100, height: 20)
                        Canvas { context, _ in
                            context.stroke(Path("M 0 10 L 100 10"), with: .color(.red),
                                style: StrokeStyle(lineWidth: width, dash: [8, 4], dashPhase: 6))
                        }.frame(width: 100, height: 20)
                    }.horizontalAlignment(.start).verticalAlignment(.start)
                }
                let stack = try XCTUnwrap(host.views(GTKStackView.self).first)
                let points: [(Double, Double)] = [(3, 10), (10, 10), (3, 30), (10, 30), (3, 50), (10, 50), (3, 70), (10, 70)]
                let expected = [Self.red, 0, Self.red, 0, 0, Self.red, 0, Self.red]
                host.settle { stack.pixels(at: points) == expected }
                XCTAssertEqual(stack.pixels(at: points), expected)
            }
        }
    }

    func testShapePathAndCanvasDrawTheSameCurvesAndFillRule() throws {
        try onUIThread {
            let host = GTKRenderer.running {
                VStack(spacing: 0) {
                    NativeHoleShape(hole: true).fill(.red, style: FillStyle(eoFill: true, antialiased: true))
                        .frame(width: 100, height: 60)
                    NativeHoleShape(hole: true).path(in: Rect(0, 0, 100, 60))
                        .fill(.red, style: FillStyle(eoFill: true, antialiased: true)).frame(width: 100, height: 60)
                    Canvas { context, size in
                        context.fill(NativeHoleShape(hole: true).path(in: Rect(0, 0, size.width, size.height)),
                            with: .color(.red), style: FillStyle(eoFill: true, antialiased: true))
                    }.frame(width: 100, height: 60)
                }.horizontalAlignment(.start).verticalAlignment(.start)
            }
            let stack = try XCTUnwrap(host.views(GTKStackView.self).first)
            let points: [(Double, Double)] = [(10, 30), (50, 30), (10, 90), (50, 90), (10, 150), (50, 150)]
            let expected = [Self.red, 0, Self.red, 0, Self.red, 0]
            host.settle { stack.pixels(at: points) == expected }
            XCTAssertEqual(stack.pixels(at: points), expected)
        }
    }
}
