// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// The colour and letter spacing of a control's text, without the text
/// itself - worn by the pickers too, which format a value rather than show a
/// text of their own. A control that says something wears `TextElement`.
@preconcurrency @MainActor public protocol TextStyleElement: PropertyContainer {}

extension TextStyleElement {
    /// The colour of the text; a `Color(light:dark:)` follows the system color scheme.
    public func foregroundStyle(_ value: Color) -> Modified {
        modified { $0.writeForeground(value.brush, textIsExplicit: true) }
    }

    /// The style the text is painted with: a colour paints it in that colour;
    /// a gradient or a material paints it in the style's first colour, a
    /// painter of one colour taking what the style leads with.
    ///
    ///     Text("…").foregroundStyle(.secondary)
    ///     Image(symbol: "checkmark").foregroundStyle(.green, .mint)
    public func foregroundStyle(_ style: some ShapeStyle) -> Modified {
        modified { $0.writeForeground(style.brush, textIsExplicit: true) }
    }

    /// The symbol-palette spelling of `foregroundStyle`: the first style tints
    /// the symbol, a platform without palette rendering taking the first
    /// colour alone.
    public func foregroundStyle(_ primary: some ShapeStyle, _ secondary: some ShapeStyle) -> Modified {
        foregroundStyle(primary)
    }

    /// The symbol-palette spelling of `foregroundStyle`, of three.
    public func foregroundStyle(
        _ primary: some ShapeStyle, _ secondary: some ShapeStyle, _ tertiary: some ShapeStyle
    ) -> Modified {
        foregroundStyle(primary)
    }

    /// The colour of the text, the spelling SwiftUI's older API kept -
    /// `foregroundStyle`'s.
    public func foregroundColor(_ value: Color) -> Modified { foregroundStyle(value) }

    /// The space added between letters, in device units.
    @_spi(Host) public func characterSpacing(_ value: Double) -> Modified { setValue(TextStyleElementContract.characterSpacing, value) }

    /// The space added between letters, the SwiftUI spelling of
    /// `.characterSpacing`.
    public func kerning(_ value: Double) -> Modified { characterSpacing(value) }

    /// The space added between letters - `tracking` scales with the point
    /// size on Apple's platforms; here the value is the device units added,
    /// as `.kerning`.
    public func tracking(_ value: Double) -> Modified { characterSpacing(value) }
}

extension TextStyleElement where Self: VisualElement {
    /// `kerning` from a state, `$x`: the host animates the property to each
    /// new value, and no view is rebuilt for it.
    public func kerning(_ state: Binding<Double>) -> Modified { characterSpacing(state) }

    /// `tracking` from a state, `$x`: the host animates the property to each
    /// new value, and no view is rebuilt for it.
    public func tracking(_ state: Binding<Double>) -> Modified { characterSpacing(state) }

    /// `characterSpacing` from a state, `$x`: the host animates the property to
    /// each new value, and no view is rebuilt for it.
    @_spi(Host) public func characterSpacing(_ state: Binding<Double>) -> Modified {
        journey(TextStyleElementContract.characterSpacing, by: state)
    }

    /// `foregroundStyle` from a state, `$x`: the host animates the property to each
    /// new value, and no view is rebuilt for it.
    public func foregroundStyle(_ state: Binding<Color>) -> Modified {
        journey(TextStyleElementContract.foregroundStyle, by: state)
    }

    /// `foregroundColor` from a state, `$x` - `foregroundStyle`'s by its older
    /// name.
    public func foregroundColor(_ state: Binding<Color>) -> Modified {
        foregroundStyle(state)
    }
}
