// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIGTK
import XCTest

final class GTKShapeViewTests: XCTestCase {
    private static let red: UInt32 = 0xFFFF_0000
    private static let blue: UInt32 = 0xFF00_00FF

    func testASpacerDoesNotPaintOverItsBackgroundWhenItInheritsAForeground() throws {
        try onUIThread {
            let host = GTKRenderer.running {
                Spacer().frame(width: 100, height: 20).background { Color.blue }.foregroundStyle(.red)
            }
            let stack = try XCTUnwrap(host.views(GTKZStackView.self).first)
            let points: [(Double, Double)] = [(1, 1), (50, 10), (99, 19)]
            host.settle { stack.pixels(at: points) == [Self.blue, Self.blue, Self.blue] }
            XCTAssertEqual(stack.pixels(at: points), [Self.blue, Self.blue, Self.blue])
        }
    }

    func testACapsuleForegroundDrawsItsLowOpacityFill() throws {
        let colours = try drawn(width: 100, height: 20, at: [(50, 10), (1, 1)]) {
            Capsule(style: .continuous).foregroundStyle(.black.opacity(0.03)).frame(width: 100, height: 20)
        }
        XCTAssertEqual(Double(colours[0] >> 24), 8, accuracy: 1)
        XCTAssertEqual(colours[0] & 0x00FF_FFFF, 0)
        XCTAssertEqual(colours[1], 0, "outside the capsule stays transparent")
    }

    func testACapsuleInheritsACompleteGradientThroughAModifiedContainer() throws {
        let colours = try drawn(width: 100, height: 20, at: [(1, 10), (99, 10)]) {
            ZStack {
                Capsule(style: .continuous).frame(width: 100, height: 20)
            }
            .frame(width: 100, height: 20)
            .foregroundStyle(LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing))
        }
        XCTAssertGreaterThan(colours[0] >> 16 & 0xFF, 0xE0)
        XCTAssertGreaterThan(colours[1] & 0xFF, 0xE0)
    }

    func testChangingCapsuleForegroundRepaintsTheSameNativeShape() throws {
        try onUIThread {
            let alpha = State(wrappedValue: 0.03)
            let host = GTKRenderer.running(reducesMotion: true) {
                Capsule(style: .continuous).frame(width: 100, height: 20)
                    .foregroundStyle(.black.opacity(alpha.wrappedValue))
            }
            let shape = try XCTUnwrap(host.views(GTKShapeView.self).first)
            host.settle { shape.pixels(at: [(50, 10)])[0] >> 24 == 8 }
            alpha.wrappedValue = 0.2
            host.settle { shape.pixels(at: [(50, 10)])[0] >> 24 == 51 }
            XCTAssertTrue(host.views(GTKShapeView.self).first === shape)
            XCTAssertEqual(shape.pixels(at: [(50, 10), (1, 1)]), [0x3300_0000, 0])
        }
    }

    /// A rectangle fills its room, its corners rounded away.
    func testARectangleFillsItsRoomItsCornersRounded() throws {
        let colours = try drawn(width: 100, height: 60, at: [(50, 30), (50, 1), (1, 1)]) {
            Rectangle().fill(Color("#FF0000")).cornerRadius(20).frame(width: 100).frame(height: 60)
        }
        XCTAssertEqual(colours, [Self.red, Self.red, 0])
    }

    /// A corner wider than half the room's shorter side is held to that side's half (`BoxArithmetic.fitted`), as a
    /// circular radius is - the room's ends becoming the capsule's semicircles.
    func testACornerIsHeldToHalfOfTheShorterSide() throws {
        let colours = try drawn(width: 100, height: 20, at: [(2, 2), (12, 2)]) {
            Rectangle().fill(Color("#FF0000")).cornerRadius(50).frame(width: 100).frame(height: 20)
        }
        XCTAssertEqual(colours, [0, Self.red], "outside then inside the circular corner")
    }

    /// An ellipse fills its room, and nothing beyond its curve.
    func testAnEllipseFillsItsRoom() throws {
        let colours = try drawn(width: 100, height: 60, at: [(50, 30), (5, 30), (3, 3)]) {
            Ellipse().fill(Color("#FF0000")).frame(width: 100).frame(height: 60)
        }
        XCTAssertEqual(colours, [Self.red, Self.red, 0])
    }

    /// A path of its own is placed by its aspect: fitted, a triangle keeps its shape; stretched, it covers a wide
    /// room.
    func testAPathIsPlacedByItsAspect() throws {
        let fitted = try drawn(width: 40, height: 40, at: [(35, 5), (5, 35)]) {
            Path("M 0 0 L 10 0 L 10 10 Z").fill(Color("#FF0000")).aspect(.fit).frame(width: 40).frame(height: 40)
        }
        XCTAssertEqual(fitted, [Self.red, 0])

        let stretched = try drawn(width: 80, height: 40, at: [(75, 5), (70, 20), (5, 35)]) {
            Path("M 0 0 L 10 0 L 10 10 Z").fill(Color("#FF0000")).aspect(.stretch).frame(width: 80).frame(height: 40)
        }
        XCTAssertEqual(stretched, [Self.red, Self.red, 0])
    }

    /// A polygon is filled inside its points, and a line outlined from end to end, in the middle of its room.
    func testAPolygonAndALineAreDrawnFromTheirPoints() throws {
        let polygon = try drawn(width: 20, height: 20, at: [(10, 10)]) {
            Polygon([Point(0, 0), Point(10, 0), Point(10, 10), Point(0, 10)]).fill(Color("#0000FF")).frame(width: 20).frame(height: 20)
        }
        XCTAssertEqual(polygon, [Self.blue])

        let line = try drawn(width: 40, height: 10, at: [(20, 5), (20, 0.5)]) {
            Line().x1(0).y1(0).x2(40).y2(0).stroke(Color("#FF0000")).strokeWidth(4).frame(width: 40).frame(height: 10)
        }
        XCTAssertEqual(line, [Self.red, 0])
    }

    /// A gradient runs across the shape it fills.
    func testAGradientRunsAcrossTheShape() throws {
        let colours = try drawn(width: 100, height: 20, at: [(1, 10), (99, 10)]) {
            Rectangle().fill(.linearGradient(
                [GradientStop(Color("#FF0000"), 0), GradientStop(Color("#0000FF"), 1)],
                startPoint: Point(0, 0), endPoint: Point(1, 0))).frame(width: 100).frame(height: 20)
        }
        XCTAssertGreaterThan(colours[0] >> 16 & 0xFF, 0xE0, "red at the start")
        XCTAssertGreaterThan(colours[1] & 0xFF, 0xE0, "blue at the end")
    }

    /// A geometry that fills its room at its own size - placed where it stands, its placement the identity - is
    /// drawn.
    func testAGeometryAtItsOwnSizeIsDrawn() throws {
        let colours = try drawn(width: 56, height: 56, at: [(28, 40), (5, 5)]) {
            Path("M 28,0 L 56,56 L 0,56 Z").fill(Color("#FF0000")).frame(width: 56).frame(height: 56)
        }
        XCTAssertEqual(colours, [Self.red, 0])
    }

    /// Dashes and gaps are outline widths, and an offset of half the pattern puts dashes where the gaps were.
    func testDashesAreOutlineWidths() throws {
        let plain = try drawn(width: 200, height: 8, at: [(6, 4), (16, 4), (26, 4)]) {
            Line().x1(0).y1(4).x2(200).y2(4).stroke(Color("#FF0000")).strokeWidth(4)
                .strokeDashPattern([3, 2]).frame(width: 200).frame(height: 8)
        }
        XCTAssertEqual(plain, [Self.red, 0, Self.red], "a dash of 12, a gap of 8")

        let shifted = try drawn(width: 200, height: 8, at: [(6, 4), (16, 4)]) {
            Line().x1(0).y1(4).x2(200).y2(4).stroke(Color("#FF0000")).strokeWidth(4)
                .strokeDashPattern([3, 2]).strokeDashOffset(2.5).frame(width: 200).frame(height: 8)
        }
        XCTAssertEqual(shifted, [0, Self.red], "half a pattern on")
    }

    /// The colours at `points` of `shape`, sized `width` by `height`, read from the layout holding it.
    private func drawn(
        width: Double, height: Double, at points: [(Double, Double)], _ shape: @escaping @Sendable () -> any View
    ) throws -> [UInt32] {
        try onUIThread {
            let host = GTKRenderer.running {
                VStack { shape() }
                    .horizontalAlignment(.start)
                    .verticalAlignment(.start)
            }
            let stack = try XCTUnwrap(host.views(GTKStackView.self).first)
            XCTAssertEqual(host.views(GTKShapeView.self).count, 1, "one shape, a panel of its own")
            host.settle { stack.pixels(at: [(width / 2, height / 2)]) != [0] }
            return stack.pixels(at: points)
        }
    }
}
