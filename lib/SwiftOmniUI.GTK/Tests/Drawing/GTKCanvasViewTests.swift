// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIGTK
import XCTest

final class GTKCanvasViewTests: XCTestCase {
    private static let red: UInt32 = 0xFFFF_0000
    private static let blue: UInt32 = 0xFF00_00FF

    /// A width-only scroll proposal still allocates the Canvas's derived
    /// height through the native custom-layout placement boundary.
    func testAspectRatioAllocatesTheCanvasHeight() throws {
        try onUIThread {
            let host = GTKRenderer.running {
                Canvas { context, size in
                    context.fill(Path(Rect(0, 0, size.width, size.height)), with: .color(Color("#0000FF")))
                }.aspectRatio(2, contentMode: .fit).frame(width: 100)
            }
            let canvas = try XCTUnwrap(host.views(GTKCanvasView.self).first)
            XCTAssertEqual(canvas.drawingSize(), Size(100, 50))
            XCTAssertEqual(canvas.pixels(at: [(50, 25)]), [Self.blue])
        }
    }

    /// A canvas draws its records in order: a filled rectangle covers the room it names, and a stroked line under
    /// the pen set for it - its style, cap and join - draws where it runs.
    func testACanvasDrawsItsRecordsAsWritten() throws {
        let colours = try drawn(at: [(30, 30), (90, 30), (50, 55), (5, 5)]) {
            Canvas {
                Draw.fillColor(Color("#FF0000"))
                Draw.fillRectangle(x: 10, y: 10, width: 60, height: 40)
                Draw.strokeColor(Color("#0000FF"))
                Draw.strokeStyle(width: 4, cap: .round, join: .round)
                Draw.drawLine(x1: 0, y1: 55, x2: 100, y2: 55)
            }
            .frame(width: 100, height: 60)
        }
        XCTAssertEqual(colours, [Self.red, 0, Self.blue, 0])
    }

    /// Text clipping must finish before a later diagram shape is recorded.
    func testTextClipDoesNotConsumeFollowingDiagramShapes() throws {
        let colours = try drawn(at: [(80, 45)]) {
            Canvas {
                Draw.foregroundStyle(Color("#0000FF"))
                Draw.fontSize(14)
                Draw.drawText("label", x: 0, y: 0, width: 30, height: 20)
                Draw.fillColor(Color("#FF0000"))
                Draw.fillRectangle(x: 70, y: 35, width: 20, height: 20)
            }.frame(width: 100, height: 60)
        }
        XCTAssertEqual(colours, [Self.red])
    }

    /// A canvas' transform turns what follows it: moved and spun, a box draws its own diamond, and a saved state
    /// would have put back what it held.
    func testATransformTurnsWhatFollowsIt() throws {
        let colours = try drawn(at: [(30, 10), (60, 30), (70, 30)]) {
            Canvas {
                Draw.fillColor(Color("#FF0000"))
                Draw.fillRectangle(x: 20, y: 0, width: 20, height: 20)
                Draw.translate(dx: 50, dy: 30)
                Draw.rotate(45)
                Draw.fillColor(Color("#0000FF"))
                Draw.fillRectangle(x: -10, y: -10, width: 20, height: 20)
            }
            .frame(width: 100, height: 60)
        }
        XCTAssertEqual(colours, [Self.red, Self.blue, 0],
                       "the spun box's diamond reaches 14 from its centre and no farther")
    }

    /// A closure canvas draws with the room it was laid out in: the frame's report rebuilds it, and the drawing it
    /// writes then is the size the canvas settled at.
    func testAClosuredCanvasDrawsWithItsRoom() throws {
        try onUIThread {
            let host = GTKRenderer.running {
                VStack {
                    Canvas { context, size in
                        context.fill(
                            Path(roundedRect: Rect(0, 0, size.width, size.height), cornerRadius: 4),
                            with: .color(Color("#FF0000")))
                    }
                    .frame(width: 100, height: 60)
                }
                .horizontalAlignment(.start)
                .verticalAlignment(.start)
            }
            let canvas = try XCTUnwrap(host.views(GTKCanvasView.self).first)
            XCTAssertEqual(canvas.pixels(at: [(50, 30), (0.5, 0.5)]), [Self.red, 0],
                           "the first native layout paints the whole room with rounded corners")
        }
    }

    /// A path drawn by the closure fills what the path names and no more.
    func testAClosuredPathFillsWhatItNames() throws {
        try onUIThread {
            let host = GTKRenderer.running {
                VStack {
                    Canvas { context, _ in
                        context.fill(Path(ellipseIn: Rect(0, 0, 100, 60)), with: .color(Color("#0000FF")))
                    }
                    .frame(width: 100, height: 60)
                }
                .horizontalAlignment(.start)
                .verticalAlignment(.start)
            }
            let canvas = try XCTUnwrap(host.views(GTKCanvasView.self).first)
            host.settle { canvas.pixels(at: [(50, 30)]) != [0] }
            XCTAssertEqual(canvas.pixels(at: [(50, 30), (3, 3), (97, 57)]), [Self.blue, 0, 0])
        }
    }

    /// The colours at `points` of the canvas showing `view`, laid out.
    private func drawn(
        at points: [(Double, Double)], _ view: @escaping @Sendable () -> any View
    ) throws -> [UInt32] {
        try onUIThread {
            let host = GTKRenderer.running {
                VStack { view() }
                    .horizontalAlignment(.start)
                    .verticalAlignment(.start)
            }
            let canvas = try XCTUnwrap(host.views(GTKCanvasView.self).first)
            host.settle { canvas.pixels(at: [points.first ?? (0, 0)]) != [0] }
            return canvas.pixels(at: points)
        }
    }
}
