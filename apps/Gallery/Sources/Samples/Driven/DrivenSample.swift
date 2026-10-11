import SwiftOmniUI

/// A value both sides hold, moved by the host and read by arithmetic that
/// describes nothing.
struct DrivenSample: SampleContent, ExampleContent {
    /// Which law the buttons send the marker under - ORDINARY state, read
    /// below so the caption can name it, which is what puts this page's build
    /// count next to a value that moves for nothing.
    @State private var slowly = false

    /// Where the marker sits - the value the HOST carries.
    @State private var offset = 0.0

    /// The rail's colour, which the HOST carries with no engine at all.
    @State private var tint = Palette.outline

    static let id = "driven"
    static let title = "A value the host moves"
    static let summary = "A value the host moves, and arithmetic that follows it every frame."

    /// How far the marker may travel - the rail's width less its own.
    private static let run = 240.0

    static let code = """
        @State private var offset = 0.0
        @State private var tint = Palette.outline

        @State private var slowly = false

        VStack {
            // The marker and the percentage cost no build at all; the
            // caption below reads `slowly`, so the switch is the only thing
            // that moves this reading - and it names it.
            DebugInfoLabel()

            let law = slowly ? "1600 ms, cubicInOut" : "350 ms, cubicOut"

            Grid {
                ColorPicker()
                    .color($tint)
                    .frame(height: 6)
                    .verticalAlignment(.center)

                ColorPicker()
                    .color(Palette.brand)
                    .frame(width: 20)
                    .frame(height: 20)
                    .horizontalAlignment(.start)
                    .offset(x: $offset)
            }
            .frame(width: 260)
            .frame(height: 28)

            // A CONVERSION of the same driven value: the host works the words
            // out on its own frames, from where the marker HAS GOT TO, and
            // nothing here reads anything.
            Text($offset.journey.convert { "\\(Int(($0.value / 240 * 100).rounded()))%" })

            // Off state: written twice a page, and described both times.
            Text(law)

            HStack {
                Button("Empty", action: { go(to: 0) })
                Button("Half", action: { go(to: 0.5) })
                Button("Full", action: { go(to: 1) })
            }

            SwitchRow("Take the long way", $slowly)
        }
        /// One place to be sent to, under whichever law the switch asks for.
        private func go(to place: Double) {
            let law: Animation = slowly ? .easeInOut(duration: 1.6) : .easeOut(duration: 0.35)

            $offset.journey.animation = law
            offset = 240 * place

            $tint.journey.animation = law
            tint = place > 0 ? Palette.accent : Palette.outline
        }
        """

    var body: some View {
        VStack {
            // WHAT THIS PAGE IS ABOUT, and it takes both halves to say it: the
            // marker crosses and the percentage counts up for no build at all,
            // while the caption below is described from `slowly` - so the only
            // thing that moves this reading is the switch, which it names.
            DebugInfoLabel()

            let law = slowly ? "1600 ms, cubicInOut" : "350 ms, cubicOut"

            ZStack {
                Grid {
                    ColorPicker()
                        .color($tint)
                        .frame(height: 6)
                        .cornerRadius(3)
                        .verticalAlignment(.center)

                    ColorPicker()
                        .color(Palette.brand)
                        .frame(width: 20)
                        .frame(height: 20)
                        .cornerRadius(10)
                        .horizontalAlignment(.start)
                        .verticalAlignment(.center)
                        .offset(x: $offset)
                }
                .frame(width: 260)
                .frame(height: 28)
            }
            .style("Card")
            .padding(16)
            .background(Palette.surface)
            .stroke(.transparent)
            .shape(.roundedRectangle(12))
            .horizontalAlignment(.center)

            Text()
                .text($offset.journey.convert { "\(Int(($0.value / Self.run * 100).rounded()))%" })
                .font(.system(size: 28))
                .bold()
                .horizontalAlignment(.center)

            Text("Sent under \(law)")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
                .horizontalAlignment(.center)

            HStack {
                button("Empty") { go(to: 0) }
                button("Half") { go(to: 0.5) }
                button("Full") { go(to: 1) }
            }
            .spacing(8)
            .horizontalAlignment(.center)

            SwitchRow("Take the long way", $slowly)
        }
        .spacing(12)
    }

    var notes: (any View)? {
        VStack {
            Text("The reading at the top says how many times this closure has been "
                + "described and which value for. Press the buttons and watch the marker "
                + "cross, the colour change and the percentage count up: the count does "
                + "not move. Throw the switch, which changes one caption, and it goes up "
                + "by one and says `for slowly`. The percentage is written off a driven "
                + "value by a conversion; the caption under it is described from "
                + "`slowly`, which is ordinary `@State`.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("A value the host holds is worn by a property the way a plain value is: "
                + "`.offset(x: $offset)`, `.color($tint)`. Send it somewhere from a "
                + "handler - `offset = 240`, under `$offset.journey.animation` - and the host "
                + "walks the property there on the display's own frames, which the tree "
                + "does not have. A journey is part of every `@State` the host can walk, "
                + "so both values here are ordinary `@State`; nothing reads either in a "
                + "body, and the run costs no render at all.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("`$offset.journey` holds three things at once: `offset` itself is where "
                + "the value is going, `$offset.journey.value` where it is, and "
                + "`$offset.journey.velocity` how fast. Writing the state asks the host for "
                + "a journey; writing `$offset.journey.value` puts it there at once, which "
                + "is what arithmetic worked out per frame does. `$offset.journey.convert "
                + "{ … }` writes the percentage from where the marker has got to, and a "
                + "converted text is written only when its letters change, so a reading "
                + "that rounds to the same number costs nothing.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("A conversion rewrites one value as another; an engine is for arithmetic "
                + "that keeps state of its own between frames, which Engine shows. The "
                + "marker moves rather than resizing: a translation is a drawing field and "
                + "costs nothing, while a width written per frame measures the layout again "
                + "every time. Wherever a value moves quickly, reach for the transform.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(12)
    }

    /// One place to be sent to, under whichever law the switch asks for.
    private func go(to place: Double) {
        let law: Animation = slowly ? .easeInOut(duration: 1.6) : .easeOut(duration: 0.35)

        $offset.journey.animation = law
        offset = Self.run * place

        $tint.journey.animation = law
        tint = place > 0 ? Palette.accent : Palette.outline
    }

    /// One of the buttons, all of which look the same.
    private func button(_ caption: String, _ act: @escaping EventHandler) -> Button {
        Button(caption, action: act)
            .font(.system(size: 13))
            .padding(EdgeInsets(14, 6))
            
    }
}
