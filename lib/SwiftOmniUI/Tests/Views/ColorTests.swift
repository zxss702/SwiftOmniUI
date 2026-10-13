// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// A colour, read from hex and written as four bytes.
//
// The parser is SwiftOmniUI's, so what a colour may be is defined here rather
// than in the host: hex, in four lengths, checked below. A host that read
// colours for itself would have to reproduce that exactly or differ in
// silence.

import XCTest
@_spi(Host) @testable import SwiftOmniUICore

@MainActor final class ColorTests: XCTestCase {
    // MARK: - Reading hex

    /// The four lengths hex is read in, and the shorthand doubling each digit.
    func testEveryLengthOfHexReadsTheSameColour() {
        XCTAssertEqual(Color("#F00"), Color("#FF0000"))
        XCTAssertEqual(Color("#8F00"), Color("#88FF0000"))
        XCTAssertEqual(Color("#FF0000"), Color("#FFFF0000"), "six digits are opaque")

        XCTAssertEqual(Color("#80FF0000").propValue,
                       .color(red: 255, green: 0, blue: 0, alpha: 128))
    }

    /// Alpha comes FIRST in the four- and eight-digit forms, which is what
    /// ARGB means - and it is the channel a wrong reading gets away with
    /// longest, since most colours are opaque.
    func testAlphaIsTheFirstChannelWrittenAndTheLastOneSent() {
        XCTAssertEqual(Color("#40204060").propValue,
                       .color(red: 0x20, green: 0x40, blue: 0x60, alpha: 0x40))
    }

    /// Case does not matter, and the `#` may be left off.
    func testHexIsReadInEitherCaseWithOrWithoutTheHash() {
        XCTAssertEqual(Color("#ff0000"), Color("#FF0000"))
        XCTAssertEqual(Color("FF0000"), Color("#FF0000"))
    }

    /// What is NOT hex answers nothing, which is what the initializer traps
    /// on - asked through the reader, since a trap cannot be caught.
    func testAnythingThatIsNotHexIsNotAColour() {
        XCTAssertNil(Color.channels(of: "Red"), "a colour NAME is Color.red, not a string")
        XCTAssertNil(Color.channels(of: "#12345"))
        XCTAssertNil(Color.channels(of: "#GGGGGG"))
        XCTAssertNil(Color.channels(of: ""))
        XCTAssertNil(Color.channels(of: "#123456789"))
        XCTAssertNil(Color.channels(of: "rgb(255,0,0)"))
    }

    /// Equality is the COLOUR, not its spelling - which is what stops two ways
    /// of writing one from reading as a change and being sent again.
    func testTwoSpellingsOfOneColourAreOneValue() {
        let (r, g, b) = (255, 0, 0)
        XCTAssertEqual(Color("#ff0000"), Color("#FF0000"))
        XCTAssertEqual(Color(red: r, green: g, blue: b), Color("#FF0000"))
        XCTAssertEqual(Color(red: r, green: g, blue: b, alpha: 255), Color("#FF0000"))
        XCTAssertNotEqual(Color(red: r, green: g, blue: b, alpha: 128), Color("#FF0000"))
        XCTAssertNotEqual(Color("#FF0000"), Color.red, "the UI palette is not a constant CSS primary")
    }

    /// A channel outside 0-255 is held to it rather than wrapping - which is
    /// what an Int argument makes possible in the first place.
    func testAChannelOutsideItsRangeIsHeldToIt() {
        let (r, g, b) = (-20, 300, 0)
        XCTAssertEqual(Color(red: r, green: g, blue: b), Color("#00FF00"))
    }

    /// A fractional channel is the one SwiftUI writes: 0-1, held to it, and a
    /// value that is no number reads as no channel.
    func testAFractionalChannelScalesToAByte() {
        XCTAssertEqual(Color(red: 1, green: 0.5, blue: 0),
                       Color("#FF8000"))
        XCTAssertEqual(Color(red: 0.61, green: 0.74, blue: 0.65),
                       Color("#9CBDA6"))
        XCTAssertEqual(Color(red: 2.0, green: -1, blue: 0), Color("#FF0000"))
        XCTAssertEqual(Color(red: .nan, green: 0, blue: 0), Color.black)
        XCTAssertEqual(Color(red: 1, green: 1, blue: 1, alpha: 0.5),
                       Color("#80FFFFFF"))
    }

    /// Untyped literals follow SwiftUI's component initializer, rather than the older byte overload.
    func testIntegerRGBLiteralsAreFullIntensityComponents() {
        XCTAssertEqual(Color(red: 1, green: 0, blue: 0), Color("#FF0000"))
        XCTAssertEqual(Color(red: 0, green: 1, blue: 1), Color("#00FFFF"))
        XCTAssertEqual(Color(red: 1, green: 1, blue: 1), Color.white)
        XCTAssertEqual(Color(red: 0, green: 1, blue: 1, opacity: 0.5), Color("#8000FFFF"))
        XCTAssertEqual(Color(red: 0.0, green: 1.0, blue: 1.0), Color(red: 0, green: 1, blue: 1))
    }

    func testExplicitColorSpacesEncodeOnceBeforeReachingTheHost() {
        XCTAssertEqual(Color(.sRGB, red: 0.25, green: 0.5, blue: 0.75, opacity: 0.4), Color("#664080BF"))
        XCTAssertEqual(Color(.sRGBLinear, white: 0.5), Color("#BCBCBC"))
        XCTAssertEqual(Color(white: 0.5), Color("#808080"))
        XCTAssertEqual(Color(.displayP3, red: 1, green: 1, blue: 1), Color.white)
        XCTAssertEqual(Color(.displayP3, red: 1, green: 0, blue: 0), Color("#FF0000"),
                       "the existing 8-bit boundary clips out-of-gamut components to sRGB")
    }

    // MARK: - What crosses

    /// A themed colour crosses as ONE colour: written, it is the pair, and
    /// the half in force is picked as the element wearing it is built - so
    /// a host never sees two. See Color.swift.
    func testAThemedColourCrossesAsTheHalfInForce() {
        let themed = Color(light: .white, dark: .black)

        XCTAssertEqual(
            themed.propValue,
            .themed(light: Color.white.propValue, dark: Color.black.propValue))
        XCTAssertEqual(themed.propValue.resolvingColorScheme(), Color.white.propValue)

        withTheme(.dark) {
            XCTAssertEqual(themed.propValue.resolvingColorScheme(), Color.black.propValue)
        }
    }

    // MARK: - A colour inside a drawing

    /// A drawing is a list of RECORDS - one number for the canvas member, its
    /// arguments after it as the things they are - so a colour in one crosses
    /// as the four bytes every other colour crosses as, and the color scheme picks
    /// its half as the element holding the drawing is built.
    func testADrawingWritesEachColourAsItsFourChannels() {
        func drawn() -> PropValue? {
            Canvas { Draw.fillColor(Color(light: Color("#6495ED"), dark: .black)) }
                .node.props[.drawable]?.resolvingColorScheme()
        }

        // One record: the fillColor command's number, then the colour itself.
        XCTAssertEqual(
            drawn(),
            .values([.values([
                .enumeration(0),
                .color(red: 0x64, green: 0x95, blue: 0xED, alpha: 0xFF),
            ])]))

        withTheme(.dark) {
            XCTAssertEqual(
                drawn(),
                .values([.values([
                    .enumeration(0),
                    .color(red: 0, green: 0, blue: 0, alpha: 0xFF),
                ])]))
        }
    }
}
