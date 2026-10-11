import SwiftOmniUI

/// Explicit native focus and soft-input actions.
struct KeyboardSample: SampleContent, ExampleContent {
    @State private var name = ""
    @State private var note = ""
    @State private var said = ""

    @Aim(TextField.self) private var first

    static let id = "keyboard"
    static let title = "Keyboard"
    static let summary = "Aim at one field, or release whichever input is focused."

    static let code = """
        @State private var name = ""
        @State private var note = ""
        @State private var said = ""
        @Aim(TextField.self) private var first

        VStack {
            // `said` is read here, so the answer below builds this closure.

            TextField("Name", text: $name)
                .aim(first)

            TextField("Note", text: $note)

            HStack {
                Button("Focus first", action: { try await first.focus() })
                    

                Button("Unfocus first", action: { try await first.unfocus() })
                    
            }

            Button("Close keyboard", action: {
                    said = try await OnScreenKeyboard.hide()
                        ? "Focus released"
                        : "Nothing was focused"
                })
                

            Text(said.isEmpty ? "Nothing said yet." : said)
        }
        """

    var notes: (any View)? {
        Text("`focus()` and `unfocus()` are acts aimed at one field with `@Aim`. "
            + "`OnScreenKeyboard.hide()` releases whichever input holds the focus, and answers "
            + "whether anything did.")
            .font(.system(size: 12))
            .foregroundStyle(Palette.subtle)
    }

    var body: some View {
        VStack {

            TextField("Name", text: $name)
                .accessibilityIdentifier("keyboard.name")
                .accessibilityLabel("Name")
                .aim(first)

            TextField("Note", text: $note)
                .accessibilityIdentifier("keyboard.note")
                .accessibilityLabel("Note")

            HStack {
                Button("Focus first", action: { try await first.focus() })
                    .frame(maxWidth: .infinity)
                    

                Button("Unfocus first", action: { try await first.unfocus() })
                    .frame(maxWidth: .infinity)
                    
            }
            .spacing(8)

            Button("Close keyboard", action: {
                    said = try await OnScreenKeyboard.hide()
                        ? "Focus released"
                        : "Nothing was focused"
                })
                

            Text(said.isEmpty ? "Nothing said yet." : said)
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(12)
    }
}
