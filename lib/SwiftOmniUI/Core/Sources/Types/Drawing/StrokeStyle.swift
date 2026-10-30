// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The style an outline or a fill is drawn in, as SwiftUI's `GraphicsContext`
// calls take them: what a `stroke` draws with, and which points a `fill`
// counts as inside.

/// How an outline is drawn - how wide its stroke is, and how its ends and
/// corners are finished.
///
///     context.stroke(path, with: .color(.steelBlue),
///                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
public struct StrokeStyle: Equatable, Sendable {
    /// How wide the stroke is, in the canvas's own units.
    public var lineWidth: Double

    /// How the ends of open lines are drawn.
    public var lineCap: LineCap

    /// How the corners where segments meet are drawn.
    public var lineJoin: LineJoin

    /// How far a sharp corner may reach before it is cut flat, in multiples of
    /// the stroke width - SwiftUI's `miterLimit`.
    public var miterLimit: Double

    /// The dashes and the gaps between them, in path units;
    /// empty is a solid line.
    public var dash: [Double]

    /// How far into the dash pattern the line starts, in path units.
    public var dashPhase: Double

    /// An outline `lineWidth` wide, its ends, corners, miters and dashes as
    /// said - SwiftUI's `StrokeStyle` spelling.
    public init(
        lineWidth: Double,
        lineCap: LineCap = .flat,
        lineJoin: LineJoin = .miter,
        miterLimit: Double = 10,
        dash: [Double] = [],
        dashPhase: Double = 0
    ) {
        self.lineWidth = lineWidth
        self.lineCap = lineCap
        self.lineJoin = lineJoin
        self.miterLimit = miterLimit
        self.dash = dash
        self.dashPhase = dashPhase
    }

    /// An outline `lineWidth` wide, ends flat and corners mitered.
    public init(lineWidth: Double) {
        self.init(lineWidth: lineWidth, lineCap: .flat, lineJoin: .miter)
    }
}

/// Which points of a path a fill counts as inside.
public struct FillStyle: Equatable, Sendable {
    /// Whether inside is decided by the even-odd rule: a point is inside where
    /// a ray out crosses the outline an odd number of times. The winding rule
    /// answers false for one wound around an even net number of times.
    public var isEOFilled: Bool

    /// Whether the fill's edges blend into what is under them - declared for
    /// compatibility, as the canvases always antialias.
    public var isAntialiased: Bool

    /// A rule and an edge, together.
    public init(eoFill: Bool, antialiased: Bool) {
        self.isEOFilled = eoFill
        self.isAntialiased = antialiased
    }

    /// The winding rule, antialiased - the fill a plain call gets.
    public init() {
        self.init(eoFill: false, antialiased: true)
    }
}
