// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// How the text of a control is set in type - its size, its family, its
/// weight.
@preconcurrency @MainActor public protocol FontElement: PropertyContainer {}

extension FontElement {
    /// How big the text is, in device units.
    @_spi(Host) public func fontSize(_ value: Double) -> Modified { setValue(FontElementContract.fontSize, value) }

    /// Which font, by the alias the app registered it under - not the file name.
    @_spi(Host) public func fontFamily(_ value: String) -> Modified { setValue(FontElementContract.fontFamily, Name(value)) }

    /// Bold, italic, or both.
    ///
    ///     Text("Total").fontAttributes([.bold, .italic])
    @_spi(Host) public func fontAttributes(_ value: FontAttributes) -> Modified { setValue(FontElementContract.fontAttributes, value) }

    /// Whether the text grows with the system's text-size setting. On by
    /// default.
    @_spi(Host) public func fontAutoScalingEnabled(_ value: Bool) -> Modified { setValue(FontElementContract.fontAutoScalingEnabled, value) }

    /// The font text is drawn in - the SwiftUI spelling:
    ///
    ///     Text("Chapter").font(.title)
    ///     Text("Code").font(.system(size: 13, design: .monospaced))
    ///
    /// A named text style stands as `fontTextStyle`; an explicit size as
    /// `fontSize`, a named family as `fontFamily` - the members the font
    /// decomposes into, so a host reads it through the members it already
    /// knows.
    public func font(_ font: Font) -> Modified {
        modified { frame in
            frame.modifyContent(for: FontElementContract.self) { node in
                if LibraryContracts.byType[node.type]?.worn.contains(where: {
                    ObjectIdentifier($0) == ObjectIdentifier(FontElementContract.self)
                }) == true {
                    node.props[.fontSize] = nil
                    node.props[.fontTextStyle] = nil
                    node.props[.fontFamily] = nil
                }
                if let weight = font.weight {
                    node.writeOrInherit(FontElementContract.fontWeight, weight)
                }
                if let design = font.design {
                    node.writeOrInherit(FontElementContract.fontDesign, design)
                }
                switch font.basis {
                case .textStyle(let style):
                    node.writeOrInherit(FontElementContract.fontTextStyle, style)
                case .system(let size):
                    node.writeOrInherit(FontElementContract.fontSize, size)
                case .custom(let family, let size):
                    node.writeOrInherit(FontElementContract.fontFamily, Name(family))
                    node.writeOrInherit(FontElementContract.fontSize, size)
                }
                if font.attributes != .none {
                    let worn = node.props[.fontAttributes].flatMap(FontAttributes.init(propValue:)) ?? .none
                    node.writeOrInherit(FontElementContract.fontAttributes, worn.union(font.attributes))
                }
                node.hasExplicitFontBasis = true
            }
        }
    }

    /// The weight the text is drawn at - the SwiftUI spelling:
    ///
    ///     Text("Total").fontWeight(.semibold)
    public func fontWeight(_ weight: Font.Weight) -> Modified {
        modified { $0.writeOrInherit(FontElementContract.fontWeight, weight) }
    }

    /// The letter shape of the system font - the SwiftUI spelling:
    ///
    ///     Text("Code").fontDesign(.monospaced)
    public func fontDesign(_ design: FontDesign) -> Modified {
        modified { $0.writeOrInherit(FontElementContract.fontDesign, design) }
    }

    /// One of the platform's named text styles - what `.font(.title)` and the
    /// rest write. The platform chooses its size and follows the user's
    /// text-size setting.
    ///
    ///     Text("Caption").fontTextStyle(.caption)
    @_spi(Host) public func fontTextStyle(_ style: FontTextStyle) -> Modified {
        setValue(FontElementContract.fontTextStyle, style)
    }

    /// Bold text - the SwiftUI spelling of `.fontAttributes(.bold)`, added to
    /// whatever attributes the text already wears.
    public func bold() -> Modified {
        let worn = node.controlContent.props[.fontAttributes].flatMap(FontAttributes.init(propValue:)) ?? .none
        return modified { $0.writeOrInherit(FontElementContract.fontAttributes, worn.union(.bold)) }
    }

    /// Italic text - `.fontAttributes(.italic)` added to what is worn.
    public func italic() -> Modified {
        let worn = node.controlContent.props[.fontAttributes].flatMap(FontAttributes.init(propValue:)) ?? .none
        return modified { $0.writeOrInherit(FontElementContract.fontAttributes, worn.union(.italic)) }
    }
}

extension FontElement where Self: VisualElement {
    /// `fontAttributes` from a state, `$x`: the host sets each new value as it
    /// stands, and no view is rebuilt for it.
    @_spi(Host) public func fontAttributes(_ state: Binding<FontAttributes>) -> Modified {
        plain(FontElementContract.fontAttributes, by: state)
    }

    /// `fontAutoScalingEnabled` from a state, `$x`: the host sets each new
    /// value as it stands, and no view is rebuilt for it.
    @_spi(Host) public func fontAutoScalingEnabled(_ state: Binding<Bool>) -> Modified {
        plain(FontElementContract.fontAutoScalingEnabled, by: state)
    }

    /// `fontSize` from a state, `$x`: the host animates the property to each
    /// new value, and no view is rebuilt for it.
    @_spi(Host) public func fontSize(_ state: Binding<Double>) -> Modified {
        journey(FontElementContract.fontSize, by: state)
    }

    /// `fontTextStyle` from a state, `$x`: the host sets each new value as it
    /// stands, and no view is rebuilt for it.
    @_spi(Host) public func fontTextStyle(_ state: Binding<FontTextStyle>) -> Modified {
        plain(FontElementContract.fontTextStyle, by: state)
    }

    /// `fontWeight` from a state, `$x`: the host sets each new value as it
    /// stands, and no view is rebuilt for it.
    public func fontWeight(_ state: Binding<Font.Weight>) -> Modified {
        plain(FontElementContract.fontWeight, by: state)
    }

    /// `fontDesign` from a state, `$x`: the host sets each new value as it
    /// stands, and no view is rebuilt for it.
    public func fontDesign(_ state: Binding<FontDesign>) -> Modified {
        plain(FontElementContract.fontDesign, by: state)
    }
}
