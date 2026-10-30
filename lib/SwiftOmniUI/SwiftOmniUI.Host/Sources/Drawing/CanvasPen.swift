// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore

/// What a canvas draws with: each setting holds until the next of its kind, `saveState` remembers them all and
/// `restoreState` puts them back - the same on every host drawing in Swift.
/// Design: docs/design/types/drawing.md#settings-hold-until-changed
@_spi(Host) public struct CanvasPen: Equatable, Sendable {
    /// The colour fills are drawn in: black until set.
    public var fill: HostValue = .color(red: 0, green: 0, blue: 0, alpha: 255)

    /// The colour outlines are drawn in: black until set.
    public var stroke: HostValue = .color(red: 0, green: 0, blue: 0, alpha: 255)

    /// The colour text is drawn in: black until set.
    public var text: HostValue = .color(red: 0, green: 0, blue: 0, alpha: 255)

    /// An outline's width, never below nothing: one until set.
    public var strokeWidth = 1.0

    /// The text's size in points; the platform's own until set.
    public var fontSize: Double?
    public var fontFamily = ""
    public var fontWeight = 400.0
    public var fontItalic = false

    /// How opaque everything is drawn, from nothing to whole: whole until set.
    public var alpha = 1.0

    /// How the ends of open lines are drawn: flat until set.
    public var strokeCap: LineCap = .flat

    /// How the corners where segments meet are drawn: mitered until set.
    public var strokeJoin: LineJoin = .miter

    public var strokeMiter = 10.0
    public var strokeDash: [Double] = []
    public var strokePhase = 0.0

    /// Which points a fill counts as inside: the winding rule until set -
    /// `true` asks for the even-odd one.
    public var fillEvenOdd = false

    private var saved: [CanvasPen] = []

    /// A pen drawing black, one wide, whole.
    public init() {}

    /// Takes `instruction` where it is a setting or a state's saving or putting back: whether it was one.
    public mutating func take(_ instruction: CanvasInstruction) -> Bool {
        switch instruction {
        case .fillColor(let color): fill = color
        case .strokeColor(let color): stroke = color
        case .foregroundStyle(let color): text = color
        case .strokeWidth(let width): strokeWidth = max(0, width)
        case .fontSize(let size): fontSize = max(0, size)
        case .fontStyle(let family, let weight, let italic):
            fontFamily = family; fontWeight = weight; fontItalic = italic
        case .alpha(let value): alpha = min(max(value, 0), 1)
        case .strokeStyle(let width, let cap, let join):
            strokeWidth = max(0, width)
            strokeCap = cap
            strokeJoin = join
        case .fillStyle(let evenOdd): fillEvenOdd = evenOdd
        case .completeStrokeStyle(let style):
            strokeWidth = max(0, style.lineWidth)
            strokeCap = style.lineCap
            strokeJoin = style.lineJoin
            strokeMiter = max(1, style.miterLimit)
            strokeDash = style.dash.map { max(0, $0) }
            strokePhase = style.dashPhase
        case .saveState: saved.append(self)
        case .restoreState:
            guard let last = saved.popLast() else { return true }
            let stack = saved
            self = last
            saved = stack
        default: return false
        }
        return true
    }

    /// How many states are saved and not yet put back.
    public var savedDepth: Int { saved.count }
}
