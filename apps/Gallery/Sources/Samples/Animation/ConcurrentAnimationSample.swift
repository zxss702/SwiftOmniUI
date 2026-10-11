import SwiftOmniUI

/// Several movements in the air at once: each `.animation(_:value:)` rides its
/// own state, so they overlap rather than queue.
struct ConcurrentAnimationSample: SampleContent, ExampleContent {
    @State private var playing = false

    /// One state per bar: where it stands on the stage.
    @State private var hop0 = 0.0
    @State private var hop1 = 0.0
    @State private var hop2 = 0.0
    @State private var hop3 = 0.0

    /// What the stage is washing to.
    @State private var wash = Palette.accent

    /// How opaque the caption is.
    @State private var breath = 1.0

    /// The four bars, in order - one place to write the list, read by both the
    /// view and the beat.
    private var bars: [Binding<Double>] { [$hop0, $hop1, $hop2, $hop3] }

    static let id = "concurrentAnimation"
    static let title = "At the same time"
    static let summary = "Movements of different lengths, overlapping rather than queueing."

    static let code = """
        @State private var playing = false

        @State private var hop0 = 0.0
        @State private var hop1 = 0.0
        @State private var hop2 = 0.0
        @State private var hop3 = 0.0

        @State private var wash = Palette.accent
        @State private var breath = 1.0

        private var bars: [Binding<Double>] { [$hop0, $hop1, $hop2, $hop3] }

        VStack {
            ZStack {
                VStack {
                    HStack {
                        ForEach(Array(bars.enumerated()), id: \\.offset) { bar in
                            ColorPicker(Palette.onAccent)
                                .offset(y: bar.element.wrappedValue)
                                // Each bar's movement is its own, gated on its
                                // own value.
                                .animation(.easeInOut(duration: 0.15), value: bar.element.wrappedValue)
                                .frame(width: 14)
                                .frame(height: 46)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                    }
                    .frame(height: 92)

                    Text("in concert")
                        .opacity(breath)
                        .animation(.easeInOut(duration: 0.6), value: breath)
                }
            }
            .background(wash)
            .animation(.easeInOut(duration: 1.2), value: wash)

            HStack {
                Button("Play") {
                    playing = true
                    Task { await run() }
                }
                .disabled(playing)

                Button("Stop") {
                    playing = false
                    hop0 = 0; hop1 = 0; hop2 = 0; hop3 = 0
                    wash = Palette.accent
                    breath = 1
                }
                .disabled(!playing)
            }
        }
        .onDisappear { playing = false }
        """

    var body: some View {
        VStack {
            ZStack {
                VStack {
                    HStack {
                        ForEach(Array(bars.enumerated()), id: \.offset) { bar in
                            ColorPicker(Palette.onAccent)
                                .offset(y: bar.element.wrappedValue)
                                // Each bar's movement is its own, gated on its
                                // own value - so all four overlap rather than
                                // queue.
                                .animation(.easeInOut(duration: 0.15), value: bar.element.wrappedValue)
                                .frame(width: 14)
                                .frame(height: 46)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                    }
                    .spacing(10)
                    .frame(height: 92)

                    Text("in concert")
                        .opacity(breath)
                        .animation(.easeInOut(duration: 0.6), value: breath)
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.onAccent)
                        .multilineTextAlignment(.center)
                }
                .spacing(4)
                .padding(16)
            }
            .style("Card")
            .background(wash)
            .animation(.easeInOut(duration: 1.2), value: wash)
            .stroke(.transparent)
            .shape(.roundedRectangle(12))

            HStack {
                button("Play") {
                    guard !playing else { return }
                    playing = true
                    Task { await run() }
                }
                .disabled(playing)

                button("Stop") {
                    playing = false
                    hop0 = 0
                    hop1 = 0
                    hop2 = 0
                    hop3 = 0
                    wash = Palette.accent
                    breath = 1
                }
                .disabled(!playing)
            }
            .spacing(8)
        }
        .spacing(12)
        .onDisappear {
            playing = false
        }
    }

    var notes: (any View)? {
        VStack {
            Text("One press, and three things move at once for as long as it runs: "
                + "the wash across the stage, the caption breathing, and the bars "
                + "hopping one after another inside both. Each `.animation(_:value:)` "
                + "rides the state it is gated on - writes to it are what move it - "
                + "so the three movements are in the air together rather than queued.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("The four bars are FOUR states, one each, so that a write to one "
                + "moves one bar and leaves the rest where they stand.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(12)
    }

    /// Writes the states until Stop is pressed: the animations on each are what
    /// carry the movement between writes.
    private func run() async {
        var n = 0

        while playing {
            wash = n.isMultiple(of: 2) ? Palette.brand : Palette.accent
            breath = 0.25

            for bar in bars {
                guard playing else { return }
                bar.wrappedValue = -26
                try? await Task.sleep(for: .milliseconds(150))
                bar.wrappedValue = 0
                try? await Task.sleep(for: .milliseconds(150))
            }

            breath = 1
            try? await Task.sleep(for: .milliseconds(300))
            n += 1
        }
    }

    /// One of the buttons, both of which look the same.
    private func button(_ caption: String, _ act: @escaping EventHandler) -> Button {
        Button(caption, action: act)
            .font(.system(size: 13))
            .padding(EdgeInsets(14, 6))
    }
}
