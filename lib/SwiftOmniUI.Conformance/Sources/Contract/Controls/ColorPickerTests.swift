// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// `ColorPickerContract` on a host: a box fills its room with its colour, the colour the tree changes it to, and leaves
/// its rounded corners empty.
@_spi(Host) public enum ColorPickerTests: ConformanceFamily {
    public static let name = "ColorPicker"

    public static var cases: [ConformanceCase] {
        [
            Aspects.standsAlone("ColorPicker"),
            ConformanceCase("aBoxFillsItsRoomWithItsColour", proves: [
                Covered(ColorPickerContract.color),
            ], needs: [Covered(ButtonContract.clicked)]) { s in
                let blue = State(wrappedValue: false)
                s.start {
                    VStack {
                        ColorPicker(blue.wrappedValue ? .blue : .red).frame(width: 40).frame(height: 40).id("box")
                        Button("Blue").onClicked { blue.wrappedValue = true }.id("change")
                    }
                    .horizontalAlignment(.start)
                }
                let box = try s.element("box")
                try s.settle { try s.shows(.red, on: box, at: Point(20, 20)) }
                s.expect(try s.color(of: box, at: Point(1, 1)), .red, "to its corner")

                try s.perform(.activate, on: s.element("change"))
                try s.settle { try s.shows(.blue, on: box, at: Point(20, 20)) }
                s.expect(try s.color(of: box, at: Point(20, 20)), .blue, "the colour the tree changed it to")
            },
            ConformanceCase("aBoxsRoundedCornersAreLeftEmpty", proves: [
                Covered(ColorPickerContract.cornerRadius), Covered(ColorPickerContract.color),
            ], needs: [Covered(ButtonContract.clicked)]) { s in
                let square = State(wrappedValue: false)
                s.start {
                    VStack {
                        ColorPicker(.red).cornerRadius(square.wrappedValue ? 0 : 20)
                            .frame(width: 80).frame(height: 80).id("box")
                        Button("Square").onClicked { square.wrappedValue = true }.id("change")
                    }
                    .horizontalAlignment(.start)
                }
                let box = try s.element("box")
                try s.settle { try s.shows(.red, on: box, at: Point(40, 40)) }
                s.expect(try s.color(of: box, at: Point(1, 1)), nil, "the rounded corner empty")

                try s.perform(.activate, on: s.element("change"))
                try s.settle { try s.shows(.red, on: box, at: Point(1, 1)) }
                s.expect(try s.color(of: box, at: Point(1, 1)), .red, "square once the tree says so")
            },
        ]
    }
}
