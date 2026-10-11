import SwiftOmniUI

/// The public animation vocabulary: `withAnimation` around a state write, and
/// `.animation(_:value:)` on the view the change lands on.
struct AnimationSample: SampleContent, ExampleContent {
    @State private var curve = 0

    /// The four values the card is drawn from, one per thing a button moves.
    /// Each is DESCRIBED - a write asks for a build, and the build's patch
    /// carries the animation the write ran under to the host.
    @State private var fade = 1.0
    @State private var shift = 0.0
    @State private var scale = 1.0
    @State private var angle = 0.0

    static let id = "animation"
    static let title = "Animations"
    static let summary = "Fade, move, scale and spin a view - a state write inside withAnimation."

    static let curves = ["Linear", "Ease in-out", "Bouncy", "Spring"]

    static let code = """
        @State private var curve = 0

        @State private var fade = 1.0
        @State private var shift = 0.0
        @State private var scale = 1.0
        @State private var angle = 0.0

        static let curves = ["Linear", "Ease in-out", "Bouncy", "Spring"]

        VStack {
            ZStack {
                Text("Animate me")
            }
            .opacity(fade)
            .offset(x: shift)
            .scaleEffect(scale)
            .rotationEffect(.degrees(angle))

            Picker("Animation", selection: $curve) {
                ForEach(Self.curves.indices) { Text(Self.curves[$0]).tag($0) }
            }

            HStack {
                // withAnimation names the curve the writes in its body run
                // under; each change travels to its new value by it.
                // A write goes TO a value: each button toggles its value
                // between where it rests and where it travels, so every
                // press is a visible change in one direction.
                Button("Fade", action: {
                    withAnimation(animation) { fade = fade < 0.5 ? 1 : 0.1 }
                })

                Button("Move", action: {
                    withAnimation(animation) { shift = shift == 0 ? 60 : 0 }
                })

                Button("Scale", action: {
                    withAnimation(animation) { scale = scale == 1 ? 1.4 : 1 }
                })

                // A full turn is the author's arithmetic - add 360 to where
                // the angle stands.
                Button("Spin", action: {
                    withAnimation(.snappy) { angle += 360 }
                })
            }

            // Applied at once - `nil` says the write animates under nothing.
            Button("Reset", action: {
                withAnimation(nil) {
                    fade = 1
                    shift = 0
                    scale = 1
                    angle = 0
                }
            })
        }

        /// The animation the picker is on.
        private var animation: Animation {
            switch curve {
            case 1: return .easeInOut(duration: 0.4)
            case 2: return .bouncy(duration: 0.4)
            case 3: return .spring(response: 0.4, dampingFraction: 0.6)
            default: return .linear(duration: 0.4)
            }
        }
        """

    var body: some View {
        VStack {
            ZStack {
                Text("Animate me")
                    .font(.system(size: 17))
                    .foregroundStyle(Palette.onBrand)
                    .padding(EdgeInsets(24, 16))
            }
            .style("Card")
            .opacity(fade)
            .offset(x: shift)
            .scaleEffect(scale)
            .rotationEffect(.degrees(angle))
            .background(Palette.brand)
            .stroke(Palette.accent)
            .shape(.roundedRectangle(32))

            Picker("Animation", selection: $curve) {
                ForEach(Self.curves.indices) { Text(Self.curves[$0]).tag($0) }
            }
            .accessibilityIdentifier("animation.curve")
            .accessibilityLabel("Animation curve")

            HStack {
                button("Fade") {
                    withAnimation(animation) { fade = fade < 0.5 ? 1 : 0.1 }
                }

                button("Move") {
                    withAnimation(animation) { shift = shift == 0 ? 60 : 0 }
                }

                button("Scale") {
                    withAnimation(animation) { scale = scale == 1 ? 1.4 : 1 }
                }

                button("Spin") {
                    withAnimation(.snappy) { angle += 360 }
                }
            }
            .spacing(8)

            button("Reset") {
                withAnimation(nil) {
                    fade = 1
                    shift = 0
                    scale = 1
                    angle = 0
                }
            }
        }
        .spacing(12)
    }

    var notes: (any View)? {
        VStack {
            Text("Each button writes STATE inside `withAnimation`: the write "
                + "asks for a build, and the render that answers carries the "
                + "animation to the host, which moves the property by it. "
                + "Nothing names a journey - the change and its curve are one "
                + "write.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("`withAnimation(nil)` writes without a curve, so Reset lands "
                + "at once. `.animation(_:value:)` on a view is the other "
                + "half: it names the curve a change to THAT value arrives "
                + "under, with no `withAnimation` around the write.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("The journeys behind this - a state that can be moved, "
                + "awaited and read mid-flight - are the Driven samples and "
                + "Journey, which drive the property on the host's own frames "
                + "without a build at all.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(12)
    }

    /// One of the buttons, all of which look the same.
    private func button(_ caption: String, _ act: @escaping EventHandler) -> Button {
        Button(caption, action: act)
            .font(.system(size: 13))
            .padding(EdgeInsets(14, 6))
    }

    /// The animation the picker is on.
    private var animation: Animation {
        switch curve {
        case 1: return .easeInOut(duration: 0.4)
        case 2: return .bouncy(duration: 0.4)
        case 3: return .spring(response: 0.4, dampingFraction: 0.6)
        default: return .linear(duration: 0.4)
        }
    }
}
