// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore

/// How words look where the tree says, in the contract's terms - each nil or empty for the host's own - which a
/// host turns into its toolkit's attributes.
/// Design: docs/design/host/tree.md#runs-of-words
@_spi(Host) public struct TextLook: Equatable, Sendable {
    /// The font's size in points.
    public var size: Double?

    /// The font's weight and slant.
    public var attributes = FontAttributes.none

    /// The font's family.
    public var family: String?

    /// One of the platform's named text styles, where the words take one.
    public var textStyle: FontTextStyle?

    /// The font's weight on the 100-900 scale.
    public var weight: Double?

    /// The letter shape of the system font.
    public var design: FontDesign?

    /// The words' colour, as the tree gives it.
    public var color: HostValue?

    /// What stands behind the words, as the tree gives it.
    public var background: HostValue?

    /// The space between the letters, in points.
    public var letterSpacing = 0.0

    /// A line's height as a multiple of the font's own.
    public var lineHeight: Double?
    /// Extra space between baselines beyond the font's natural line height.
    public var lineSpacing = 0.0

    /// The lines under or through the words.
    public var decorations = TextDecorations.none

    /// How far the words' baseline sits from the line's own, in points; nil
    /// leaves it on the line's.
    public var baselineOffset: Double?

    /// A look saying nothing: the host's own throughout.
    public init() {}

    /// The space between the letters as a share of a font `size` points tall - what a toolkit spacing letters in
    /// ems takes; nothing for a size that is none.
    public func letterSpacing(inEmsOf size: Double) -> Double {
        size > 0 && size.isFinite ? letterSpacing / size : 0
    }

    /// This look where it says something, `other` where it says nothing: a run of words over its label's look.
    public func over(_ other: TextLook) -> TextLook {
        var look = self
        look.size = size ?? other.size
        look.attributes = attributes.isEmpty ? other.attributes : attributes
        look.family = family ?? other.family
        look.textStyle = textStyle ?? other.textStyle
        look.weight = weight ?? other.weight
        look.design = design ?? other.design
        look.color = color ?? other.color
        look.background = background ?? other.background
        look.letterSpacing = letterSpacing != 0 ? letterSpacing : other.letterSpacing
        look.lineHeight = lineHeight ?? other.lineHeight
        look.lineSpacing = lineSpacing != 0 ? lineSpacing : other.lineSpacing
        look.decorations = decorations.isEmpty ? other.decorations : decorations
        look.baselineOffset = baselineOffset ?? other.baselineOffset
        return look
    }
}

/// One run of a label's words: the words in their case, and their own look -
/// or a picture drawn as one glyph where `image` says one is.
@_spi(Host) public struct TextRun: Equatable, Sendable {
    /// The words; the object-replacement mark `"\u{FFFC}"` where `image`
    /// stands, so a typesetter counts the picture's glyph.
    public let text: String

    /// Their look, which the label's look stands behind.
    public let look: TextLook

    /// The picture this run draws in place of words, where it is one.
    public let image: ImageSource?

    /// `text` looking as `look` says.
    public init(text: String, look: TextLook, image: ImageSource? = nil) {
        self.text = text
        self.look = look
        self.image = image
    }
}

extension MountedElement {
    /// The look this element's own values give its words: its font, its colour, what stands behind them, the space
    /// between its letters, its lines' height and its decorations - each nil or empty where it says nothing.
    public var textLook: TextLook {
        var look = TextLook()
        look.size = number(.fontSize)
        look.attributes = value(.fontAttributes)?.enumeration.map { FontAttributes(rawValue: $0) } ?? .none
        look.family = value(.fontFamily)?.name
        look.textStyle = value(.fontTextStyle)?.enumeration.flatMap(FontTextStyle.init(rawValue:))
        look.weight = value(.fontWeight)?.number
        look.design = value(.fontDesign)?.enumeration.flatMap(FontDesign.init(rawValue:))
        look.color = value(.foregroundStyle)
        look.letterSpacing = number(.characterSpacing) ?? 0
        look.lineHeight = number(.lineHeight)
        look.lineSpacing = number(.lineSpacing) ?? 0
        look.decorations = value(.textDecorations)?.enumeration.map { TextDecorations(rawValue: $0) } ?? .none
        look.baselineOffset = number(.baselineOffset)
        return look
    }

    /// A label's spans as runs of its words, each in its case - its own, else the label's - and its look; nil
    /// where the label holds no spans. A span saying `image` is the picture's
    /// run, its words the object-replacement mark a typesetter counts.
    public var textRuns: [TextRun]? {
        guard let spans = children.first(where: { $0.type == .spans }) else { return nil }
        let labelCase = value(.textCase)
        return spans.children.filter { $0.type == .span }.map { span in
            var look = span.textLook
            look.background = span.value(.background)
            let image = span.value(.image).flatMap { ImageSource(propValue: $0) }
            let textCase = (span.value(.textCase) ?? labelCase)?.enumeration.flatMap(TextCase.init(rawValue:))
            let text = image != nil ? "\u{FFFC}"
                : (textCase ?? .none).applied(to: span.string(.text) ?? "")
            return TextRun(text: text, look: look, image: image)
        }
    }
}
