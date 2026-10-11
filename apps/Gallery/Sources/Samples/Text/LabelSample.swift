import SwiftOmniUI

struct LabelSample: SampleContent, ExampleContent {
    static let id = "label"
    static let title = "Text"
    static let summary = "Read-only native text with SwiftOmniUI typography and alignment."

    static let code = """
        VStack {
            Text("Plain")

            Text("Bold")
                .bold()

            Text("Italic, and coloured")
                .italic()
                .foregroundStyle(Palette.accent)

            Text("Underlined and struck through")
                .underline().strikethrough()

            Text("Centred, with room around it")
                .multilineTextAlignment(.center)
                .padding(8)

            Text("A long line that has nowhere left to go, so it is cut short with an ellipsis")
                .truncationMode(.tail)
                .lineLimit(1)

            Text("Letters spaced out")
                .tracking(3)

            // One string in mixed case, drawn twice. The case is the DRAWING;
            // the text stays as it was written.
            Text("One string, drawn in Two Ways")
                .textCase(.uppercase)

            Text("One string, drawn in Two Ways")
                .textCase(.lowercase)

        }
        """

    var body: some View {
        VStack {
            Text("Plain")
                .font(.system(size: 16))

            Text("Bold")
                .font(.system(size: 16))
                .bold()

            Text("Italic, and coloured")
                .font(.system(size: 16))
                .italic()
                .foregroundStyle(Palette.accent)

            Text("Underlined and struck through")
                .font(.system(size: 16))
                .underline().strikethrough()

            Text("Centred, with room around it")
                .font(.system(size: 16))
                .multilineTextAlignment(.center)
                .padding(8)

            Text("A long line that has nowhere left to go, so it is cut short with an ellipsis")
                .font(.system(size: 16))
                .truncationMode(.tail)
                .lineLimit(1)

            Text("Letters spaced out")
                .font(.system(size: 16))
                .tracking(3)

            Text("One string, drawn in Two Ways")
                .font(.system(size: 16))
                .textCase(.uppercase)

            Text("One string, drawn in Two Ways")
                .font(.system(size: 16))
                .textCase(.lowercase)
        }
        .spacing(10)
    }

    var notes: (any View)? {
        VStack {
            Text("The uppercase and the lowercase line are written the same way, in mixed "
                + "case: the transform changes the DRAWING and leaves the text alone.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("Text follows the system's text-size setting; where the platform "
                + "offers no such setting, the size written is the size drawn.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("Formatting is expressed by SwiftOmniUI properties and `Text` runs; "
                + "the native host remains responsible for shaping and drawing glyphs.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(10)
    }
}
