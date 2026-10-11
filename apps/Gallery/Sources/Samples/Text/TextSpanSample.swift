import SwiftOmniUI

/// Runs of text inside one Text, each with a look of its own.
struct TextSpanSample: SampleContent, ExampleContent {
    @State private var highlighted = 1

    /// The line the last example colours one word of.
    private let words = ["A", "Text", "has", "one", "TextColor"]

    static let id = "textSpan"
    static let title = "TextSpan"
    static let summary = "Text in more than one colour: a Text's runs, each with a look of its own."

    static let code = """
        @State private var highlighted = 1

        private let words = ["A", "Text", "has", "one", "TextColor"]

        VStack {
            // Two colours in one line: a label has one `foregroundStyle`, so
            // `Text + Text` is the only way - each side keeps its own look.
            Text("let ").foregroundStyle(Palette.brand)
                + Text("counter").foregroundStyle(Palette.accent)
                + Text(" = 0")

            // A run carries font properties of its own.
            Text("Sold ").foregroundStyle(Palette.text)
                + Text("out")
                    .bold()
                    .foregroundStyle(Palette.accent)

            // A loop is the usual way - one run per token, gathered with
            // `reduce` - which is how the code block on every page of this
            // gallery is drawn.
            words.enumerated().map { pair in
                Text(pair.element + " ")
                    .foregroundStyle(pair.offset == highlighted ? Palette.accent : Palette.text)
                    .fontWeight(pair.offset == highlighted ? .bold : .regular)
            }
            .reduce(Text(""), +)

            Button("Move the highlight", action: { highlighted = (highlighted + 1) % words.count })
        }
        """

    var body: some View {
        VStack {

            (Text("let ").foregroundStyle(Palette.brand)
                + Text("counter").foregroundStyle(Palette.accent)
                + Text(" = 0"))
                .font(.system(size: 17, design: .monospaced))

            Text("Sold ")
                .font(.system(size: 17))
                .foregroundStyle(Palette.text)
                + Text("out")
                    .font(.system(size: 17))
                    .bold()
                    .foregroundStyle(Palette.accent)

            words.enumerated().map { pair in
                Text(pair.element + " ")
                    .font(.system(size: 17))
                    .foregroundStyle(pair.offset == highlighted ? Palette.accent : Palette.text)
                    .fontWeight(pair.offset == highlighted ? .bold : .regular)
            }
            .reduce(Text(""), +)

            Button("Move the highlight", action: { highlighted = (highlighted + 1) % words.count })

        }
        .spacing(12)
    }

    var notes: (any View)? {
        VStack {
            Text("Two colours in one line is what runs are for: a label has one `foregroundStyle`, "
                + "so text in two colours is two runs joined with `+`. A run carries font and "
                + "text properties of its own - size, family, weight. It is not a view, so "
                + "there is no margin and no size on it.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("A loop is the usual way, one run per token, gathered into one Text with "
                + "`reduce` - which is how the code block under every example here is drawn. "
                + "Moving the highlight sends the two runs that changed and nothing else; "
                + "the host keeps the rest of the line.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(12)
    }
}
