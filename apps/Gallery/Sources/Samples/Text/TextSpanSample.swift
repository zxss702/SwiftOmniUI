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
            // The chosen run is read here, so tapping one builds this closure.
            DebugInfoLabel()

            // Two colours in one line, which is what runs are FOR: a label
            // has one `foregroundStyle`, so this is the only way.
            Text()
                .spans {
                    TextSpan("let ").foregroundStyle(Palette.brand)
                    TextSpan("counter").foregroundStyle(Palette.accent)
                    TextSpan(" = 0")
                }

            // A run carries font properties of its own, and what an unset one
            // falls back to is the platform's business.
            Text()
                .spans {
                    TextSpan("Sold ")
                    TextSpan("out")
                        .bold()
                        .foregroundStyle(Palette.onAccent)
                        .background(Palette.accent)
                }

            // A loop is the usual way - one run per token, which is how the
            // code block on every page of this gallery is drawn.
            Text()
                .spans {
                    ForEach(Array(words.enumerated()), id: \\.offset) { pair in
                        let (index, word) = pair
                        return TextSpan(word + " ")
                            .foregroundStyle(index == highlighted ? Palette.accent : Palette.text)
                            .fontWeight(index == highlighted ? .bold : .regular)
                    }
                }

            Button("Move the highlight", action: { highlighted = (highlighted + 1) % words.count })
                

            // `text` and `spans` are MUTUALLY EXCLUSIVE: a label
            // given both shows the runs.
            Text("this text never appears")
                .spans {
                    TextSpan("the runs win")
                }
        }
        """

    var body: some View {
        VStack {
            DebugInfoLabel()

            Text()
                .spans {
                    TextSpan("let ").foregroundStyle(Palette.brand)
                    TextSpan("counter").foregroundStyle(Palette.accent)
                    TextSpan(" = 0")
                }
                .font(.system(size: 17, design: .monospaced))

            Text()
                .spans {
                    TextSpan("Sold ")
                        .font(.system(size: 17))
                        .foregroundStyle(Palette.text)

                    TextSpan("out")
                        .font(.system(size: 17))
                        .bold()
                        .foregroundStyle(Palette.onAccent)
                        .background(Palette.accent)
                }

            Text()
                .spans {
                    ForEach(Array(words.enumerated()), id: \.offset) { pair in
                        let (index, word) = pair
                        return TextSpan(word + " ")
                            .font(.system(size: 17))
                            .foregroundStyle(index == highlighted ? Palette.accent : Palette.text)
                            .fontWeight(index == highlighted ? .bold : .regular)
                    }
                }

            Button("Move the highlight", action: { highlighted = (highlighted + 1) % words.count })
                

            Text("this text never appears")
                .spans {
                    TextSpan("the runs win")
                        .font(.system(size: 17))
                        .foregroundStyle(Palette.text)
                }

        }
        .spacing(12)
    }

    var notes: (any View)? {
        VStack {
            Text("Two colours in one line is what runs are for: a label has one `foregroundStyle`, "
                + "so text in two colours is two runs. A run carries font and text properties "
                + "of its own - size, family, weight, a background behind those words alone. "
                + "It is not a view, so there is no margin and no size on it.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("A loop is the usual way, one run per token - which is how the code block "
                + "under every example here is drawn. Moving the highlight sends the two runs "
                + "that changed and nothing else; the host keeps the rest of the line, the "
                + "same way it keeps a list of rows.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("`text` and `spans` are MUTUALLY EXCLUSIVE: the last label is given "
                + "both, and it shows only the runs.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("The Swift type is `TextSpan`, not `Span`: Swift's own standard library has "
                + "a `Span` in scope in every file, and it wins - `Span(\"…\")` does not "
                + "compile.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(12)
    }
}
