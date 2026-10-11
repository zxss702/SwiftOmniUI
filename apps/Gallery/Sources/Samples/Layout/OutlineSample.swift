import SwiftOmniUI

/// A layout's own box: its background and its outline on the shape it names, and what it holds cut to that shape.
struct OutlineSample: SampleContent, ExampleContent {
    @State private var clips = true

    static let id = "outline"
    static let title = "Shape and outline"
    static let summary = "A stack, a grid or a ZStack paints its own background and outline, in the shape you give it."

    static let code = """
        @State private var clips = true

        VStack {
            VStack {
                Text("A column")
                Text("rounded, with a hairline")
            }
            .padding(16)
            .stroke(Palette.outline, width: 1)
            .shape(.roundedRectangle(12))

            HStack {
                Text("A row,")
                Text("square and thicker")
            }
            .spacing(6)
            .padding(16)
            .stroke(Palette.accent, width: 3)
            .shape(.rectangle)

            ZStack {
                Text("An ellipse")
            }
            .padding(24)
            .stroke(Palette.accent)
            .shape(.ellipse)

            // The box fills the ZStack; its corners are cut only while the
            // ZStack clips what it holds.
            if clips {
                ZStack {
                    ColorPicker(Palette.accent)
                }
                .shape(.roundedRectangle(24))
                .clipped()
                .frame(height: 60)
            } else {
                ZStack {
                    ColorPicker(Palette.accent)
                }
                .shape(.roundedRectangle(24))
                .frame(height: 60)
            }

            SwitchRow("Cut what it holds", $clips)
        }
        """

    var body: some View {
        VStack {
            VStack {
                Text("A column")
                    .font(.system(size: 15))
                Text("rounded, with a hairline")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.subtle)
            }
            .spacing(2)
            .padding(16)
            .stroke(Palette.outline, width: 1)
            .shape(.roundedRectangle(12))

            HStack {
                Text("A row,")
                    .font(.system(size: 15))
                Text("square and thicker")
                    .font(.system(size: 15))
            }
            .spacing(6)
            .padding(16)
            .stroke(Palette.accent, width: 3)
            .shape(.rectangle)

            ZStack {
                Text("An ellipse")
                    .font(.system(size: 15))
            }
            .padding(24)
            .stroke(Palette.accent)
            .shape(.ellipse)

            if clips {
                ZStack {
                    ColorPicker(Palette.accent)
                }
                .shape(.roundedRectangle(24))
                .clipped()
                .frame(height: 60)
            } else {
                ZStack {
                    ColorPicker(Palette.accent)
                }
                .shape(.roundedRectangle(24))
                .frame(height: 60)
            }

            SwitchRow("Cut what it holds", $clips)
        }
        .spacing(12)
    }

    var notes: (any View)? {
        Text("The shape is `.rectangle`, `.roundedRectangle(radius)` or `.ellipse`: the layout's background is "
            + "painted to it and its outline follows it. `.clipped()` cuts what the layout holds to it too.")
            .font(.system(size: 12))
            .foregroundStyle(Palette.subtle)
    }
}
