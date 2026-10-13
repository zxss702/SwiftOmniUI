// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// `CanvasContract` on a host: its instructions drawn in order and drawn again when the tree changes them, and a
/// press heard where it went down, where it was dragged and where it was let go, in the canvas's own points.
@_spi(Host) public enum CanvasTests: ConformanceFamily {
    public static let name = "Canvas"

    public static var cases: [ConformanceCase] {
        [
            Aspects.standsAlone("Canvas"),
            ConformanceCase("itsInstructionsAreDrawnInOrder", proves: [
                Covered(CanvasContract.drawable),
            ]) { s in
                s.start {
                    VStack {
                        Canvas {
                            Draw.fillColor(.red)
                            Draw.fillRectangle(x: 0, y: 0, width: 80, height: 40)
                            Draw.fillColor(.blue)
                            Draw.fillRectangle(x: 50, y: 0, width: 20, height: 40)
                        }
                        .frame(width: 100).frame(height: 40).id("canvas")
                    }
                    .horizontalAlignment(.start)
                    .verticalAlignment(.start)
                }
                let canvas = try s.element("canvas")

                try s.settle { try s.shows(.red, on: canvas, at: Point(10, 20)) }
                s.expect(try s.color(of: canvas, at: Point(10, 20)), .red, "the first fill")
                s.expect(try s.color(of: canvas, at: Point(60, 20)), .blue, "the later fill over it")
                s.expect(try s.color(of: canvas, at: Point(95, 20)), nil, "nothing past both")
            },
            ConformanceCase("aWholeTurnFillsTheWholeOval", proves: [Covered(CanvasContract.drawable)]) { s in
                s.start {
                    VStack {
                        Canvas {
                            Draw.fillColor(.red)
                            Draw.fillArc(
                                x: 0, y: 0, width: 40, height: 40, startAngle: 0, endAngle: 360, clockwise: false)
                            Draw.fillArc(
                                x: 50, y: 0, width: 40, height: 40, startAngle: 90, endAngle: -270, clockwise: true)
                        }
                        .frame(width: 90).frame(height: 40).id("canvas")
                    }
                    .horizontalAlignment(.start)
                    .verticalAlignment(.start)
                }
                let canvas = try s.element("canvas")

                try s.settle { try s.shows(.red, on: canvas, at: Point(20, 20)) }
                for point in [Point(20, 20), Point(20, 4), Point(4, 20), Point(70, 20), Point(70, 36)] {
                    s.expect(try s.color(of: canvas, at: point), .red, "a whole turn, at \(point.x), \(point.y)")
                }
                s.expect(try s.color(of: canvas, at: Point(2, 2)), nil, "the oval's corner stands empty")
            },
            ConformanceCase("aDrawingTheTreeChangesIsDrawnAgain", proves: [
                Covered(CanvasContract.drawable),
            ], needs: [Covered(ButtonContract.clicked)]) { s in
                let blue = State(wrappedValue: false)
                s.start {
                    VStack {
                        Canvas {
                            Draw.fillColor(blue.wrappedValue ? .blue : .red)
                            Draw.fillRectangle(x: 0, y: 0, width: 40, height: 40)
                        }
                        .frame(width: 40).frame(height: 40).id("canvas")
                        Button("Blue").onClicked { blue.wrappedValue = true }.id("change")
                    }
                    .horizontalAlignment(.start)
                    .verticalAlignment(.start)
                }
                let canvas = try s.element("canvas")
                try s.settle { try s.shows(.red, on: canvas, at: Point(20, 20)) }

                try s.perform(.activate, on: s.element("change"))
                try s.settle { try s.shows(.blue, on: canvas, at: Point(20, 20)) }
                s.expect(try s.color(of: canvas, at: Point(20, 20)), .blue)
            },
            ConformanceCase("aTextIsMeasuredByTheHostsOwnEngine", proves: [
                Covered(CanvasContract.measureText),
            ], needs: [Covered(ButtonContract.clicked)]) { s in
                let canvas = Aim(Canvas.self)
                let measured = Received<Size>()
                s.start {
                    VStack {
                        Canvas { Draw.fillColor(.red); Draw.fillRectangle(x: 0, y: 0, width: 40, height: 40) }
                            .aim(canvas).frame(width: 40).frame(height: 40).id("canvas")
                        Button("Measure").onClicked {
                            let wide = try await canvas.measureText(
                                "alpha beta gamma delta", font: .system(size: 20))
                            let wrapped = try await canvas.measureText(
                                "alpha beta gamma delta", font: .system(size: 20),
                                maximumWidth: wide.width / 2)
                            measured.values.append(wide)
                            measured.values.append(wrapped)
                        }.id("measure")
                    }
                    .horizontalAlignment(.start)
                    .verticalAlignment(.start)
                }
                try s.perform(.activate, on: s.element("measure"))
                s.settle { measured.values.count == 2 }
                guard let wide = measured.values.first, let wrapped = measured.values.last else { return }

                s.expect(wide.width > 0 && wide.height > 0, true, "the words take room")
                s.expect(wrapped.height > wide.height, true, "half the room takes a second line")
                s.expect(wrapped.width <= wide.width / 2 + 2, true, "wrapped within the width asked")
            },
            ConformanceCase("aPressIsHeardWhereItWent", proves: [
                Covered(CanvasContract.pressed), Covered(CanvasContract.dragged), Covered(CanvasContract.released),
            ]) { s in
                let heard = Received<String>()
                s.start {
                    VStack {
                        Canvas { Draw.fillColor(.red); Draw.fillRectangle(x: 0, y: 0, width: 100, height: 40) }
                            .onPressed { heard.values.append("pressed \(Int($0.x)),\(Int($0.y))") }
                            .onDragged { heard.values.append("dragged \(Int($0.x)),\(Int($0.y))") }
                            .onReleased { heard.values.append("released \(Int($0.x)),\(Int($0.y))") }
                            .frame(width: 100).frame(height: 40).id("canvas")
                    }
                    .horizontalAlignment(.start)
                }
                let canvas = try s.element("canvas")

                try s.perform(.pressDown(at: Point(5, 6)), on: canvas)
                try s.perform(.drag(to: Point(7, 8)), on: canvas)
                try s.perform(.lift(at: Point(9, 10)), on: canvas)
                s.settle { heard.values.count == 3 }

                s.expect(heard.values, ["pressed 5,6", "dragged 7,8", "released 9,10"])
            },
        ]
    }
}
