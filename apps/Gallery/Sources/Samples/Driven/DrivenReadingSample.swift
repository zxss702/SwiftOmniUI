import SwiftOmniUI

/// Where a value is GOING and where it HAS GOT TO are two readings, and a
/// walked state holds both: the state itself is the destination from the first
/// millisecond, and its journey's `value` is what is on the screen this frame.
struct DrivenReadingSample: SampleContent, ExampleContent {
    /// The bar's width, driven - so both readings live here and neither costs
    /// a render.
    @State private var width = 60.0


    static let id = "driven-reading"
    static let title = "Reading a driven state"
    static let summary = "One state holds where the value is going and where it has got to."

    static let code = """
        @State private var width = 60.0

        VStack {
            // NOTHING in this closure reads: the bar is a channel and both
            // readings are CONVERSIONS of it, worked out by the host on its own
            // frames. So this stays at one build while the numbers move sixty
            // times a second.
            DebugInfoLabel()

            // The bar: one driven property, and the host moves it.
            ZStack { }
            .style("Card")
                .frame(width: $width)
                .frame(height: 28)

            // The two readings, off ONE journey: `destination` is where the
            // value is going and `value` where it has got to.
            Text($width.journey.convert {
                "going to \\(Int($0.destination)) — showing \\(Int($0.value))"
            })

            // The SAME arithmetic drawn: the distance between where the value
            // is going and where it is - widest the moment a button is
            // pressed, and nought when the bar arrives.
            ZStack { }
            .style("Card")
                .frame(width: $width.journey.convert { abs($0.destination - $0.value) })
                .frame(height: 10)

            HStack {
                Button("Grow", action: {
                    try await $width.journey.move(to: 300, .easeOut(duration: 1.6))
                })

                Button("Shrink", action: {
                    try await $width.journey.move(to: 60, .easeIn(duration: 1.6))
                })

                // Stopping leaves the value where it stands, and the
                // destination is mirrored onto it - so both readings agree again.
                Button("Stop", action: { width = $width.journey.value })
            }
        }

        """

    var body: some View {
        VStack {
            DebugInfoLabel()

            ZStack {
                Text("")
            }
            .style("Card")
            .frame(width: $width)
            .frame(height: 28)
            .background(.solidColor(Palette.accent))
            .shape(.roundedRectangle(8))
            .strokeWidth(0)
            .horizontalAlignment(.start)

            Text()
                .text($width.journey.convert {
                    "going to \(Int($0.destination)) — showing \(Int($0.value))"
                })
                .font(.system(size: 17))

            Text("how far apart the two readings are")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            // The SAME arithmetic drawn: the distance between where the value
            // is going and where it is. It is widest the moment a button is
            // pressed and nought when the bar arrives.
            ZStack {
                Text("")
            }
            .style("Card")
            .frame(width: $width.journey.convert { abs($0.destination - $0.value) })
            .frame(height: 10)
            .background(.solidColor(Palette.subtle))
            .shape(.roundedRectangle(5))
            .strokeWidth(0)
            .horizontalAlignment(.start)

            HStack {
                Button("Grow", action: {
                        try await $width.journey.move(to: 300, .easeOut(duration: 1.6))
                    })
                    .background(Palette.accent)
                    .shape(.roundedRectangle(8))
                    .padding(EdgeInsets(16, 8))
                    

                Button("Shrink", action: {
                        try await $width.journey.move(to: 60, .easeIn(duration: 1.6))
                    })
                    .background(Palette.accent)
                    .shape(.roundedRectangle(8))
                    .padding(EdgeInsets(16, 8))
                    

                Button("Stop", action: { width = $width.journey.value })
                    .stroke(Palette.outline)
                    .strokeWidth(1)
                    .background(.transparent)
                    .foregroundStyle(Palette.subtle)
                    .shape(.roundedRectangle(8))
                    .padding(EdgeInsets(16, 8))
                    
            }
            .spacing(10)
        }
        .spacing(12)
    }

    var notes: (any View)? {
        VStack {
            Text("One state, two readings. `width` is 300 the instant Grow is "
                + "pressed; `$width.journey.value` is what the bar is actually showing this "
                + "frame. The grey bar under the caption is the distance between them, "
                + "widest at the start and nought on arrival.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("Both numbers, and the grey bar's width, are CONVERSIONS of the one "
                + "state: `$width.journey.convert { … }` reads `destination` and `value` off it "
                + "and the host works the answer out on its own frames. Nothing on this "
                + "page reads `width` in a body, so a 1600ms journey costs no renders at "
                + "all: a body printing `width` would be built once per press, and one "
                + "printing `$width.journey.value` once per frame.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("Stop leaves the value where it stands and brings the destination to "
                + "meet it, so the two readings agree again and the grey bar closes. "
                + "Press Grow and then Stop half way: the caption's first number "
                + "becomes the second.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("There is no cadence to choose. A conversion is worked out once a "
                + "frame, and what it answers is another driven state - so asking for "
                + "a reading sixty times a second costs what asking for one twice a "
                + "second would.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(12)
    }
}
