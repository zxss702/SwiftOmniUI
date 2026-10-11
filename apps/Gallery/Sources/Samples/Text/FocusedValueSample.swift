import SwiftOmniUI

/// What the focused field publishes under - its name, and the words typed in it.
private struct FieldKey: FocusedValueKey { typealias Value = String }
private struct DraftKey: FocusedValueKey { typealias Value = String }

extension FocusedValues {
    fileprivate var field: String? {
        get { self[FieldKey.self] }
        set { self[FieldKey.self] = newValue }
    }
    fileprivate var draft: String? {
        get { self[DraftKey.self] }
        set { self[DraftKey.self] = newValue }
    }
}

/// `.focusedValue` publishes a value while its view holds the keyboard focus;
/// `@FocusedValue` reads the nearest write on the focus chain, wherever the
/// reading view stands.
struct FocusedValueSample: SampleContent, ExampleContent {
    @State private var name = ""
    @State private var email = ""

    /// What the focused field publishes: its name, and the words typed in it.
    @FocusedValue(\.field) private var field
    @FocusedValue(\.draft) private var draft

    static let id = "focused-value"
    static let title = "Focused value"
    static let summary = "A value published by the focused view - a readout follows whichever field holds the focus."

    static let code = """
        struct FieldKey: FocusedValueKey { typealias Value = String }
        struct DraftKey: FocusedValueKey { typealias Value = String }

        extension FocusedValues {
            var field: String? {
                get { self[FieldKey.self] }
                set { self[FieldKey.self] = newValue }
            }
            var draft: String? {
                get { self[DraftKey.self] }
                set { self[DraftKey.self] = newValue }
            }
        }

        @State private var name = ""
        @State private var email = ""

        @FocusedValue(\\.field) private var field
        @FocusedValue(\\.draft) private var draft

        var body: some View {
            VStack {
                Text(field.map { "Focused on \\($0): '\\(draft ?? "")'" }
                    ?? "Nothing focused")

                TextField("Name", text: $name)
                    .focusedValue(\\.field, "name")
                    .focusedValue(\\.draft, name)

                TextField("Email", text: $email)
                    .focusedValue(\\.field, "email")
                    .focusedValue(\\.draft, email)
            }
        }
        """

    var body: some View {
        VStack {
            Text(field.map { "Focused on \($0): '\(draft ?? "")'" }
                ?? "Nothing focused")
                .font(.system(size: 13))
                .foregroundStyle(Palette.accent)

            TextField("Name", text: $name)
                .focusedValue(\.field, "name")
                .focusedValue(\.draft, name)

            TextField("Email", text: $email)
                .focusedValue(\.field, "email")
                .focusedValue(\.draft, email)
        }
        .spacing(12)
    }

    var notes: (any View)? {
        Text("The writes are declared beside the view they describe, not on a "
            + "shared switchboard: a command bar or a readout asks `\\.`field` "
            + "and answers for whatever is focused. `.focusedSceneValue` "
            + "publishes to the whole scene instead, and sits beneath the "
            + "focus chain's own writes.")
            .font(.system(size: 12))
            .foregroundStyle(Palette.subtle)
    }
}
