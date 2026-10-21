// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The drawing surface `Canvas`'s closure form is handed, as SwiftUI writes it:
// the calls gather into the canvas's `drawable` drawing, which a host replays
// on its own canvas - the same records `Draw` writes.

/// What a `Canvas`'s drawing closure draws on.
///
///     Canvas { context, size in
///         context.fill(
///             Path(roundedRect: Rect(0, 0, size.width, 40), cornerRadius: 8),
///             with: .color(.cornflowerBlue))
///         context.stroke(
///             Path { path in
///                 path.move(to: Point(x: 0, y: 0))
///                 path.addLine(to: Point(x: size.width, y: size.height))
///             },
///             with: .color(.steelBlue),
///             style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
///     }
///
/// The calls gather into a drawing - the same records `Draw` writes - and the
/// closure runs again as the canvas's size settles, so what depends on `size`
/// is drawn at the size it lands.
public struct GraphicsContext: Sendable {
    public init() {}
    /// The instructions gathered so far, in drawing order.
    var commands: [DrawCommand] = []

    /// Renders the recorded drawing to an immutable native bitmap.
    public func makeImage(size: Size, scale: Double = 1) -> BitmapImage? {
        BitmapImage.render(size: size, scale: scale, drawing: commands)
    }

    /// What a fill or a stroke is drawn with.
    public enum Shading: Sendable {
        /// One colour.
        case color(Color)

        /// The colour, where the shading is one.
        var color: Color? {
            if case .color(let color) = self { return color }
            return nil
        }
    }
}

extension GraphicsContext {
    /// Draws an isolated group, preserving the caller's transforms and paint.
    public mutating func drawLayer(content: (inout GraphicsContext) throws -> Void) rethrows {
        var layer = GraphicsContext()
        try content(&layer)
        commands += [Draw.saveState()] + layer.commands + [Draw.restoreState()]
    }

    public mutating func translateBy(x: Double, y: Double) {
        commands.append(Draw.translate(dx: x, dy: y))
    }

    public mutating func scaleBy(x: Double, y: Double) {
        commands.append(Draw.scale(sx: x, sy: y))
    }

    public mutating func rotate(by angle: Angle) {
        commands.append(Draw.rotate(angle.degrees))
    }

    /// Fills `path` in the shading's colour, `style`'s rule deciding which
    /// points are inside.
    public mutating func fill(_ path: Path, with shading: Shading, style: FillStyle) {
        guard let color = shading.color else { return }
        commands += [
            Draw.fillColor(color),
            Draw.fillStyle(eoFill: style.isEOFilled),
            Draw.fillGeometry(path),
        ]
    }

    /// Fills `path` in the shading's colour, by the winding rule.
    public mutating func fill(_ path: Path, with shading: Shading) {
        fill(path, with: shading, style: FillStyle())
    }

    /// Outlines `path` in the shading's colour, as `style` finishes it.
    public mutating func stroke(_ path: Path, with shading: Shading, style: StrokeStyle) {
        guard let color = shading.color else { return }
        commands += [
            Draw.strokeColor(color),
            Draw.completeStrokeStyle(style),
            Draw.drawGeometry(path),
        ]
    }

    /// Outlines `path` in the shading's colour, `lineWidth` wide.
    public mutating func stroke(_ path: Path, with shading: Shading, lineWidth: Double) {
        stroke(path, with: shading, style: StrokeStyle(lineWidth: lineWidth))
    }
}

extension GraphicsContext {
    /// Writes `text` inside `rect`, the two alignments placing the words in
    /// the box as `Draw.drawText`'s do - the box is also what cuts them.
    ///
    ///     context.draw(
    ///         Text("42").foregroundStyle(.white),
    ///         in: Rect(0, 0, 40, 16),
    ///         horizontalAlignment: .center, verticalAlignment: .center)
    ///
    /// - Parameters:
    ///   - text: the text to write. Its words cross - a `Text(…)`'s own, the
    ///     display string a `Text(LocalizedStringKey)`'s key looks up to, a
    ///     `+` or `.spans` one's runs joined, a `Text($state)`'s read of the
    ///     state now - and the colour and size it wears are written ahead of
    ///     it, under a state saved for them so the pen's own hold. What the
    ///     drawing has no instruction for - a weight, a family, a run's own
    ///     look - stays behind.
    ///   - rect: the box the words are drawn in and cut at.
    ///   - horizontalAlignment: where they sit across the box.
    ///   - verticalAlignment: and down it.
    public mutating func draw(
        _ text: Text,
        in rect: Rect,
        horizontalAlignment: TextAlignment = .start,
        verticalAlignment: TextAlignment = .start
    ) {
        let look = text.drawnLook
        if !look.isEmpty { commands.append(Draw.saveState()) }
        commands += look
        commands.append(Draw.drawText(
            text.drawnWords,
            x: rect.x, y: rect.y, width: rect.width, height: rect.height,
            horizontalAlignment: horizontalAlignment, verticalAlignment: verticalAlignment))
        if !look.isEmpty { commands.append(Draw.restoreState()) }
    }

    /// Writes `text` with its `anchor` on `point` - the way SwiftUI's
    /// `draw(_:at:anchor:)` places one:
    ///
    ///     context.draw(Text("●"), at: Point(x: 40, y: 24))
    ///
    /// A drawn text goes in a box, which is also what cuts it: `at` stands a
    /// box reaching far past any canvas on the anchor, so the words take all
    /// the room they ask. An anchor between the three stops a box's
    /// alignment knows - the near edge, the middle, the far - is drawn at
    /// the nearer.
    ///
    /// - Parameters:
    ///   - text: the text to write, as `draw(_:in:)` takes it.
    ///   - point: where the anchor lands, in the canvas's coordinates.
    ///   - anchor: which point of the words lands on it - `.center` the
    ///     middle, `.topLeading` the top left corner.
    public mutating func draw(_ text: Text, at point: Point, anchor: UnitPoint = .center) {
        draw(
            text, in: Self.room(at: point, anchor: anchor),
            horizontalAlignment: Self.stop(anchor.x), verticalAlignment: Self.stop(anchor.y))
    }

    /// The box a `draw(_:at:anchor:)` stands the words in, a million points
    /// on a side: far past any canvas, so it wraps nothing the words would
    /// keep whole and cuts nothing but what lies past the drawing.
    private static func room(at point: Point, anchor: UnitPoint) -> Rect {
        let reach = 1_000_000.0
        func edge(_ at: Double, _ aligned: TextAlignment) -> Double {
            switch aligned {
            case .start: return at
            case .center: return at - reach / 2
            case .end: return at - reach
            }
        }
        return Rect(
            x: edge(point.x, stop(anchor.x)), y: edge(point.y, stop(anchor.y)),
            width: reach, height: reach)
    }

    /// The nearer of the three stops a drawn box's alignment knows - 0 the
    /// near edge, a half the middle, 1 the far - clamped inside them.
    private static func stop(_ fraction: Double) -> TextAlignment {
        switch Int((min(max(fraction, 0), 1) * 2).rounded()) {
        case ..<1: return .start
        case 1: return .center
        default: return .end
        }
    }
}

extension Text {
    /// The words a canvas's `draw` writes of the text: a `+` or `.spans`
    /// one's runs joined where it is made of them (a run's own look is the
    /// text's now), else the words written on it, else the words the state a
    /// `Text(_ state:)` draws from holds now. A picture run writes nothing -
    /// a drawing has no image instruction.
    var drawnWords: String {
        if let runs = node.children.first(where: { $0.type == .spans }) {
            return runs.children.map(\.spanWords).joined()
        }
        if let words = node.props[TextElementContract.text.token]?.string { return words }
        if case .text(let words)? = node.driven[TextElementContract.text.token]?.current?() {
            return words
        }
        return ""
    }

    /// The instructions the text's own look draws ahead of its words - its
    /// colour, then its size - none where it wears the pen's.
    var drawnLook: [DrawCommand] {
        var look: [DrawCommand] = []
        if let color = node.props[TextStyleElementContract.foregroundStyle.token]
            .flatMap(Color.init(propValue:)) {
            look.append(Draw.foregroundStyle(color))
        }
        if let size = node.props[FontElementContract.fontSize.token]?.number {
            look.append(Draw.fontSize(size))
        }
        return look
    }
}

extension Node {
    /// The words one run of a drawn text carries - its own, or its run
    /// children's joined where a `ForEach` or a branch stands for them, each
    /// producing its children when first asked.
    fileprivate var spanWords: String {
        var node = self
        node.materialize()
        if let words = node.props[TextElementContract.text.token]?.string { return words }
        return node.children.map(\.spanWords).joined()
    }
}
