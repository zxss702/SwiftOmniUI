import SwiftOmniUI

/// Children drawn one over another, each in the whole room or where its own
/// frame puts it, and which of them is on top.
struct ZStackSample: SampleContent {
    static let id = "zStack"
    static let title = "ZStack"
    static let summary = "Children drawn one over another, each in the whole room or where its own frame puts it."

    var examples: [Example] {
        [Example(Areas()), Example(Layers())]
    }
}

/// Two markers aligned in the whole room, and a panel drawn in a corner of it.
private struct Areas: ExampleContent {
    static let code = """
        VStack {
            ZStack(alignment: .topLeading) {
                // The whole room, filled.
                ColorPicker(Palette.outline)

                // Its own size, tucked into the top-left.
                ColorPicker(Color("#1E88E5"))
                    .frame(width: 120, height: 60)
                    .offset(x: 16, y: 16)

                // Its natural size, where the stack's alignment put it.
                Marker(text: "start", color: "#E53935")

                // Asking for the whole room, so its own alignment answers.
                Marker(text: "end", color: "#00897B")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            .frame(height: 180)
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
        ZStack(alignment: .topLeading) {
            ColorPicker(Palette.outline)

            ColorPicker(Color("#1E88E5"))
                .frame(width: 120, height: 60)
                .offset(x: 16, y: 16)

            Marker(text: "start", color: "#E53935")

            Marker(text: "end", color: "#00897B")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .frame(height: 180)
    }

    var notes: (any View)? {
        Text("A child keeps its own size until it asks for the room - the frame's alignment then says where in it it stands.")
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .zIndex(redInFront ? 1 : 0)

                ColorPicker(Color("#1E88E5"))
                    .frame(width: 150)
                    .frame(height: 70)
                    .frame(maxWidth: .infinity, alignment: .trailing)
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .zIndex(redInFront ? 1 : 0)

                ColorPicker(Color("#1E88E5"))
                    .frame(width: 150)
                    .frame(height: 70)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .zIndex(redInFront ? 0 : 1)
            }
            .frame(height: 70)
            .frame(maxWidth: 240)

            SwitchRow("Red in front", $redInFront)
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
