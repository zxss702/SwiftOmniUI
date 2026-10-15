// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// `Canvas`'s own properties, shared by the control and its `Style<Canvas>`.
@preconcurrency @MainActor public protocol CanvasProperties: PropertyContainer {}

extension CanvasProperties {
    /// What to draw, written as the canvas calls that make the drawing.
    ///
    ///     .drawable {
    ///         Draw.strokeColor(.firebrick)
    ///         Draw.strokeWidth(2)
    ///         Draw.drawLine(x1: 0, y1: 0, x2: 120, y2: 0)
    ///     }
    ///
    /// Usually given in the initializer instead; this is how a `Style<Canvas>`
    /// states one.
    @_spi(Host) public func drawable(@DrawingBuilder _ drawing: () -> [DrawCommand]) -> Modified {
        setValue(CanvasContract.drawable, drawing())
    }
}

/// A canvas to draw on, one instruction at a time.
///
///     Canvas {
///         Draw.fillColor(.cornflowerBlue)
///         Draw.fillRoundedRectangle(x: 0, y: 0, width: 160, height: 48, cornerRadius: 8)
///
///         Draw.foregroundStyle(.white)
///         Draw.fontSize(15)
///         Draw.drawText(
///             "Drawn, not built",
///             x: 0, y: 0, width: 160, height: 48,
///             horizontalAlignment: .center, verticalAlignment: .center)
///     }
///     .frame(height: 48)
///
/// The drawing travels as data - the canvas calls `Draw` offers, in order -
/// and the host replays them on the platform's own canvas. A drawing that
/// reads a state is drawn again when the state changes.
public struct Canvas: VisualElement, CanvasProperties{
    /// The node this control describes.
    public var node: Node

    /// An empty canvas - what a `Style<Canvas>` is written against.
    public init() {
        node = Node(shape: CanvasContract.self)
    }

    /// A canvas showing what the closure draws.
    public init(@DrawingBuilder _ drawing: () -> [DrawCommand]) {
        node = Node(shape: CanvasContract.self)
        node.write(CanvasContract.drawable, drawing())
    }

    /// A canvas drawn from the space it is given, the way SwiftUI's closure
    /// form draws it:
    ///
    ///     Canvas { context, size in
    ///         context.fill(
    ///             Path(roundedRect: Rect(0, 0, size.width, 40), cornerRadius: 8),
    ///             with: .color(.cornflowerBlue))
    ///     }
    ///
    /// The calls on `context` gather into the canvas's drawing, and `size` is
    /// the room its layout gave it. The host asks the core for the drawing
    /// when that room is allocated, so the first drawing belongs to the
    /// canvas's first native frame.
    public init(renderer: @escaping (inout GraphicsContext, Size) -> Void) {
        node = Node(shape: CanvasContract.self)
        node.canvas = CanvasBox(renderer: renderer)
    }

    /// A finger went down, or a mouse button was pressed.
    ///
    /// The point is in the canvas's own coordinates - the same ones the drawing
    /// instructions use, so what arrives can be drawn where it happened.
    @_spi(Host) public func onPressed(_ handler: @escaping ValueEventHandler<Point>) -> Self {
        onEvent(CanvasContract.pressed, handler)
    }

    /// It moved while still down, with where it is now - the canvas's own
    /// coordinates again.
    @_spi(Host) public func onDragged(_ handler: @escaping ValueEventHandler<Point>) -> Self {
        onEvent(CanvasContract.dragged, handler)
    }

    /// It was lifted, with where it left off.
    @_spi(Host) public func onReleased(_ handler: @escaping ValueEventHandler<Point>) -> Self {
        onEvent(CanvasContract.released, handler)
    }
}

/// The renderer stays on the core side of the host boundary. Its current
/// drawing and the states it read belong to the mounted canvas's identity;
/// neither the closure nor its state crosses the host wire.
final class CanvasBox {
    let renderer: (inout GraphicsContext, Size) -> Void
    weak var owner: RenderedNode?
    private(set) var size: Size?
    private(set) var commands: [DrawCommand]?

    init(renderer: @escaping (inout GraphicsContext, Size) -> Void) {
        self.renderer = renderer
    }

    func inheritSize(from previous: CanvasBox?) {
        size = previous?.size
    }

    /// `nil` reads mean the cached drawing was reused, so the owner's read
    /// index must stay as it was. A zero allocation has no visible commands.
    func drawing(at proposed: Size, force: Bool = false) -> (commands: [DrawCommand], reads: Set<ObjectIdentifier>?) {
        guard proposed.width.isFinite, proposed.height.isFinite else {
            return (commands ?? [], nil)
        }
        let size = Size(max(0, proposed.width), max(0, proposed.height))
        if !force, self.size == size, let commands { return (commands, nil) }
        self.size = size
        guard size.width > 0, size.height > 0 else {
            commands = []
            return ([], [])
        }
        let (drawn, reads) = ReadScope.observed {
            var context = GraphicsContext()
            renderer(&context, size)
            // Native drawing records cannot carry a themed colour. Resolve it
            // while the renderer's reads are observed, so a colour-scheme
            // change invalidates this canvas just like any other state read.
            return context.commands.map { command in
                DrawCommand(command.kind, command.arguments.map {
                    $0.isThemed ? $0.resolvingColorScheme() : $0
                })
            }
        }
        commands = drawn
        return (drawn, reads)
    }
}

extension Aim where Target == Canvas {
    /// The room `text` takes drawn in `font`, asked of the host's own text
    /// engine - the same one that draws a `Text`. `maximumWidth` wraps the
    /// words as a `Text` in that much room does; nil measures each paragraph
    /// one line, the answer the intrinsic width and one line's height a
    /// paragraph.
    ///
    ///     @Aim(Canvas.self) private var surface
    ///
    ///     Canvas { ... }.aim(surface)
    ///
    ///     let size = try await surface.measureText("Hello", font: .system(size: 13))
    ///
    /// - Returns: The width and height, in the canvas's coordinates.
    /// - Throws: `SwiftOmniUIError` when the aim is on no canvas or on two, or
    ///   the host does not measure text.
    public nonisolated(nonsending) func measureText(
        _ text: String, font: Font = .default, maximumWidth: Double? = nil
    ) async throws -> Size {
        let textStyle: FontTextStyle?
        let size: Double?
        let family: Name?
        switch font.basis {
        case .textStyle(let style):
            (textStyle, size, family) = (style, nil, nil)
        case .system(let points):
            (textStyle, size, family) = (nil, points, nil)
        case .custom(let name, let points):
            (textStyle, size, family) = (nil, points, Name(name))
        }
        return try await call(
            CanvasContract.measureText,
            text, textStyle, size, family, font.weight, font.design, font.attributes, maximumWidth)
    }
}
