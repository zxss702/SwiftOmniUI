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
    /// the room its layout gave it: the closure runs again as the size
    /// settles, so what depends on it is drawn at the size it lands.
    public init(renderer: @escaping (inout GraphicsContext, Size) -> Void) {
        node = CanvasSizeReader(renderer: renderer).node
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

/// A drawing depends on its allocated size, not its position in a scrolling
/// window. Unlike business GeometryReader feedback, this passive measurement
/// neither rebuilds on every scroll nor prevents ancestor placement animations.
private struct CanvasSizeReader: View {
    @State private var size: Size? = nil
    let renderer: (inout GraphicsContext, Size) -> Void

    init(renderer: @escaping (inout GraphicsContext, Size) -> Void) {
        self.renderer = renderer
    }

    var body: some View {
        var container = Grid {
            if let size {
                canvas(for: size)
            }
        }
        container.node.props[.isGeometryReader] = true.propValue
        return container.flex(0)
            .hearing(ViewContract.drawingSizeChanged) { numbers in
                guard numbers.count == 2 else { return }
                let next = Size(numbers[0], numbers[1])
                guard next != self.size else { return }
                var transaction = Transaction()
                transaction.isGeometryFeedback = true
                withTransaction(transaction) { self.size = next }
            }
    }

    /// Runs the imperative renderer before handing its commands to the view
    /// builder, which only accepts view expressions.
    private func canvas(for size: Size) -> some View {
        var context = GraphicsContext()
        renderer(&context, size)
        return Canvas { context.commands }
            .frame(width: size.width, height: size.height)
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
