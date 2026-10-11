import SwiftOmniUI

/// `ContentUnavailableView`: what stands where content would, while none does.
struct ContentUnavailableSample: SampleContent, ExampleContent {
    /// The words a search would have found.
    @State private var query = ""
    @State private var hasContent = false

    static let id = "content-unavailable"
    static let title = "No content yet"
    static let summary = "A symbol, a title and the words under it - the empty state."

    static let code = """
        if hasContent {
            NotesList()
        } else {
            ContentUnavailableView(
                "No Notes",
                systemImage: noteIcon,
                description: "Create a note to see it listed here.")
        }

        // The full form, with an action:
        ContentUnavailableView {
            Label("No Selection", systemImage: selectionIcon)
        } description: {
            Text("Pick a note from the list.")
        } actions: {
            Button("New Note", action: create)
        }
        """

    var notes: (any View)? {
        VStack {
            Text("The common form - `title`, `systemImage:` and a description - "
                + "draws the platform's empty state: a greyed symbol, a heading, "
                + "smaller words. The builder form lets the label, description "
                + "and actions say anything.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(12)
    }

    var body: some View {
        VStack {
            Toggle("Show content", isOn: $hasContent)

            Group {
                if hasContent {
                    VStack {
                        Text("A note")
                        Text("Another")
                        Text("A third")
                    }
                    .spacing(4)
                } else {
                    ContentUnavailableView(
                        "No Notes",
                        systemImage: {
                            #if os(Windows)
                            return "\u{E70B}"
                            #else
                            return "notebook-symbolic"
                            #endif
                        }(),
                        description: "Create a note to see it listed here.")
                }
            }
        }
        .spacing(16)
        .accessibilityIdentifier("contentUnavailable.demo")
    }
}
