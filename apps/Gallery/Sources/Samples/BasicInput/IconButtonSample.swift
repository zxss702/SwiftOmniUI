import SwiftOmniUI

/// Two buttons whose content is an icon, each drawn once per color scheme.
struct IconButtonSample: SampleContent, ExampleContent {
    @State private var taps = 0

    static let id = "iconButton"
    static let title = "Icon button"
    static let summary = "A button whose content is an icon - with an outline and a rounded shape."

    static let code = """
        @State private var taps = 0

        VStack {
            // The count is read here, so a press builds this closure again.

            HStack {
                Button(icon: ImageSource(light: "nav_media.png", dark: "nav_media_dark.png"), action: { taps += 1 })
                    .style("IconButton")
                    .frame(width: 64)
                    .frame(height: 64)
                    .stroke(Palette.outline, width: 1)
                    .shape(.roundedRectangle(12))

                Button(icon: ImageSource(light: "nav_layout.png", dark: "nav_layout_dark.png"), action: { taps += 1 })
                    .style("IconButton")
                    .frame(width: 64)
                    .frame(height: 64)
                    .shape(.roundedRectangle(32))
                    
            }

            Text("Tapped \\(taps) time\\(taps == 1 ? "" : "s")")
        }
        """

    var body: some View {
        VStack {

            HStack {
                Button(icon: ImageSource(light: "nav_media.png", dark: "nav_media_dark.png"), action: { taps += 1 })
                    .style("IconButton")
                    .frame(width: 64)
                    .frame(height: 64)
                    .padding(12)
                    .stroke(Palette.outline, width: 1)
                    .shape(.roundedRectangle(12))

                Button(icon: ImageSource(light: "nav_layout.png", dark: "nav_layout_dark.png"), action: { taps += 1 })
                    .style("IconButton")
                    .frame(width: 64)
                    .frame(height: 64)
                    .padding(12)
                    .background(Palette.accent)
                    .shape(.roundedRectangle(32))
                    
            }
            .spacing(12)

            Text("Tapped \(taps) time\(taps == 1 ? "" : "s")")
                .font(.system(size: 14))
        }
        .spacing(12)
    }

    var notes: (any View)? {
        VStack {
            Text("The picture is what gives it its purpose, so it goes in the initializer - "
                + "and it can be drawn once per colorScheme, like any other, which is what these "
                + "two are.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("It is a button, not an `Image` with a tap recognizer on it: that gives "
                + "no shape and no action of a button's own.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(12)
    }
}
