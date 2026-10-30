// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// A font for text - the same words as SwiftUI's `Font`, resolved by the host
/// into the platform's own.
///
///     Text("Chapter").font(.title)
///     Text("Code").font(.system(size: 13, design: .monospaced))
///     Text("Named").font(.custom("Source Han Serif SC VF", size: 15))
///
/// A named text style - `.title`, `.body` - leaves the size to the platform
/// and follows the user's text-size setting; `system(size:)` names the size
/// outright.
public struct Font: Sendable, Equatable {
    /// What the font is made of.
    enum Basis: Sendable, Equatable {
        /// One of the platform's named text styles.
        case textStyle(FontTextStyle)
        /// The system font at an explicit size.
        case system(size: Double)
        /// A family by name, at an explicit size.
        case custom(family: String, size: Double)
    }

    /// What the font is made of.
    let basis: Basis

    /// The weight the font is drawn at - nil leaves it to the basis.
    var weight: Weight?

    /// The letter shape - nil leaves it to the platform default.
    var design: FontDesign?

    /// Bold or italic, over what the weight already says.
    var attributes: FontAttributes = .none

    init(basis: Basis) {
        self.basis = basis
    }

    /// The platform's largest text style.
    public static let largeTitle = Font(basis: .textStyle(.largeTitle))

    /// A page's title.
    public static let title = Font(basis: .textStyle(.title))

    /// A section's title.
    public static let title2 = Font(basis: .textStyle(.title2))

    /// A subsection's title.
    public static let title3 = Font(basis: .textStyle(.title3))

    /// A heading above ordinary text.
    public static let headline = Font(basis: .textStyle(.headline))

    /// A heading lighter than `headline`.
    public static let subheadline = Font(basis: .textStyle(.subheadline))

    /// Ordinary reading text.
    public static let body = Font(basis: .textStyle(.body))

    /// What text is drawn in where none is named - ordinary reading text, as
    /// SwiftUI's `Font.default` is.
    public static let `default` = Font(basis: .textStyle(.body))

    /// Text a step under a heading.
    public static let callout = Font(basis: .textStyle(.callout))

    /// Footnotes.
    public static let footnote = Font(basis: .textStyle(.footnote))

    /// Captions and small labels.
    public static let caption = Font(basis: .textStyle(.caption))

    /// The smaller caption.
    public static let caption2 = Font(basis: .textStyle(.caption2))

    /// The system font at `size`, in `design`, drawn at `weight` where one is
    /// named.
    ///
    ///     .font(.system(size: 13, weight: .medium, design: .monospaced))
    public static func system(
        size: Double,
        weight: Weight? = nil,
        design: Design? = nil
    ) -> Font {
        var font = Font(basis: .system(size: size))
        font.weight = weight
        font.design = design
        return font
    }

    /// The system font for `style`, in `design`, drawn at `weight` where one
    /// is named - SwiftUI's `Font.system(.caption, design: .monospaced)`.
    public static func system(
        _ style: TextStyle,
        design: Design? = nil,
        weight: Weight? = nil
    ) -> Font {
        var font = Font(basis: .textStyle(style))
        font.weight = weight
        font.design = design
        return font
    }

    /// A named family at `size`, its size staying fixed against the user's
    /// text-size setting.
    public static func custom(_ name: String, fixedSize size: Double) -> Font {
        Font(basis: .custom(family: name, size: size))
    }

    /// A named family at `size`.
    public static func custom(_ name: String, size: Double) -> Font {
        Font(basis: .custom(family: name, size: size))
    }

    /// A named family sized `size`, scaling with `textStyle` where the
    /// platform's text-size setting changes.
    public static func custom(_ name: String, size: Double, relativeTo textStyle: Font.TextStyle) -> Font {
        Font(basis: .custom(family: name, size: size))
    }

    /// The same font, bolder - `.weight(.bold)` where no weight is set, added
    /// to the weight where one is.
    public func bold() -> Font {
        var font = self
        if let weight = font.weight {
            font.weight = Weight(min(900, weight.value + 300))
        } else {
            font.attributes.insert(.bold)
        }
        return font
    }

    /// The same font, italic.
    public func italic() -> Font {
        var font = self
        font.attributes.insert(.italic)
        return font
    }

    /// The same font, drawn at `weight`.
    public func weight(_ weight: Weight) -> Font {
        var font = self
        font.weight = weight
        return font
    }

    /// The same font, drawn in `design`.
    @_spi(Host) public func design(_ design: Design) -> Font {
        var font = self
        font.design = design
        return font
    }

    /// The same font, monospaced - `.design(.monospaced)` the SwiftUI way.
    public func monospaced() -> Font {
        design(.monospaced)
    }

    /// A font's heaviness, from `.ultraLight` to `.black`.
    public struct Weight: Sendable, Equatable {
        /// The weight on the 100-900 scale the platforms share.
        @_spi(Host) public let value: Double

        /// A weight by its scale value.
        public init(_ value: Double) {
            self.value = value
        }

        /// 100.
        public static let ultraLight = Weight(100)

        /// 200.
        public static let thin = Weight(200)

        /// 300.
        public static let light = Weight(300)

        /// The ordinary weight.
        public static let regular = Weight(400)

        /// 500.
        public static let medium = Weight(500)

        /// Between ordinary and bold.
        public static let semibold = Weight(600)

        /// Bold.
        public static let bold = Weight(700)

        /// 800.
        public static let heavy = Weight(800)

        /// 900.
        public static let black = Weight(900)
    }

    /// How the system's letters are shaped - `FontDesign`.
    public typealias Design = FontDesign

    /// A platform text style - `FontTextStyle`.
    public typealias TextStyle = FontTextStyle
}

extension Font.Weight: HostRepresentable {
    /// The scale value, as a member carries it.
    public var propValue: PropValue { .number(value) }

    /// The weight a member carried.
    public init?(propValue: PropValue) {
        guard let number = propValue.number else { return nil }
        self.init(number)
    }
}

extension Font.Weight: StateValue {
    /// One lane, which is the scale value itself.
    public var carried: StateCarried { .lanes([value]) }

    /// The weight the lane holds.
    public init?(carried: StateCarried) {
        guard case .lanes(let lanes) = carried, lanes.count == 1 else { return nil }
        self.init(lanes[0])
    }

    /// One.
    public static var lanes: Int { 1 }
}
