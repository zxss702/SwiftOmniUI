// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// What a `.fill`, a `.background` or a `.foregroundStyle` paints with - the
// SwiftUI vocabulary over this library's `Brush`: a colour, a gradient, or a
// material, each answering for the brush it stands for.
// Design: docs/design/types/brushes.md

/// What a shape, a background or a foreground is painted with: a `Color`, a
/// `LinearGradient`, a `Material`, or an `AnyShapeStyle` erasing whichever it
/// is.
///
///     Capsule().fill(.regularMaterial)
///     Text("…").background(LinearGradient(colors: [.mint, .teal],
///         startPoint: .leading, endPoint: .trailing))
///
/// A style answers for the brush it stands for, so every place a brush can go
/// a style can.
@preconcurrency @MainActor public protocol ShapeStyle {
    /// The brush the style stands for - how every style crosses.
    var brush: Brush { get }
}

extension ShapeStyle {
    /// The brush a style stands for, read where a property takes one.
    var asBrush: Brush { brush }
}

/// The colours a gradient paints between, each with where along it it sits.
///
///     Gradient(colors: [.mint, .teal])
///     Gradient(stops: [.init(color: .gold, location: 0),
///                      .init(color: .tomato, location: 1)])
public struct Gradient: Equatable, Sendable {
    /// One colour of the gradient, and where along it it stands.
    public struct Stop: Equatable, Sendable {
        /// What colour the gradient is at this point.
        public var color: Color

        /// Where along the gradient it stands, from 0 to 1.
        public var location: Double

        /// A stop: the colour, then how far along it sits.
        public init(color: Color, location: Double) {
            self.color = color
            self.location = location
        }
    }

    /// The colours the gradient paints between, in order.
    public var stops: [Stop]

    /// A gradient of `stops`.
    public init(stops: [Stop]) {
        self.stops = stops
    }

    /// A gradient of `colors` spread evenly.
    public init(colors: [Color]) {
        stops = colors.enumerated().map { index, color in
            Stop(
                color: color,
                location: colors.count > 1 ? Double(index) / Double(colors.count - 1) : 0)
        }
    }

    /// A gradient of `colors` at `locations` along it; the count of each
    /// matching, stops standing where their colour says.
    public init(colors: [Color], locations: [Double]) {
        stops = zip(colors, locations).map { Stop(color: $0, location: $1) }
    }

    /// The stops as the brush's own.
    var gradientStops: [GradientStop] {
        stops.map { GradientStop($0.color, $0.location) }
    }
}

/// A gradient painted along a line:
///
///     Rectangle().fill(LinearGradient(colors: [.mint, .teal],
///         startPoint: .leading, endPoint: .trailing))
///     Text("…").background(.linearGradient(...)) - no, as a style:
///     Text("…").background(LinearGradient(colors: [.white, .clear],
///         startPoint: .top, endPoint: .bottom))
///
/// Standing alone it is a view filling the room it is given with the gradient.
public struct LinearGradient: ShapeStyle, View {
    /// The gradient's colours.
    let gradient: Gradient

    /// Where the line starts, as a fraction of what it paints.
    let startPoint: UnitPoint

    /// Where the line ends.
    let endPoint: UnitPoint

    /// A gradient of `colors` spread evenly from `startPoint` to `endPoint`.
    public init(colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint) {
        self.init(gradient: Gradient(colors: colors), startPoint: startPoint, endPoint: endPoint)
    }

    /// A gradient of `stops` from `startPoint` to `endPoint`.
    public init(stops: [Gradient.Stop], startPoint: UnitPoint, endPoint: UnitPoint) {
        self.init(gradient: Gradient(stops: stops), startPoint: startPoint, endPoint: endPoint)
    }

    /// A `gradient` from `startPoint` to `endPoint`.
    public init(gradient: Gradient, startPoint: UnitPoint, endPoint: UnitPoint) {
        self.gradient = gradient
        self.startPoint = startPoint
        self.endPoint = endPoint
    }

    /// The brush the style stands for.
    public var brush: Brush {
        .linearGradient(
            gradient.gradientStops,
            startPoint: Point(x: startPoint.x, y: startPoint.y),
            endPoint: Point(x: endPoint.x, y: endPoint.y))
    }

    /// A rectangle filled with the gradient, stretching to its room.
    public var body: some View {
        Rectangle().fill(brush).flex(0)
    }
}

/// A material - the platform's own frosted translucency, what is behind the
/// view showing through it:
///
///     Text("…").background(.regularMaterial, in: Capsule())
///
/// A host paints it with the platform's material where the platform draws
/// one; elsewhere it stands for a soft translucency in the room's tone.
public struct Material: ShapeStyle, Sendable {
    /// Which material this is, as the number that crosses ahead of its parts.
    enum Kind: Int32, Sendable {
        case ultraThin = 1
        case thin = 2
        case regular = 3
        case thick = 4
        case ultraThick = 5
        case bar = 6
    }

    /// Which material this is.
    let kind: Kind

    /// The brush the style stands for.
    public var brush: Brush { .material(kind.rawValue) }
}

extension ShapeStyle where Self == Material {
    /// A material blurrier than `.thinMaterial` - the least opaque.
    public static var ultraThinMaterial: Material { Material(kind: .ultraThin) }

    /// A thin material - a hint of what is behind.
    public static var thinMaterial: Material { Material(kind: .thin) }

    /// The middle material.
    public static var regularMaterial: Material { Material(kind: .regular) }

    /// A material nearer opaque than `.regularMaterial`.
    public static var thickMaterial: Material { Material(kind: .thick) }

    /// A material blurriest of all - nearly the room's own colour.
    public static var ultraThickMaterial: Material { Material(kind: .ultraThick) }

    /// The material of the platform's own bars - its toolbars, its sidebars.
    public static var barMaterial: Material { Material(kind: .bar) }

    /// `.ultraThinMaterial`, short.
    public static var ultraThin: Material { .ultraThinMaterial }

    /// `.thinMaterial`, short.
    public static var thin: Material { .thinMaterial }

    /// `.regularMaterial`, short.
    public static var regular: Material { .regularMaterial }

    /// `.thickMaterial`, short.
    public static var thick: Material { .thickMaterial }

    /// `.ultraThickMaterial`, short.
    public static var ultraThick: Material { .ultraThickMaterial }

    /// `.barMaterial`, short.
    public static var bar: Material { .barMaterial }
}

extension ShapeStyle where Self == Color {
    /// The foreground's own colour.
    public static var primary: Color { Color.primary }

    /// A foreground colour one step fainter.
    public static var secondary: Color { Color.secondary }

    /// A foreground colour two steps fainter.
    public static var tertiary: Color { Color.tertiary }

    /// A foreground colour three steps fainter.
    public static var quaternary: Color { Color.quaternary }

    /// The app's accent colour.
    public static var accentColor: Color { Color.accentColor }

    /// The window's own fill - SwiftUI's `.background` style, bridged to the
    /// light/dark pair `Color.background` already speaks.
    public static var background: Color { Color.background }

    /// Clear - no colour at all.
    public static var clear: Color { Color.clear }

    /// Black, as a shape style - `.background(.black)`.
    public static var black: Color { Color.black }

    /// White, as a shape style.
    public static var white: Color { Color.white }

    /// Gray, as a shape style.
    public static var gray: Color { Color.gray }

    /// Red, as a shape style.
    public static var red: Color { Color.red }

    /// Orange, as a shape style.
    public static var orange: Color { Color.orange }

    /// Yellow, as a shape style.
    public static var yellow: Color { Color.yellow }

    /// Green, as a shape style.
    public static var green: Color { Color.green }

    /// Mint, as a shape style.
    public static var mint: Color { Color.mint }

    /// Teal, as a shape style.
    public static var teal: Color { Color.teal }

    /// Cyan, as a shape style.
    public static var cyan: Color { Color.cyan }

    /// Blue, as a shape style.
    public static var blue: Color { Color.blue }

    /// Indigo, as a shape style.
    public static var indigo: Color { Color.indigo }

    /// Purple, as a shape style.
    public static var purple: Color { Color.purple }

    /// Pink, as a shape style.
    public static var pink: Color { Color.pink }

    /// Brown, as a shape style.
    public static var brown: Color { Color.brown }
}

extension Color: ShapeStyle {
    /// One colour, everywhere.
    public var brush: Brush { .solidColor(self) }
}

/// A style whichever way it was given: what a view keeping a caller's style
/// of any kind holds:
///
///     struct Badge: View {
///         let fill: AnyShapeStyle
///
///         init(fill: some ShapeStyle = Color.accentColor) {
///             self.fill = AnyShapeStyle(fill)
///         }
///     }
public struct AnyShapeStyle: ShapeStyle {
    /// The brush whatever it wraps stands for.
    public var brush: Brush

    /// Erases `style`.
    public init(_ style: some ShapeStyle) {
        brush = style.brush
    }
}
