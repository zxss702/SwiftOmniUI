import SwiftOmniUI

/// A native slider driven by one shared SwiftOmniUI journey.
struct SliderSample: SampleContent, ExampleContent {
    @State private var volume = 40.0
    @State private var soundOn = true
    @State private var dragging = false

    static let id = "slider"
    static let title = "Slider"
    static let summary = "A value dragged along a track, and a number that crosses the boundary intact."

    static let code = """
        @State private var volume = 40.0
        @State private var soundOn = true
        @State private var dragging = false

        VStack {
            // The volume is READ here, so EVERY report the thumb makes builds
            // this closure - which is what a get on a dragged value costs.

            Text(soundOn ? "Volume: \\(Int(volume))" : "Muted")

            Slider($volume, in: 0...100) { editing in
                dragging = editing
            }
            .disabled(!soundOn)

            Text(dragging ? "Dragging..." : "At rest")

            HStack {
                Text("Sound")

                Toggle(isOn: $soundOn)
            }
        }
        """

    var body: some View {
        VStack {

            Text(soundOn ? "Volume: \(Int(volume))" : "Muted")
                .font(.system(size: 17))
                .multilineTextAlignment(.center)

            Slider($volume, in: 0...100) { editing in
                    dragging = editing
                }
                .accessibilityIdentifier("slider.volume")
                .accessibilityLabel("Volume")
                .disabled(!soundOn)
                .tint(Palette.accent)

            Text(dragging ? "Dragging..." : "At rest")
                .font(.system(size: 13))
                .multilineTextAlignment(.center)

            HStack {
                Text("Sound")
                    .font(.system(size: 14))

                Toggle(isOn: $soundOn)
                    .accessibilityIdentifier("slider.sound")
                    .accessibilityLabel("Sound on")
                    .tint(Palette.accent)
            }
            .spacing(12)
        }
        .spacing(12)
    }

    var notes: (any View)? {
        VStack {
            Text("`onEditingChanged` reports the drag's two ends - `true` as the thumb is "
                + "grabbed, `false` as it is let go - and every step between them is a "
                + "write onto `$volume`. Work too heavy for every step belongs in the "
                + "let-go end.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("The value crosses the boundary as its own bits - nothing is formatted or "
                + "parsed on the way, so no locale can touch it.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(12)
    }
}
