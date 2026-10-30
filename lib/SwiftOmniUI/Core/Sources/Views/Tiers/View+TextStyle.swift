// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

extension View {
    /// The font every `Text` inside this view draws in - SwiftUI's
    /// environment-carried font. A text naming its own keeps its own:
    ///
    ///     VStack {
    ///         Text("Inherited")
    ///         Text("Own").font(.caption)
    ///     }
    ///     .font(.body)
    ///
    /// `Font?` against `FontElement.font(_:)`'s `Font` keeps a `Text`'s own
    /// member the nearer answer - on a text itself this spelling still wins
    /// only where the element's own does not apply.
    public func font(_ font: Font?) -> ModifiedContent {
        revised { node in
            guard let font else { return }
            if let weight = font.weight {
                node.writeInherited(FontElementContract.fontWeight, weight)
            }
            if let design = font.design {
                node.writeInherited(FontElementContract.fontDesign, design)
            }
            switch font.basis {
            case .textStyle(let style):
                node.writeInherited(FontElementContract.fontTextStyle, style)
            case .system(let size):
                node.writeInherited(FontElementContract.fontSize, size)
            case .custom(let family, let size):
                node.writeInherited(FontElementContract.fontFamily, Name(family))
                node.writeInherited(FontElementContract.fontSize, size)
            }
            if font.attributes != .none {
                node.writeInherited(FontElementContract.fontAttributes, font.attributes)
            }
            node.hasExplicitFontBasis = true
        }
    }

    /// The weight every text inside draws at - the container spelling of
    /// `Text`'s `.fontWeight`.
    public func fontWeight(_ weight: Font.Weight?) -> ModifiedContent {
        revised { node in
            guard let weight else { return }
            node.writeInherited(FontElementContract.fontWeight, weight)
        }
    }

    /// The letter shape every text inside draws with - the container spelling
    /// of `Text`'s `.fontDesign`.
    public func fontDesign(_ design: FontDesign?) -> ModifiedContent {
        revised { node in
            guard let design else { return }
            node.writeInherited(FontElementContract.fontDesign, design)
        }
    }

    /// The foreground style inherited by text, symbols and shapes inside.
    /// An explicit text colour or shape fill keeps its own style.
    @_disfavoredOverload
    public func foregroundStyle(_ style: some ShapeStyle) -> ModifiedContent {
        revised { $0.writeForeground(style.brush) }
    }

    /// The foreground colour inherited by text, symbols and shapes inside.
    public func foregroundColor(_ color: Color?) -> ModifiedContent {
        revised { node in
            guard let color else { return }
            node.writeForeground(color.brush)
        }
    }

    /// Extra space between the lines of every text inside - the container
    /// spelling of `Text`'s `.lineSpacing`.
    public func lineSpacing(_ value: Double?) -> ModifiedContent {
        revised { node in
            guard let value else { return }
            node.writeInherited(LineHeightElementContract.lineSpacing, value)
        }
    }

    /// How every multiline text inside aligns its lines - the container
    /// spelling of `Text`'s `.multilineTextAlignment`.
    public func multilineTextAlignment(_ alignment: TextAlignment?) -> ModifiedContent {
        revised { node in
            guard let alignment else { return }
            node.writeInherited(TextAlignmentElementContract.multilineTextAlignment, alignment)
        }
    }

    /// The space added between letters of every text inside - the container
    /// spelling of `Text`'s `.kerning`.
    public func kerning(_ value: Double?) -> ModifiedContent {
        revised { node in
            guard let value else { return }
            node.writeInherited(TextStyleElementContract.characterSpacing, value)
        }
    }

    /// `kerning` under another name - SwiftUI's `.tracking`.
    public func tracking(_ value: Double?) -> ModifiedContent {
        kerning(value)
    }

    /// The most lines every text inside shows before it is cut - the
    /// container spelling of `Text`'s `.lineLimit`; `nil` is no limit.
    public func lineLimit(_ limit: Int?) -> ModifiedContent {
        revised { node in
            node.writeInherited(TextContract.lineLimit, limit ?? -1)
        }
    }

    /// Struck-through text inside - the container spelling of `Text`'s
    /// `.strikethrough`. A text wearing its own decorations keeps them.
    @_disfavoredOverload
    public func strikethrough(_ isActive: Bool = true) -> ModifiedContent {
        revised { node in
            guard isActive else { return }
            node.writeInherited(DecorableTextElementContract.textDecorations, .strikethrough)
        }
    }
}
