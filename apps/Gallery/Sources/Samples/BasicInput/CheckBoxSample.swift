import SwiftOmniUI

/// A box ticked or not, on its own and several at once - a `Toggle` wearing
/// `.checkbox`.
struct CheckBoxSample: SampleContent, ExampleContent {
    @State private var agreed = false
    @State private var extras = [false, false, false]

    static let id = "checkBox"
    static let title = "CheckBox"
    static let summary = "A toggle drawn as a ticked box - .toggleStyle(.checkbox)."

    static let code = """
        @State private var agreed = false
        @State private var extras = [false, false, false]

        VStack {
            // The ticks are read here, so every box builds this closure.

            Toggle("I have read the terms", isOn: $agreed)
                .toggleStyle(.checkbox)

            Text(agreed ? "Ticked" : "Not ticked")

            ForEach(Array(["Cheese", "Bacon", "Egg"].enumerated()), id: \\.offset) { pair in
                let (index, name) = pair
                // $extras[index] is a Binding into the array - the box writes
                // its element and nothing else is asked.
                return Toggle(name, isOn: $extras[index])
                    .toggleStyle(.checkbox)
                    .id(name)
            }

            Text(chosen.isEmpty ? "Nothing extra" : "With \\(chosen.joined(separator: ", "))")
        }

        /// What is ticked, in the order the boxes are drawn.
        private var chosen: [String] {
            ["Cheese", "Bacon", "Egg"].enumerated().filter { extras[$0.offset] }.map { $0.element }
        }
        """

    var body: some View {
        VStack {

            Toggle("I have read the terms", isOn: $agreed)
                .toggleStyle(.checkbox)
                .accessibilityIdentifier("checkBox.agreed")
                .accessibilityLabel("Agreed")
                .tint(Palette.accent)
                .font(.system(size: 15))

            Text(agreed ? "Ticked" : "Not ticked")
                .font(.system(size: 15))
                .foregroundStyle(agreed ? Palette.accent : Palette.subtle)

            SectionTitle("Several of them")

            ForEach(Array(["Cheese", "Bacon", "Egg"].enumerated()), id: \.offset) { pair in
                let (index, name) = pair
                return Toggle(name, isOn: $extras[index])
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("checkBox.extra.\(index)")
                    .accessibilityLabel(name)
                    .tint(Palette.accent)
                    .font(.system(size: 15))
                    .id(name)
            }

            Text(chosen.isEmpty ? "Nothing extra" : "With \(chosen.joined(separator: ", "))")
                .font(.system(size: 15))
        }
        .spacing(12)
    }

    var notes: (any View)? {
        VStack {
            Text("`.toggleStyle(.checkbox)` gives a `Toggle` the box the "
                + "platform draws for one, caption and all - the words are "
                + "part of the control, so tapping them ticks it.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("Boxes are independent - tick as many as you like. One "
                + "choice out of several is a radio group, over in the "
                + "RadioButton sample.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(12)
    }

    /// What is ticked, in the order the boxes are drawn.
    private var chosen: [String] {
        ["Cheese", "Bacon", "Egg"].enumerated().filter { extras[$0.offset] }.map { $0.element }
    }
}
