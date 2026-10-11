import SwiftOmniUI

/// One choice out of several, drawn as a group of radio buttons - a `Picker`
/// wearing `.radioGroup`.
struct RadioButtonSample: SampleContent, ExampleContent {
    @State private var size = "Medium"

    static let id = "radioButton"
    static let title = "RadioButton"
    static let summary = "One choice out of several - a Picker drawn as a radio group."

    static let code = """
        @State private var size = "Medium"

        VStack {
            // The chosen one is read here, so picking builds this closure.

            // A Picker IS the exclusive choice - .radioGroup is how the
            // platform draws it standing on the page.
            Picker("Size", selection: $size) {
                Text("Small").tag("Small")
                Text("Medium").tag("Medium")
                Text("Large").tag("Large")
            }
            .pickerStyle(.radioGroup)

            Text("Chosen: \\(size)")
        }
        """

    var body: some View {
        VStack {

            Picker("Size", selection: $size) {
                Text("Small").tag("Small")
                Text("Medium").tag("Medium")
                Text("Large").tag("Large")
            }
            .pickerStyle(.radioGroup)
            .accessibilityIdentifier("radio.size")
            .accessibilityLabel("Size")
            .font(.system(size: 15))

            Text("Chosen: \(size)")
                .font(.system(size: 17))
        }
        .spacing(12)
    }

    var notes: (any View)? {
        VStack {
            Text("Exclusivity is the Picker's, not the buttons': one `size` "
                + "state holds what is chosen and the group can only ever "
                + "show one of its entries on. `.pickerStyle(.radioGroup)` is "
                + "simply how that choice is drawn standing on the page.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("The same `Picker` wears `.menu`, `.segmented` or `.wheel` "
                + "elsewhere - the Picker sample compares them; this one is "
                + "about the radio look specifically.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(12)
    }
}
