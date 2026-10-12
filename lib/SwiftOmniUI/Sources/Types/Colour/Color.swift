// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The platform's C maths library, for the colour-space conversion's `pow`.
#if canImport(Android)
import Android
#elseif canImport(Glibc)
import Glibc
#elseif canImport(CRT)
import CRT
#endif

// A colour, held as four 8-bit sRGB channels, and as a pair where the two
// themes want different colours.
// Design: docs/design/types/colour-and-color-scheme.md#four-channels

/// A colour.
///
///     Color("#512BD4")
///     Color.cornflowerBlue
///     Color(light: .white, dark: .black)
///
/// Written as hex or by name, and as a pair where the two themes want
/// different colours - `Color(light:dark:)` is one value that goes wherever a
/// colour goes. Held as four 8-bit channels, so two spellings of one colour
/// are equal.
public struct Color: Hashable, Sendable, HostRepresentable {
    /// The four sRGB channels of one colour, 0-255 each.
    struct Rgba: Hashable, Sendable {
        let red: UInt8
        let green: UInt8
        let blue: UInt8
        let alpha: UInt8
    }

    /// The colour in force unless the color scheme is dark and there is a dark half.
    let light: Rgba

    /// The dark color scheme's half of a pair; the differ picks the half in force.
    /// Design: docs/design/types/colour-and-color-scheme.md#a-pair-for-each-color-scheme
    let dark: Rgba?

    /// A colour from hex: "#RGB", "#ARGB", "#RRGGBB" or "#AARRGGBB", with or
    /// without the leading `#` - the alpha, when it is written, first.
    ///
    /// Anything that is not hex stops the program with a message naming the
    /// text, the first time the code runs. A colour's name is `Color.red` and
    /// its kin.
    public init(_ hex: String) {
        guard let parsed = Color.channels(of: hex) else {
            preconditionFailure(
                "'\(hex)' is not a colour: write hex - #RGB, #ARGB, #RRGGBB or "
                    + "#AARRGGBB - or one of Color's named colours")
        }

        self.light = parsed
        self.dark = nil
    }

    /// The same color named twice, once for each color scheme.
    ///
    ///     static let surface = Color(light: .white, dark: AppColors.offBlack)
    ///
    /// It goes anywhere a colour goes - a `Style`, a control, a page's session,
    /// a state - and follows the system color scheme wherever it is written.
    ///
    /// Design: docs/design/types/colour-and-color-scheme.md#a-pair-for-each-color-scheme
    public init(light: Color, dark: Color) {
        self.light = light.light
        self.dark = dark.light
    }

    /// The channels themselves, and the ones for dark mode when there are any.
    init(_ light: Rgba, dark: Rgba? = nil) {
        self.light = light
        self.dark = dark
    }

    /// A colour from its channels: red, green and blue, each 0-255, and an
    /// alpha from 0, invisible, to 255, opaque - the default.
    ///
    ///     Color(red: 81, green: 43, blue: 212)
    ///     Color(red: 81, green: 43, blue: 212, alpha: 128)
    ///
    /// Whole numbers, as a channel holds them, so a fraction is refused where
    /// it is written. A value outside 0-255 is held to the range rather than
    /// refused.
    public init(red: Int, green: Int, blue: Int, alpha: Int = 255) {
        self.init(Rgba(
            red: Color.channel(red),
            green: Color.channel(green),
            blue: Color.channel(blue),
            alpha: Color.channel(alpha)))
    }

    /// A colour from its channels as fractions of full, SwiftUI's spelling:
    /// red, green and blue each from 0 to 1, and an alpha from 0, invisible,
    /// to 1, opaque - the default.
    ///
    ///     Color(red: 0.61, green: 0.74, blue: 0.65)
    ///
    /// A value outside 0-1 is held to the range, rounded to the channel it
    /// lands nearest.
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.init(Rgba(
            red: Color.channel(red),
            green: Color.channel(green),
            blue: Color.channel(blue),
            alpha: Color.channel(alpha)))
    }

    /// A grey, the SwiftUI spelling - `Color(white: 0.5)` is a medium grey.
    public init(white: Double, opacity: Double = 1) {
        self.init(red: white, green: white, blue: white, alpha: opacity)
    }

    /// A colour from channels in `colorSpace`, SwiftUI's spelling: red, green and blue each from 0 to 1, and an
    /// alpha from 0, invisible, to 1 - the components read in the space named, the colour held in sRGB.
    ///
    ///     Color(.displayP3, red: 0.2314, green: 0.5251, blue: 0.9678)
    public init(_ colorSpace: RGBColorSpace = .sRGB, red: Double, green: Double, blue: Double, opacity: Double = 1) {
        let (r, g, b) = colorSpace.channels(red, green, blue)
        self.init(red: r, green: g, blue: b, alpha: opacity)
    }

    /// A grey in `colorSpace`, SwiftUI's spelling.
    public init(_ colorSpace: RGBColorSpace = .sRGB, white: Double, opacity: Double = 1) {
        self.init(colorSpace, red: white, green: white, blue: white, opacity: opacity)
    }

    /// Four bytes under the colour kind, or both halves as a themed pair.
    public var propValue: PropValue {
        guard let dark else { return Color.tagged(light) }

        return .themed(light: Color.tagged(light), dark: Color.tagged(dark))
    }

    /// A colour back: four channels, or a pair of them - nil for anything
    /// else.
    /// - Parameter propValue: what the host sent.
    public init?(propValue: PropValue) {
        switch propValue {
        case .color(let red, let green, let blue, let alpha):
            self.init(Rgba(red: red, green: green, blue: blue, alpha: alpha))

        case .themed(light: .color(let red, let green, let blue, let alpha),
                     dark: .color(let darkRed, let darkGreen, let darkBlue, let darkAlpha)):
            self.init(
                Rgba(red: red, green: green, blue: blue, alpha: alpha),
                dark: Rgba(red: darkRed, green: darkGreen, blue: darkBlue, alpha: darkAlpha))

        default:
            return nil
        }
    }

    /// Four channels under the colour tag.
    private static func tagged(_ channels: Rgba) -> PropValue {
        .color(red: channels.red, green: channels.green, blue: channels.blue, alpha: channels.alpha)
    }

    // MARK: - Reading hex

    /// The channels a hex string names, or nil. Three and four digits are the
    /// shorthand, each digit standing for both of its pair; alpha comes first
    /// in four and eight digits.
    static func channels(of text: String) -> Rgba? {
        var digits: [UInt8] = []
        digits.reserveCapacity(8)

        for scalar in text.unicodeScalars.dropFirst(text.hasPrefix("#") ? 1 : 0) {
            guard let digit = digit(scalar), digits.count < 8 else { return nil }
            digits.append(digit)
        }

        switch digits.count {
        case 3:
            return Rgba(
                red: digits[0] * 17, green: digits[1] * 17, blue: digits[2] * 17, alpha: 255)
        case 4:
            return Rgba(
                red: digits[1] * 17, green: digits[2] * 17, blue: digits[3] * 17,
                alpha: digits[0] * 17)
        case 6:
            return Rgba(
                red: byte(digits[0], digits[1]),
                green: byte(digits[2], digits[3]),
                blue: byte(digits[4], digits[5]),
                alpha: 255)
        case 8:
            return Rgba(
                red: byte(digits[2], digits[3]),
                green: byte(digits[4], digits[5]),
                blue: byte(digits[6], digits[7]),
                alpha: byte(digits[0], digits[1]))
        default:
            return nil
        }
    }

    /// One hex digit's value, or nil for anything that is not one.
    private static func digit(_ scalar: Unicode.Scalar) -> UInt8? {
        switch scalar.value {
        case 48...57:
            return UInt8(scalar.value - 48)  // 0-9
        case 97...102:
            return UInt8(scalar.value - 87)  // a-f
        case 65...70:
            return UInt8(scalar.value - 55)  // A-F
        default:
            return nil
        }
    }

    private static func byte(_ high: UInt8, _ low: UInt8) -> UInt8 {
        high << 4 | low
    }

    /// An Int as a channel, held to the range a channel has.
    private static func channel(_ value: Int) -> UInt8 {
        UInt8(value < 0 ? 0 : (value > 255 ? 255 : value))
    }

    /// A fraction of full as a channel, held to the range and rounded.
    private static func channel(_ value: Double) -> UInt8 {
        guard value.isFinite else { return 0 }
        return UInt8((min(1, max(0, value)) * 255).rounded())
    }

}

extension Color {
    /// The space a colour's channels are read in where they are written - SwiftUI's `Color.RGBColorSpace`.
    /// A colour is held in sRGB however it is spelled: channels in another space are converted as the colour
    /// is made, so P3's colours are the sRGB colours they stand for.
    public enum RGBColorSpace: Sendable, Hashable {
        /// sRGB, gamma-encoded - what every channel already means.
        case sRGB

        /// sRGB's primaries at linear light: the channels come back gamma-encoded.
        case sRGBLinear

        /// Display P3: its channels are carried through the P3-to-sRGB matrix, so a colour beyond sRGB's
        /// gamut is the nearest sRGB one.
        case displayP3

        /// sRGB `red`, `green`, `blue` as this space's components - `channels`' reverse.
        func components(_ red: Double, _ green: Double, _ blue: Double) -> (Double, Double, Double) {
            switch self {
            case .sRGB:
                return (red, green, blue)
            case .sRGBLinear:
                return (Self.decoded(red), Self.decoded(green), Self.decoded(blue))
            case .displayP3:
                let (r, g, b) = (Self.decoded(red), Self.decoded(green), Self.decoded(blue))
                return (
                    Self.encoded(0.8224621 * r + 0.1775380 * g),
                    Self.encoded(0.0331941 * r + 0.9668058 * g),
                    Self.encoded(0.0170827 * r + 0.0723974 * g + 0.9105199 * b))
            }
        }

        /// `red`, `green`, `blue` in this space, as sRGB channels.
        func channels(_ red: Double, _ green: Double, _ blue: Double) -> (Double, Double, Double) {
            switch self {
            case .sRGB:
                return (red, green, blue)
            case .sRGBLinear:
                return (Self.encoded(red), Self.encoded(green), Self.encoded(blue))
            case .displayP3:
                let (r, g, b) = (Self.decoded(red), Self.decoded(green), Self.decoded(blue))
                return (
                    Self.encoded(1.2249402 * r - 0.2249404 * g),
                    Self.encoded(-0.0420569 * r + 1.0420571 * g),
                    Self.encoded(-0.0196376 * r - 0.0786361 * g + 1.0982735 * b))
            }
        }

        /// A gamma-encoded channel at linear light, sRGB's transfer curve (Display P3's is the same curve).
        private static func decoded(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }

        /// A linear-light channel gamma-encoded, sRGB's transfer curve.
        private static func encoded(_ channel: Double) -> Double {
            channel <= 0.0031308 ? channel * 12.92 : 1.055 * pow(channel, 1 / 2.4) - 0.055
        }
    }
}

// MARK: - Named colors
// The common ones, with their CSS names and values.

extension Color {
    /// Nothing at all, #00FFFFFF.
    public static let transparent = Color("#00FFFFFF")

    /// SwiftUI's spelling for `transparent`.
    public static let clear = Color.transparent

    /// Black, #000000.
    public static let black = Color("#000000")

    /// White, #FFFFFF.
    public static let white = Color("#FFFFFF")

    /// Gray, #808080.
    public static let gray = Color("#808080")

    /// Light gray, #D3D3D3.
    public static let lightGray = Color("#D3D3D3")

    /// Dark gray, #A9A9A9 - lighter than `.gray` despite the CSS name.
    public static let darkGray = Color("#A9A9A9")

    /// Dim gray, #696969.
    public static let dimGray = Color("#696969")

    /// Silver, #C0C0C0.
    public static let silver = Color("#C0C0C0")

    /// White smoke, #F5F5F5.
    public static let whiteSmoke = Color("#F5F5F5")

    /// Red, #FF0000.
    public static let red = Color("#FF0000")

    /// Firebrick, #B22222.
    public static let firebrick = Color("#B22222")

    /// Tomato, #FF6347.
    public static let tomato = Color("#FF6347")

    /// Orange, #FFA500.
    public static let orange = Color("#FFA500")

    /// Gold, #FFD700.
    public static let gold = Color("#FFD700")

    /// Yellow, #FFFF00.
    public static let yellow = Color("#FFFF00")

    /// Green, the dark one: #008000 - `.lime` is #00FF00.
    public static let green = Color("#008000")

    /// Lime, #00FF00.
    public static let lime = Color("#00FF00")

    /// Forest green, #228B22.
    public static let forestGreen = Color("#228B22")

    /// Teal, #008080.
    public static let teal = Color("#008080")

    /// Cyan, #00FFFF.
    public static let cyan = Color("#00FFFF")

    /// Blue, #0000FF.
    public static let blue = Color("#0000FF")

    /// Navy, #000080.
    public static let navy = Color("#000080")

    /// Dodger blue, #1E90FF.
    public static let dodgerBlue = Color("#1E90FF")

    /// Cornflower blue, #6495ED.
    public static let cornflowerBlue = Color("#6495ED")

    /// Steel blue, #4682B4.
    public static let steelBlue = Color("#4682B4")

    /// Light blue, #ADD8E6.
    public static let lightBlue = Color("#ADD8E6")

    /// Purple, #800080.
    public static let purple = Color("#800080")

    /// Indigo, #4B0082.
    public static let indigo = Color("#4B0082")

    /// Violet, #EE82EE.
    public static let violet = Color("#EE82EE")

    /// Magenta, #FF00FF.
    public static let magenta = Color("#FF00FF")

    /// Pink, #FFC0CB.
    public static let pink = Color("#FFC0CB")

    /// Brown, #A52A2A.
    public static let brown = Color("#A52A2A")

    /// Maroon, #800000.
    public static let maroon = Color("#800000")

    /// Olive, #808000.
    public static let olive = Color("#808000")

    /// Mint, #00C7BE.
    public static let mint = Color("#00C7BE")
}

extension Color {
    /// The same colour at `opacity`: 0 is invisible, 1 keeps it whole, and a
    /// value between scales the alpha. Outside that range the ends are taken.
    ///
    ///     .secondary.opacity(0.5)
    public func opacity(_ opacity: Double) -> Color {
        let opacity = min(1, max(0, opacity))
        func scaled(_ rgba: Rgba) -> Rgba {
            Rgba(
                red: rgba.red, green: rgba.green, blue: rgba.blue,
                alpha: UInt8((Double(rgba.alpha) * opacity).rounded()))
        }
        return Color(scaled(light), dark: dark.map(scaled))
    }

    /// This colour mixed toward `rhs` by `fraction`, SwiftUI's spelling: 0 keeps this colour whole, 1 gives
    /// `rhs` - the colour components interpolated in `colorSpace`, the alpha with them. A light/dark pair
    /// mixes scheme for scheme; a side without a dark half mixes its light there.
    ///
    ///     accent.mix(with: .back, by: 0.7)
    public func mix(with rhs: Color, by fraction: Double, in colorSpace: RGBColorSpace = .sRGB) -> Color {
        let t = min(1, max(0, fraction))
        func mixed(_ a: Rgba, _ b: Rgba) -> Rgba {
            var (r, g, bl) = colorSpace.components(
                Double(a.red) / 255, Double(a.green) / 255, Double(a.blue) / 255)
            let (r2, g2, b2) = colorSpace.components(
                Double(b.red) / 255, Double(b.green) / 255, Double(b.blue) / 255)
            (r, g, bl) = (r + (r2 - r) * t, g + (g2 - g) * t, bl + (b2 - bl) * t)
            (r, g, bl) = colorSpace.channels(r, g, bl)
            return Rgba(
                red: Color.channel(r), green: Color.channel(g), blue: Color.channel(bl),
                alpha: Color.channel(Int((Double(a.alpha) + (Double(b.alpha) - Double(a.alpha)) * t).rounded())))
        }
        return Color(
            mixed(light, rhs.light),
            dark: dark == nil && rhs.dark == nil ? nil : mixed(dark ?? light, rhs.dark ?? rhs.light))
    }
}

extension Color {
    /// The system's text and picture colours, each a pair answering for the
    /// two color schemes - the platforms' named colours as their documented
    /// channels.

    /// The colour a principal label or picture draws in - `NSColor.labelColor`, black or white at 85%.
    public static let primary = Color(
        light: Color(red: 0, green: 0, blue: 0, alpha: 0.847),
        dark: Color(red: 1, green: 1, blue: 1, alpha: 0.847))

    /// The colour a label of second importance draws in - `NSColor.secondaryLabelColor`.
    public static let secondary = Color(
        light: Color(red: 0, green: 0, blue: 0, alpha: 0.498),
        dark: Color(red: 1, green: 1, blue: 1, alpha: 0.549))

    /// The colour a label of third importance draws in - `NSColor.tertiaryLabelColor`.
    public static let tertiary = Color(
        light: Color(red: 0, green: 0, blue: 0, alpha: 0.259),
        dark: Color(red: 1, green: 1, blue: 1, alpha: 0.247))

    /// The colour a label of least importance draws in - `NSColor.quaternaryLabelColor`.
    public static let quaternary = Color(
        light: Color(red: 0, green: 0, blue: 0, alpha: 0.098),
        dark: Color(red: 1, green: 1, blue: 1, alpha: 0.098))

    /// The colour the system marks its own accents with - the blue a control
    /// takes where nothing was chosen, `NSColor.controlAccentColor`.
    public static let accentColor = Color("#007AFF")

    /// The system's plain background colour, where one is needed as a colour.
    public static let background = Color(light: .white, dark: .black)
}
