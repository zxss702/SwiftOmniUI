import SwiftOmniUI

/// Native alerts, confirmations, choices of actions and prompts, asked as awaited SwiftOmniUI acts.
struct DialogsSample: SampleContent, ExampleContent {
    @State private var answer = "nothing asked yet"
    @State private var name = "Draft 1"

    static let id = "dialogs"
    static let title = "Dialogs"
    static let summary = "An alert, a confirmation, a choice of actions and a prompt - asked, awaited, answered."

    static let code = """
        @State private var answer = "nothing asked yet"
        @State private var name = "Draft 1"

        VStack {
            // The answer is read here, so every dialog that closes builds
            // this closure.

            // One button, nothing to answer: the handler resumes when it is
            // dismissed, so the next line runs with the alert already gone.
            Button("Tell me something", action: {
                    try await Dialogs.alert(
                        "Saved", message: "The draft is safe")
                    answer = "the alert was dismissed"
                })
                

            // Ask, await, branch - in one place, which is what an act is for.
            Button("Ask me a question", action: {
                    let ok = try await Dialogs.confirm(
                        "Delete draft?", message: "This cannot be undone",
                        accept: "Delete", cancel: "Keep")
                    answer = ok ? "Delete pressed" : "Keep pressed"
                })
                

            // The answer is the pressed CAPTION, cancel and destruction
            // included - nil only when the sheet was dismissed with nothing
            // chosen, tapping beside it where the platform allows that.
            Button("Offer me choices", action: {
                    let choice = try await Dialogs.chooseAction(
                        "Share via", cancel: "Cancel", destruction: "Delete",
                        buttons: ["Mail", "Message"])
                    answer = choice.map { "\\($0) pressed" }
                        ?? "dismissed with nothing chosen"
                })
                

            // nil is CANCELLED; an accepted prompt with nothing typed comes
            // back as "" - an empty answer, which is still an answer.
            Button("Ask me to type", action: {
                    let typed = try await Dialogs.prompt(
                        "Rename", message: "A new name for the draft",
                        placeholder: "Name", initialValue: name, maximumLength: 40)
                    if let typed { name = typed }
                    answer = typed.map { "renamed to '\\($0)'" } ?? "cancelled"
                })
                

            Text(answer)
            Text("the draft is called '\\(name)'")
        }
        """

    var body: some View {
        VStack {

            Button("Tell me something", action: {
                    try await Dialogs.alert(
                        "Saved", message: "The draft is safe")
                    answer = "the alert was dismissed"
                })
                

            Button("Ask me a question", action: {
                    let ok = try await Dialogs.confirm(
                        "Delete draft?", message: "This cannot be undone",
                        accept: "Delete", cancel: "Keep")
                    answer = ok ? "Delete pressed" : "Keep pressed"
                })
                

            Button("Offer me choices", action: {
                    let choice = try await Dialogs.chooseAction(
                        "Share via", cancel: "Cancel", destruction: "Delete",
                        buttons: ["Mail", "Message"])
                    answer = choice.map { "\($0) pressed" }
                        ?? "dismissed with nothing chosen"
                })
                

            Button("Ask me to type", action: {
                    let typed = try await Dialogs.prompt(
                        "Rename", message: "A new name for the draft",
                        placeholder: "Name", initialValue: name, maximumLength: 40)
                    if let typed { name = typed }
                    answer = typed.map { "renamed to '\($0)'" } ?? "cancelled"
                })
                

            Text(answer)
                .font(.system(size: 17))
                .multilineTextAlignment(.center)

            Text("the draft is called '\(name)'")
                .font(.system(size: 14))
                .foregroundStyle(Palette.subtle)
                .multilineTextAlignment(.center)
        }
        .spacing(12)
    }

    var notes: (any View)? {
        VStack {
            Text("A dialog is an act, not a view. The handler resumes with the "
                + "native answer after the dialog closes.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("A choice of actions answers with the pressed caption, cancel and "
                + "destruction included. A prompt answers nil when cancelled - an "
                + "accepted empty answer is \"\", which is not the same thing.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(8)
    }
}
