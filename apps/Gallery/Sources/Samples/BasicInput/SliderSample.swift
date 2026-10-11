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
            DebugInfoLabel()

            Text(soundOn ? "Volume: \\(Int(volume))" : "Muted")

            Slider($volume, in: 0...100)
                .disabled(!soundOn)
                .onDragStarted { dragging = true }
                .onDragCompleted { dragging = false }

            Text(dragging ? "Dragging..." : "At rest")

            HStack {
                Text("Sound")
                    .verticalAlignment(.center)

                Toggle(isOn: $soundOn)
            }
        }
        """

    var body: some View {
        VStack {
            DebugInfoLabel()

            Text(soundOn ? "Volume: \(Int(volume))" : "Muted")
                .font(.system(size: 17))
                .multilineTextAlignment(.center)

            Slider($volume, in: 0...100)
                .accessibilityIdentifier("slider.volume")
                .accessibilityLabel("Volume")
                .disabled(!soundOn)
                .tint(Palette.accent)
                .onDragStarted { dragging = true }
                .onDragCompleted { dragging = false }

            Text(dragging ? "Dragging..." : "At rest")
                .font(.system(size: 13))
                .multilineTextAlignment(.center)

            HStack {
                Text("Sound")
                    .font(.system(size: 14))
                    .verticalAlignment(.center)

                Toggle(isOn: $soundOn)
                    .accessibilityIdentifier("slider.sound")
                    .accessibilityLabel("Sound on")
                    .tint(Palette.accent)
            }
            .spacing(12)
            .horizontalAlignment(.center)
        }
        .spacing(12)
    }

    var notes: (any View)? {
        VStack {
            Text("The drag's two ends are events of their own - `.onDragStarted` as the "
                + "thumb is grabbed, `.onDragCompleted` as it is let go - and every step "
                + "between them is an `.onValueChanged`. Work too heavy for every step "
                + "belongs in the completed end.")
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
