import SwiftOmniUI

/// Children drawn one over another, each in the whole room or in the area it
/// names, and which of them is on top.
struct ZStackSample: SampleContent {
    static let id = "zStack"
    static let title = "ZStack"
    static let summary = "Children drawn one over another, each in the whole room or in an area of its own."

    var examples: [Example] {
        [Example(Areas()), Example(Layers())]
    }
}

/// Two markers aligned in the whole room, and a panel in an area a switch
/// states in fractions or in device units.
private struct Areas: ExampleContent {
    @State private var proportional = true

    static let code = """
        @State private var proportional = true

        VStack {
            ZStack {
                // No area: the whole room, filled.
                ColorPicker(Palette.outline)

                // The panel fills the area it names: the right half of the
                // room, or 120 by 60 at 16, 16 whatever the room's size.
                ColorPicker(Color("#1E88E5"))
                    .area(proportional ? .proportional(0.5, 0, 0.5, 1) : .absolute(16, 16, 120, 60))

                // Its natural size, where its alignments put it.
                Marker(text: "start", color: "#E53935")
                    .horizontalAlignment(.start)
                    .verticalAlignment(.start)

                Marker(text: "end", color: "#00897B")
                    .horizontalAlignment(.end)
                    .verticalAlignment(.end)
            }
            .frame(height: 180)

            SwitchRow("Proportional area", $proportional)
        }

        private struct Marker: View {
            let text: String
            let color: String

            var body: some View {
                Text(text)
                    .foregroundStyle(.white)
                    .background(Color(color))
                    .padding(EdgeInsets(10, 6))
            }
        }
        """

    var body: some View {
        VStack {
            // NO BUILD READING HERE. `proportional` is read inside the stack's
            // own braces, and a container describes its children when the
            // differ asks, so the only closure this switch rebuilds is that one.
            ZStack {
                ColorPicker(Palette.outline)

                ColorPicker(Color("#1E88E5"))
                    .area(proportional ? .proportional(0.5, 0, 0.5, 1) : .absolute(16, 16, 120, 60))

                Marker(text: "start", color: "#E53935")
                    .horizontalAlignment(.start)
                    .verticalAlignment(.start)

                Marker(text: "end", color: "#00897B")
                    .horizontalAlignment(.end)
                    .verticalAlignment(.end)
            }
            .frame(height: 180)

            SwitchRow("Proportional area", $proportional)
                .horizontalAlignment(.center)
        }
        .spacing(12)
    }

    var notes: (any View)? {
        Text("Resize the window: a proportional area follows the room, an absolute one stays put.")
            .font(.system(size: 12))
            .foregroundStyle(Palette.subtle)
    }
}

/// Two boxes overlapping in the middle, and which is drawn on top.
private struct Layers: ExampleContent {
    @State private var redInFront = false

    static let code = """
        @State private var redInFront = false

        VStack {
            // Left alone, the child written last is drawn on top; the higher
            // zIndex is nearer the front, and nothing moves.
            ZStack {
                ColorPicker(Color("#E53935"))
                    .frame(width: 150)
                    .frame(height: 70)
                    .horizontalAlignment(.start)
                    .zIndex(redInFront ? 1 : 0)

                ColorPicker(Color("#1E88E5"))
                    .frame(width: 150)
                    .frame(height: 70)
                    .horizontalAlignment(.end)
                    .zIndex(redInFront ? 0 : 1)
            }
            .frame(height: 70)
            .frame(maxWidth: 240)

            SwitchRow("Red in front", $redInFront)
        }
        """

    var body: some View {
        VStack {
            ZStack {
                ColorPicker(Color("#E53935"))
                    .frame(width: 150)
                    .frame(height: 70)
                    .horizontalAlignment(.start)
                    .zIndex(redInFront ? 1 : 0)

                ColorPicker(Color("#1E88E5"))
                    .frame(width: 150)
                    .frame(height: 70)
                    .horizontalAlignment(.end)
                    .zIndex(redInFront ? 0 : 1)
            }
            .frame(height: 70)
            .frame(maxWidth: 240)
            .horizontalAlignment(.center)

            SwitchRow("Red in front", $redInFront)
                .horizontalAlignment(.center)
        }
        .spacing(12)
    }

    var notes: (any View)? { nil }
}

/// One labelled marker, so the sample says what is being positioned rather than
/// how it is drawn.
private struct Marker: View {
    let text: String
    let color: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.white)
            .background(Color(color))
            .padding(EdgeInsets(10, 6))
    }
}
