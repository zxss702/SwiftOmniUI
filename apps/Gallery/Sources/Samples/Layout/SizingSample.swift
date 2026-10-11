import SwiftOmniUI

/// How big a view asks to be, the bounds on that request, and clipping.
struct SizingSample: SampleContent, ExampleContent {
    static let id = "sizing"
    static let title = "Sizing and clipping"
    static let summary = "How big a view asks to be, the bounds on it, and what happens at the edge."

    static let code = """
        VStack {
            // A request, not an instruction: the layout has the last word.
            ColorPicker(Palette.accent)
                .frame(width: 120)
                .frame(height: 24)

            // Filling the width, but never past 200.
            ColorPicker(Palette.accent)
                .frame(height: 24)
                .frame(maxWidth: 200)

            // Filling the width, but never squeezed below 160.
            ColorPicker(Palette.accent)
                .frame(height: 24)
                .frame(minWidth: 160)

            // The same ceiling on the other axis, against the same request
            // without it: 80 asked for on the left, 32 allowed on the right.
            HStack {
                ColorPicker(Palette.outline)
                    .frame(width: 60)
                    .frame(height: 80)
                    .frame(maxHeight: .infinity, alignment: .top)

                ColorPicker(Palette.accent)
                    .frame(width: 60)
                    .frame(height: 80)
                    .frame(maxHeight: 32)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .spacing(10)

            // A child drawn past the layout's edge, cut off at it.
            VStack {
                ColorPicker(Palette.accent)
                    .frame(height: 24)
                    .offset(x: 60)
            }
            .clipped()
            .frame(width: 120)

            // The same child in the same layout, and nothing cut off.
            VStack {
                ColorPicker(Palette.accent)
                    .frame(height: 24)
                    .offset(x: 60)
            }
            .frame(width: 120)
        }
        """

    var body: some View {
        VStack {
            row("width(120)",
                ColorPicker(Palette.accent).frame(width: 120).frame(height: 24))

            row("maximumWidth(200)",
                ColorPicker(Palette.accent).frame(height: 24).frame(maxWidth: 200))

            row("minimumWidth(160)",
                ColorPicker(Palette.accent).frame(height: 24).frame(minWidth: 160))

            // The pair is the point: both ask for 80 high, and only the one
            // without a ceiling on it is allowed to have it.
            row("height(80), then the same with maximumHeight(32)",
                HStack {
                    ColorPicker(Palette.outline)
                        .frame(width: 60)
                        .frame(height: 80)
                        .frame(maxHeight: .infinity, alignment: .top)

                    ColorPicker(Palette.accent)
                        .frame(width: 60)
                        .frame(height: 80)
                        .frame(maxHeight: 32)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                .spacing(10))

            row("clipped()",
                VStack {
                    ColorPicker(Palette.accent)
                        .frame(height: 24)
                        .offset(x: 60)
                }
                .clipped()
                .frame(width: 120))

            row("not clipped",
                VStack {
                    ColorPicker(Palette.accent)
                        .frame(height: 24)
                        .offset(x: 60)
                }
                .frame(width: 120))
        }
        .spacing(14)
    }

    var notes: (any View)? {
        VStack {
            Text("Every one of these is a REQUEST. The layout decides, and a stack that "
                + "has no room to spare will ignore a width it cannot give - which is why "
                + "the bounds are worth saying separately from the size.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("`maximumWidth` and `maximumHeight` are the ceiling: a "
                + "view filling its parent stops growing there, and a view that ASKED for "
                + "more than the ceiling gets the ceiling. The minimum pair are the floor, "
                + "and stop it being squeezed.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("`clipsContent` is the LAYOUT's edge, and cuts off a child drawn "
                + "past it - here by a translation. It is not the same as a shape given "
                + "to one view.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(8)
    }

    /// One example with the modifier that made it, so the column reads as a
    /// list of named cases.
    private func row(_ caption: String, _ view: any View) -> any View {
        VStack {
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(Palette.subtle)

            view
        }
        .spacing(6)
    }
}
