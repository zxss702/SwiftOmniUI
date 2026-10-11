import SwiftOmniUI

/// Rectangles of colour - square, rounded, round and faded - and a divider.
struct ColorBoxSample: SampleContent, ExampleContent {
    static let id = "colorBox"
    static let title = "ColorPicker"
    static let summary = "A rectangle of colour - the simplest thing a host draws."

    static let code = """
        VStack {
            HStack {
                ColorPicker(Palette.accent)
                    .frame(width: 44)
                    .frame(height: 44)

                ColorPicker(Palette.accent)
                    .cornerRadius(10)
                    .frame(width: 44)
                    .frame(height: 44)

                ColorPicker(Palette.accent)
                    .cornerRadius(22)
                    .frame(width: 44)
                    .frame(height: 44)

                ColorPicker(Color("#E53935"))
                    .cornerRadius(10)
                    .opacity(0.4)
                    .frame(width: 44)
                    .frame(height: 44)
            }

            // A one-pixel ColorPicker is also the usual divider.
            ColorPicker(Palette.outline)
                .frame(height: 1)
        }
        """

    var body: some View {
        VStack {
            HStack {
                ColorPicker(Palette.accent)
                    .frame(width: 44)
                    .frame(height: 44)

                ColorPicker(Palette.accent)
                    .cornerRadius(10)
                    .frame(width: 44)
                    .frame(height: 44)

                ColorPicker(Palette.accent)
                    .cornerRadius(22)
                    .frame(width: 44)
                    .frame(height: 44)

                ColorPicker(Color("#E53935"))
                    .cornerRadius(10)
                    .opacity(0.4)
                    .frame(width: 44)
                    .frame(height: 44)
            }
            .spacing(12)
            .horizontalAlignment(.center)

            ColorPicker(Palette.outline)
                .frame(height: 1)
        }
        .spacing(12)
    }

    var notes: (any View)? {
        Text("A ColorPicker draws the colour its initializer takes, which is its `.color`. "
            + "`.background` is a second surface behind it that the corner radius "
            + "does not round. A one-pixel ColorPicker is also the usual divider.")
            .font(.system(size: 12))
            .foregroundStyle(Palette.subtle)
    }
}
