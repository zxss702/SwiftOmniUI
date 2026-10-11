import SwiftOmniUI

/// Text of several lines, in two editors sharing the one state.
struct TextEditorSample: SampleContent, ExampleContent {
    @State private var draft = ""

    static let id = "textEditor"
    static let title = "TextEditor"
    static let summary = "A TextField with room: several lines, and a state two editors can share."

    static let code = """
        @State private var draft = ""

        VStack {
            // The count of characters below reads `draft`, so every keystroke
            // builds this closure; the two editors are handed the state.

            // The same text in both editors, so typing in either moves the
            // other - the state is shared.
            Grid(horizontalSpacing: 12, verticalSpacing: nil) {
                GridRow {
                    VStack {
                        Text("a stated height")

                        TextEditor("Anything worth remembering", text: $draft)
                            .frame(height: 110)
                    }

                    VStack {
                        Text("the same text again")

                        TextEditor("The same text, written twice", text: $draft)
                    }
                }
            }

            Text(draft.isEmpty ? "nothing written yet" : "\\(draft.count) character(s)")

            Button("Clear", action: { draft = "" })
                .disabled(draft.isEmpty)
                
        }
        """

    var body: some View {
        VStack {

            // The same text in both editors, so typing in either moves the
            // other - the state is shared.
            Grid(horizontalSpacing: 12, verticalSpacing: nil) {
                GridRow {
                    VStack {
                        Text("a stated height")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.subtle)

                        TextEditor("Anything worth remembering", text: $draft)
                            .accessibilityIdentifier("editor.notes")
                            .accessibilityLabel("Notes")
                            .frame(height: 110)
                    }
                    .spacing(4)

                    VStack {
                        Text("the same text again")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.subtle)

                        TextEditor("The same text, written twice", text: $draft)
                            .accessibilityIdentifier("editor.notes.again")
                            .accessibilityLabel("Notes, again")
                    }
                    .spacing(4)
                }
            }

            Text(draft.isEmpty ? "nothing written yet" : "\(draft.count) character(s)")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
                .multilineTextAlignment(.center)

            Button("Clear", action: { draft = "" })
                .font(.system(size: 13))
                .padding(EdgeInsets(16, 6))
                .disabled(draft.isEmpty)
                
        }
        .spacing(12)
    }

    var notes: (any View)? { nil }
}
