import SwiftOmniUI

/// A canvas drawn from state, and one drawn through a GraphicsContext.
struct CanvasSample: SampleContent {
    static let id = "canvas"
    static let title = "Canvas"
    static let summary = "A canvas: the drawing instructions travel, and the host draws them."

    // A drag is a gesture, and a scroller would claim it before the canvas
    // heard about it - see SampleContent.scrolls.
    static let scrolls = false

    var examples: [Example] {
        [
            Example(FollowsState()),
            Example(WrittenWithContext()), Example(Measured()),
        ]
    }
}

/// A drawing described from state, redrawn because the state changed and for
/// no other reason.
private struct FollowsState: ExampleContent {
    @State private var bars = [0.4, 0.75, 0.3, 0.95, 0.6]

    static let code = """
        struct FollowsState: View {
            @State private var bars = [0.4, 0.75, 0.3, 0.95, 0.6]

            var body: some View {
                VStack {
                    // The bars are read by the drawing below, so changing
                    // one builds this closure - which is what redraws it.

                    Canvas {
                        for (index, value) in bars.enumerated() {
                            let height = value * 90
                            let x = Double(index) * 44

                            Draw.fillColor(Palette.accent)
                            Draw.fillRoundedRectangle(
                                x: x, y: 100 - height, width: 32, height: height,
                                cornerRadius: 4)

                            Draw.foregroundStyle(Palette.text)
                            Draw.fontSize(11)
                            Draw.drawText(
                                "\\(Int(value * 100))", x: x, y: 104, width: 32, height: 14,
                                horizontalAlignment: .center)
                        }
                    }
                    .frame(height: 120)

                    Button("Different numbers", action: { bars = bars.map { _ in Double.random(in: 0.15...1) } })
                        
                }
            }
        }
        """

    var body: some View {
        VStack {

            Canvas {
                for (index, value) in bars.enumerated() {
                    let height = value * 90
                    let x = Double(index) * 44

                    Draw.fillColor(Palette.accent)
                    Draw.fillRoundedRectangle(
                        x: x, y: 100 - height, width: 32, height: height, cornerRadius: 4)

                    Draw.foregroundStyle(Palette.text)
                    Draw.fontSize(11)
                    Draw.drawText(
                        "\(Int(value * 100))", x: x, y: 104, width: 32, height: 14,
                        horizontalAlignment: .center)
                }
            }
            .frame(height: 120)

            Button("Different numbers", action: { bars = bars.map { _ in Double.random(in: 0.15...1) } })
                .font(.system(size: 13))
                .padding(EdgeInsets(16, 6))
                
        }
        .spacing(12)
    }

    var notes: (any View)? {
        Text("The drawing is a list of instructions described in Swift. They travel to "
            + "the host, which draws them on the platform's canvas. The bars are read "
            + "inside the drawing, so new numbers draw it again.")
            .font(.system(size: 12))
            .foregroundStyle(Palette.subtle)
    }
}

/// The same canvas, drawn through a GraphicsContext with paths and text.
private struct WrittenWithContext: ExampleContent {
    static let code = """
        var body: some View {
            Canvas { context, size in
                let middle = Point(x: size.width / 2, y: 52)

                // fill and stroke take a Path, in a Shading's colour.
                context.fill(
                    Path(ellipseIn: Rect(middle.x - 90, 32, 180, 40)),
                    with: .color(Palette.accent))

                context.stroke(
                    Path(roundedRect: Rect(middle.x - 100, 24, 200, 56), cornerRadius: 10),
                    with: .color(Palette.outline), lineWidth: 1)

                // A Text goes in whole - its words, colour and size are the
                // drawing's for that call, and the anchor lands on the point.
                context.draw(Text("In context"), at: middle)
                context.draw(
                    Text("at the anchor"), at: Point(x: middle.x, y: 76),
                    anchor: .bottom)
            }
            .frame(height: 104)
        }
        """

    var body: some View {
        Canvas { context, size in
            let middle = Point(x: size.width / 2, y: 52)

            context.fill(
                Path(ellipseIn: Rect(middle.x - 90, 32, 180, 40)),
                with: .color(Palette.accent))

            context.stroke(
                Path(roundedRect: Rect(middle.x - 100, 24, 200, 56), cornerRadius: 10),
                with: .color(Palette.outline), lineWidth: 1)

            context.draw(Text("In context"), at: middle)
            context.draw(
                Text("at the anchor"), at: Point(x: middle.x, y: 76),
                anchor: .bottom)
        }
        .frame(height: 104)
    }

    var notes: (any View)? {
        Text("`Canvas(renderer:)` is the SwiftUI shape of the same canvas: a "
            + "`GraphicsContext` gathering `fill`, `stroke` and `draw` calls, "
            + "and the settled `size` beside it. The same instructions travel "
            + "either way - `Draw.` calls and `context` calls write one list.")
            .font(.system(size: 12))
            .foregroundStyle(Palette.subtle)
    }
}

/// An aim's `measureText` asks the host's own text engine the room words
/// will take - the answer fits the box to them.
private struct Measured: ExampleContent {
    @Aim(Canvas.self) private var ruler
    @State private var fitted: Size?
    @State private var failed: String?

    static let code = """
        @Aim(Canvas.self) private var ruler
        @State private var fitted: Size?

        var body: some View {
            VStack {
                Canvas {
                    Draw.foregroundStyle(Palette.text)
                    // The box a drawText cuts at: taller than a line, so a
                    // descender - a g's tail - is not cut off it.
                    Draw.drawText(
                        "Snug", x: 0, y: 40, width: 320, height: 24,
                        horizontalAlignment: .center)

                    if let fitted {
                        Draw.strokeColor(Palette.accent)
                        Draw.drawRoundedRectangle(
                            x: 160 - fitted.width / 2 - 8, y: 52 - fitted.height / 2 - 6,
                            width: fitted.width + 16, height: fitted.height + 12,
                            cornerRadius: 6)
                    }
                }
                // The aim goes on the canvas itself, ahead of the frame:
                // aimed at a wrapper the act would find no canvas.
                .aim(ruler)
                .frame(height: 104)
                .task {
                    // measureText is an act aimed at the canvas: async, and
                    // answered by the host's own text engine.
                    fitted = try? await ruler.measureText("Snug")
                }

                Text(fitted.map {
                    "measured \\(Int($0.width)) x \\(Int($0.height))" }
                    ?? "measuring...")
            }
        }
        """

    var body: some View {
        VStack {

            Canvas {
                Draw.foregroundStyle(Palette.text)
                // The box a drawText cuts at: taller than a line, so a
                // descender - a g's tail - is not cut off it.
                Draw.drawText(
                    "Snug", x: 0, y: 40, width: 320, height: 24,
                    horizontalAlignment: .center)

                if let fitted {
                    Draw.strokeColor(Palette.accent)
                    Draw.strokeWidth(1)
                    Draw.drawRoundedRectangle(
                        x: 160 - fitted.width / 2 - 8, y: 52 - fitted.height / 2 - 6,
                        width: fitted.width + 16, height: fitted.height + 12,
                        cornerRadius: 6)
                }
            }
            .aim(ruler)
            .frame(height: 104)
            .task {
                do {
                    fitted = try await ruler.measureText("Snug")
                } catch {
                    failed = String(describing: error)
                }
            }

            Text(failed ?? fitted.map { "measured \(Int($0.width)) x \(Int($0.height))" }
                ?? "measuring...")
                .font(.system(size: 13))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(12)
    }

    var notes: (any View)? {
        Text("`measureText` is an act aimed at the canvas with `@Aim`: async, "
            + "and answered by the host's own text engine - the same one that "
            + "draws a `Text` - which is why the box fits. `maximumWidth` wraps "
            + "the words as a text in that much room does.")
            .font(.system(size: 12))
            .foregroundStyle(Palette.subtle)
    }
}
