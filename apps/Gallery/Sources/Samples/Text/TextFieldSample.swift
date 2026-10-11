import SwiftOmniUI

/// Single-line text fields, with focus, case and keyboard choices.
struct TextFieldSample: SampleContent, ExampleContent {
    @State private var name = ""
    @State private var editing = false
    @State private var code = ""
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
        @State private var email = ""
        @State private var password = ""
        @State private var done = 0

        VStack {
            // The greeting below reads `name` and the caret below reads `code`,
            // so a keystroke in either builds this closure; the fields read
            // nothing - they are handed the state - and typing an address or a
            // password builds nothing at all.

            TextField("Type your name", text: $name)
                .focused($editing)

            Button("Give the field the focus", action: { editing = true })

            Text(name.isEmpty ? "Hello, stranger" : "Hello, \\(name)!")

            Text(editing ? "the field has the focus" : "the field does not have the focus")

            Text("return pressed \\(done)x")

            // A field for something that is not prose: every letter typed
            // stands in capitals, as a serial number's do.
            TextField("a serial number", text: $code)
                .textCase(.uppercase)

            TextField("disabled")
                .disabled(true)

            SecureField("a password", text: $password)
                .submitLabel(.done)

            // The keyboard the platform brings up, a cap on the length, and
            // what the return key does when it is pressed.
            TextField("an address, capped at 20", text: $email)
                .textContentType(.email)
                .onSubmit { done += 1 }
                .onChange(of: email) { email = String(email.prefix(20)) }
        }
        """

    var body: some View {
        VStack {

            TextField("Type your name", text: $name)
                .accessibilityIdentifier("entry.name")
                .accessibilityLabel("Name")
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

            // A field for something that is not prose: every letter typed
            // stands in capitals, as a serial number's do.
            TextField("a serial number", text: $code)
                .accessibilityIdentifier("entry.code")
                .accessibilityLabel("Serial number")
                .textCase(.uppercase)

            TextField("disabled")
                .accessibilityIdentifier("entry.disabled")
                .accessibilityLabel("A field that cannot be typed in")
                .disabled(true)

            SecureField("a password", text: $password)
                .accessibilityIdentifier("entry.password")
                .accessibilityLabel("Password")
                .submitLabel(.done)

            // The keyboard the platform brings up, a cap on the length, and
            // what the return key does when it is pressed.
            TextField("an address, capped at 20", text: $email)
                .textContentType(.email)
                .onSubmit { done += 1 }
                .accessibilityIdentifier("entry.email")
                .accessibilityLabel("Email address")
                .onChange(of: email) { email = String(email.prefix(20)) }
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
            + "`.onChange` written afterwards runs beside it, never instead of "
            + "it, and after the state already holds the text.")
            .font(.system(size: 12))
            .foregroundStyle(Palette.subtle)
    }
}
