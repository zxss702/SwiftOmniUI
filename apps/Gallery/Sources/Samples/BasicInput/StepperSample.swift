import SwiftOmniUI

/// A number stepped one at a time, and the same number stepped by five.
struct StepperSample: SampleContent, ExampleContent {
    @State private var servings = 4.0

    static let id = "stepper"
    static let title = "Stepper"
    static let summary = "A number tapped one step at a time, where a slider is dragged to about right."

    static let code = """
        @State private var servings = 4.0

        VStack {
            // The count is read here, so every step builds this closure.

            Text("Servings: \\(Int(servings))")

            Stepper($servings, in: 1...12)

            // The same value, stepped by five - the stride told in the
            // initializer.
            Stepper($servings, in: 1...12, step: 5)
        }
        """

    var body: some View {
        VStack {

            Text("Servings: \(Int(servings))")
                .font(.system(size: 22))
                .multilineTextAlignment(.center)

            Stepper($servings, in: 1...12)
                .accessibilityIdentifier("stepper.servings")
                .accessibilityLabel("Servings")

            SectionTitle("A bigger step")

            Stepper($servings, in: 1...12, step: 5)
                .accessibilityIdentifier("stepper.servings.bigStep")
                .accessibilityLabel("Servings, five at a time")
        }
        .spacing(12)
    }

    var notes: (any View)? {
        VStack {
            Text("A `Stepper` is a `Slider` for a value with few enough steps to name. This "
                + "one goes from 1 to 12 and never lands between two servings - which is "
                + "what a stepper is for.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("The second holds the same value, stepped by five: `step` is how far "
                + "one tap goes, and the range is where the buttons stop.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(12)
    }
}
