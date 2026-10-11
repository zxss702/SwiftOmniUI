// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// `Path` spelled the way SwiftUI spells it - `CGPoint`, `CGSize` and `CGRect`
// arguments beside the core's `Point`, `Size` and `Rect`. The geometry types
// live in Foundation's CoreGraphics on every platform, so the bridge lives
// here where Foundation is allowed.

import Foundation
import SwiftOmniUICore

extension Point {
    /// `value`, in device units.
    public init(_ value: CGPoint) {
        self.init(x: Double(value.x), y: Double(value.y))
    }
}

extension Size {
    /// `value`, in device units.
    public init(_ value: CGSize) {
        self.init(width: Double(value.width), height: Double(value.height))
    }
}

extension Rect {
    /// `value`, in device units.
    public init(_ value: CGRect) {
        self.init(
            x: Double(value.origin.x), y: Double(value.origin.y),
            width: Double(value.width), height: Double(value.height))
    }
}

extension Path {
    /// `rect`'s outline.
    public init(_ rect: CGRect) {
        self.init(Rect(rect))
    }

    /// The ellipse `rect` holds, as `GraphicsContext` calls draw it.
    public init(ellipseIn rect: CGRect) {
        self.init(ellipseIn: Rect(rect))
    }

    /// `rect` with every corner rounded by `cornerSize` - how far across each
    /// bend reaches, then how far down.
    public init(roundedRect rect: CGRect, cornerSize: CGSize) {
        self.init(roundedRect: Rect(rect), cornerSize: Size(cornerSize))
    }

    /// The same, in `style`'s bend - `.continuous` drawing the circular bend
    /// the outline is.
    public init(roundedRect rect: CGRect, cornerSize: CGSize, style: RoundedCornerStyle) {
        self.init(roundedRect: Rect(rect), cornerSize: Size(cornerSize), style: style)
    }

    /// `rect` with every corner rounded by `cornerRadius`.
    public init(roundedRect rect: CGRect, cornerRadius: Double) {
        self.init(roundedRect: Rect(rect), cornerRadius: cornerRadius)
    }

    /// The same, in `style`'s bend.
    public init(roundedRect rect: CGRect, cornerRadius: Double, style: RoundedCornerStyle) {
        self.init(roundedRect: Rect(rect), cornerRadius: cornerRadius, style: style)
    }

    /// `rect` with its corners rounded by `cornerRadii`.
    public init(roundedRect rect: CGRect, cornerRadii: RectangleCornerRadii) {
        self.init(roundedRect: Rect(rect), cornerRadii: cornerRadii)
    }

    /// The same, in `style`'s bend.
    public init(roundedRect rect: CGRect, cornerRadii: RectangleCornerRadii, style: RoundedCornerStyle) {
        self.init(roundedRect: Rect(rect), cornerRadii: cornerRadii, style: style)
    }

    /// Moves the pen to `point` without drawing.
    public mutating func move(to point: CGPoint) {
        move(to: Point(point))
    }

    /// Draws a line to `point`.
    public mutating func addLine(to point: CGPoint) {
        addLine(to: Point(point))
    }

    /// Draws a line to each of `lines` in turn.
    public mutating func addLines(_ lines: [CGPoint]) {
        addLines(lines.map(Point.init))
    }

    /// Draws a cubic Bézier to `point`, bent by `control1` and `control2`.
    public mutating func addCurve(to point: CGPoint, control1: CGPoint, control2: CGPoint) {
        addCurve(to: Point(point), control1: Point(control1), control2: Point(control2))
    }

    /// Draws a quadratic Bézier to `point`, bent by `control`.
    public mutating func addQuadCurve(to point: CGPoint, control: CGPoint) {
        addQuadCurve(to: Point(point), control: Point(control))
    }

    /// Draws `rect`'s outline.
    public mutating func addRect(_ rect: CGRect) {
        addRect(Rect(rect))
    }

    /// Draws each of `rects`' outline.
    public mutating func addRects(_ rects: [CGRect]) {
        addRects(rects.map(Rect.init))
    }

    /// Draws the ellipse `rect` holds.
    public mutating func addEllipse(in rect: CGRect) {
        addEllipse(in: Rect(rect))
    }

    /// Draws `rect` rounded by `cornerSize`.
    public mutating func addRoundedRect(
        in rect: CGRect, cornerSize: CGSize, style: RoundedCornerStyle = .circular
    ) {
        addRoundedRect(in: Rect(rect), cornerSize: Size(cornerSize), style: style)
    }

    /// Draws `rect` rounded by `cornerRadius`.
    public mutating func addRoundedRect(in rect: CGRect, cornerRadius: Double) {
        addRoundedRect(in: Rect(rect), cornerRadius: cornerRadius)
    }
}
