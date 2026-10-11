import SwiftOmniUI

/// Single-line text fields, with focus, caret, selection and keyboard choices.
struct TextFieldSample: SampleContent, ExampleContent {
    @State private var name = ""
    @State private var editing = false
    @State private var code = ""
    @State private var selectAll = false
    @State private var email = ""
    @State private var password = ""
    @State private var done = 0

    static let id = "textField"
    static let title = "TextField"
    static let summary = "A single-line field. Given a binding it writes every edit back."

    static let code = """
        @State private var name = ""
        @State private var editing = false
        @State private var code = ""
        @State private var selectAll = false
        @State private var email = ""
        @State private var password = ""
        @State private var done = 0

        VStack {
            // The greeting below reads `name` and the caret below reads `code`,
            // so a keystroke in either builds this closure; the fields read
            // nothing - they are handed the state - and typing an address or a
            // password builds nothing at all.
            DebugInfoLabel()

            TextField("Type your name", text: $name)
                .showsClearButton(true)
                .focused($editing)

            Button("Give the field the focus", action: { editing = true })

            Text(name.isEmpty ? "Hello, stranger" : "Hello, \\(name)!")

            Text(editing ? "the field has the focus" : "the field does not have the focus")

            Text("return pressed \\(done)x")

            // A field for something that is not prose: the platform's
            // underline and its next-word guesses only get in the way, the
            // caret can be put where the user did not, and every letter
            // typed stands in capitals, as a serial number's do.
            TextField("a serial number", text: $code)
                .textCase(.uppercase)
                .isSpellCheckEnabled(false)
                .isTextPredictionEnabled(false)
                .cursorPosition(selectAll ? 0 : code.count)
                .selectionLength(selectAll ? code.count : 0)

            // SELECTING IS SOMETHING THAT HAPPENS, so it is a button rather
            // than a switch - and it says which of the two it will do next,
            // because a press has to WRITE a value the field has not been
            // given: an absent field means unchanged, so a press that asks
            // for the selection the field already has says nothing at all.
            Button(selectAll ? "Clear the selection" : "Select the lot", action: { selectAll.toggle() })
                

            TextField("read only")
                .isReadOnly(true)

            SecureField("a password", text: $password)
                .submitLabel(.done)

            // The keyboard the platform brings up, a cap on the length, and
            // what the return key does when it is pressed.
            TextField("an address, capped at 20", text: $email)
                .textContentType(.email)
                .maximumLength(20)
                .onSubmit { done += 1 }
        }
        """

    var body: some View {
        VStack {
            DebugInfoLabel()

            TextField($name)
                .accessibilityIdentifier("entry.name")
                .accessibilityLabel("Name")
                .placeholder("Type your name")
                .showsClearButton(true)
                .focused($editing)

            // `.focused` is the binding both ways: the field's move of the
            // focus writes `editing`, and writing it puts the focus back.
            Button("Give the field the focus", action: { editing = true })

            Text(name.isEmpty ? "Hello, stranger" : "Hello, \(name)!")
                .font(.system(size: 17))
                .multilineTextAlignment(.center)

            Text(editing ? "the field has the focus" : "the field does not have the focus")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
                .multilineTextAlignment(.center)

            Text("return pressed \(done)x")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
                .multilineTextAlignment(.center)

            // A field for something that is not prose: the platform's
            // underline and its next-word guesses only get in the way, the
            // caret can be put where the user did not, and every letter
            // typed stands in capitals, as a serial number's do.
            TextField($code)
                .accessibilityIdentifier("entry.code")
                .accessibilityLabel("Serial number")
                .placeholder("a serial number")
                .textCase(.uppercase)
                .isSpellCheckEnabled(false)
                .isTextPredictionEnabled(false)
                .cursorPosition(selectAll ? 0 : code.count)
                .selectionLength(selectAll ? code.count : 0)

            // SELECTING IS SOMETHING THAT HAPPENS, so it is a button rather
            // than a switch - and it says which of the two it will do next,
            // because a press has to WRITE a value the field has not been
            // given: an absent field means unchanged, so a press that asks
            // for the selection the field already has says nothing at all.
            Button(selectAll ? "Clear the selection" : "Select the lot", action: { selectAll.toggle() })
                .font(.system(size: 13))
                .padding(EdgeInsets(16, 6))
                .horizontalAlignment(.center)
                

            TextField("read only")
                .accessibilityIdentifier("entry.readOnly")
                .accessibilityLabel("A field that cannot be typed in")
                .isReadOnly(true)

            SecureField("a password", text: $password)
                .accessibilityIdentifier("entry.password")
                .accessibilityLabel("Password")
                .submitLabel(.done)

            // The keyboard the platform brings up, a cap on the length, and
            // what the return key does when it is pressed.
            TextField($email)
                .accessibilityIdentifier("entry.email")
                .accessibilityLabel("Email address")
                .placeholder("an address, capped at 20")
                .textContentType(.email)
                .maximumLength(20)
                .onSubmit { done += 1 }
                .help("Submitted to nobody - this is a gallery")

            // `.textFieldStyle` is the field's look as a logical value; each
            // host maps it to its own native chrome.
            TextField("plain style")
                .textFieldStyle(.plain)

            TextField("square border")
                .textFieldStyle(.squareBorder)
        }
        .spacing(12)
    }

    var notes: (any View)? {
        Text("The binding IS the two-way part: `TextField($name)` hands the state to the "
            + "host, which shows it in the field and lands every edit back on it. "
            + "`.onTextChanged` written afterwards runs beside it, never instead of "
            + "it, and after the state already holds the text.")
            .font(.system(size: 12))
            .foregroundStyle(Palette.subtle)
    }
}
