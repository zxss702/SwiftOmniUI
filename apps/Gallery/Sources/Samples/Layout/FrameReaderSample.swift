import SwiftOmniUI

/// Content built from the space it was given, and frames reported on request.
struct FrameReaderSample: SampleContent, ExampleContent {
    @State private var slot = Rect(0, 0, 0, 0)
    @State private var window = Rect(0, 0, 0, 0)
    @State private var safe = Rect(0, 0, 0, 0)

    @State private var width = 220.0

    static let id = "frameReader"
    static let title = "Measuring a frame"
    static let summary = "GeometryReader builds from its measured frame; `.onGeometryChange` reports any view's."

    static let code = """
        @State private var width = 220.0
        @State private var slot = Rect(0, 0, 0, 0)
        @State private var window = Rect(0, 0, 0, 0)
        @State private var safe = Rect(0, 0, 0, 0)

        VStack {
            // `slot`, `window` and `safe` are read in these braces - the three
            // lines below print all of them - so every frame report builds
            // this closure, which is the whole cost of watching a frame.

            // THE PARENT, DRAWN in a gentle tint, because `slot` below is
            // measured against THIS box and the numbers say nothing until
            // there is something on the screen for them to be relative to.
            // It fills the page's width, so widening the panel walks its x
            // in towards the middle.
            VStack {
                Text("the parent")

                // The reader's content is built FROM the measurement, which
                // is the reader's own @State. The three handlers write the
                // page's states instead, and the lines below print them - so
                // a settled frame builds the reader AND the page's braces.
                GeometryReader { proxy in
                    Text("\\(Int(proxy.size.width)) × \\(Int(proxy.size.height))")
                }
                .frame(width: width)
                .frame(height: 120)
                // Reporting is a modifier on ANY view - one watch per value.
                // Nothing is measured unless something asks: a view without
                // a watch is not even subscribed.
                .onGeometryChange(for: Rect.self) { $0.frame(in: .parent) } action: { slot = $0 }
                .onGeometryChange(for: Rect.self) { $0.frame(in: .global) } action: { window = $0 }
                .onGeometryChange(for: Rect.self) { $0.frame(in: .safeArea) } action: { safe = $0 }
            }
            .padding(16)
            .background(Palette.selected)

            Slider($width, in: 140...340)

            // Where the panel sits, in three spaces: inside the tinted box
            // above, inside the window, and inside the safe area.
            Text("in its parent · \\(Int(slot.x)), \\(Int(slot.y))")
            Text("in the window · \\(Int(window.x)), \\(Int(window.y))")
            Text("in the safe area · \\(Int(safe.x)), \\(Int(safe.y))")

            Button("Animate the width", action: {
                // Nothing is described: the host carries the width and the
                // slider's thumb off the same state, and the frame reports
                // say where the panel actually got to.
                try await $width.journey.move(to: $width.journey.value < 240 ? 340 : 140)
            })
        }
        """

    var body: some View {
        VStack {
            // `slot`, `window` and `safe` are read in these braces - the three
            // lines below print all of them - so every frame report builds
            // this closure, which is the whole cost of watching a frame.

            // THE PARENT, DRAWN in a gentle tint, because `slot` below is
            // measured against THIS box and the numbers say nothing until
            // there is something on the screen for them to be relative to.
            // It fills the page's width, so widening the panel walks its x
            // in towards the middle.
            VStack {
                Text("the parent")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.brand)

                // The reader's content is built FROM the measurement, which
                // is the reader's own @State. The three handlers write the
                // page's states instead, and the three lines below print
                // them - so a settled frame builds the reader AND the page.
                GeometryReader { proxy in
                    Text("\(Int(proxy.size.width)) × \(Int(proxy.size.height))")
                        .font(.system(size: 22))
                        .bold()
                        .foregroundStyle(Palette.onAccent)
                }
                .frame(width: width)
                .frame(height: 120)
                .background(Palette.accent)
                // Reporting is a modifier on ANY view - one watch per value.
                // Nothing is measured unless something asks: a view without
                // a watch is not even subscribed.
                .onGeometryChange(for: Rect.self) { $0.frame(in: .parent) } action: { slot = $0 }
                .onGeometryChange(for: Rect.self) { $0.frame(in: .global) } action: { window = $0 }
                .onGeometryChange(for: Rect.self) { $0.frame(in: .safeArea) } action: { safe = $0 }
            }
            .spacing(8)
            .padding(16)
            .background(Palette.selected)

            Slider($width, in: 140...340)
                .accessibilityIdentifier("frameReader.width")
                .accessibilityLabel("Width")

            // Where the panel sits, in three spaces. The first is against the
            // tinted box above, which is why that box is drawn at all.
            Text("in its parent · \(Int(slot.x)), \(Int(slot.y))")
                .font(.system(size: 13))
                .foregroundStyle(Palette.brand)
                .multilineTextAlignment(.center)

            Text("in the window · \(Int(window.x)), \(Int(window.y))")
                .font(.system(size: 13))
                .multilineTextAlignment(.center)

            Text("in the safe area · \(Int(safe.x)), \(Int(safe.y))")
                .font(.system(size: 13))
                .multilineTextAlignment(.center)

            Button("Animate the width", action: {
                    // Nothing is described: the host carries the width and the
                    // slider's thumb off the same state, and the frame reports
                    // say where the panel actually got to.
                    try await $width.journey.move(to: $width.journey.value < 240 ? 340 : 140)
                })
                .padding(EdgeInsets(20, 10))
                
        }
        .spacing(12)
    }

    var notes: (any View)? {
        VStack {
            Text("The tinted box is the parent, drawn because the first reading is measured "
                + "against it: `in its parent` is where the panel sits inside that box. "
                + "Widening the panel walks its x in towards the middle, while the window "
                + "and safe-area readings move by the same amount from wherever the page is.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("A frame costs nothing until something asks for it: a view with no "
                + "`.onGeometryChange` is not even subscribed. A report comes when the "
                + "watched value settles somewhere new, so dragging the slider re-lays "
                + "the panel out and the button's walk reports every step of the way.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("The panel's width and the slider's thumb are one state - "
                + "`.frame(width: width)` and `Slider($width)` - so dragging the thumb "
                + "resizes the panel, and the button walks that same state.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("The reader builds its content from the frame it was given, and the "
                + "three watchers beside it write the page's own states, which the "
                + "lines under the panel print. So the page is a reader too, and the "
                + "count at the top moves for the frame reports and nothing else.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(8)
    }
}
