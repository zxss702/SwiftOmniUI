import SwiftOmniUI

/// Two bars over one job: how much of it is done, and how much is left.
struct ProgressBarSample: SampleContent, ExampleContent {
    @State private var done = 3.0

    static let id = "progressBar"
    static let title = "ProgressBar"
    static let summary = "How far along something is, as a fraction from 0 to 1."

    static let code = """
        @State private var done = 3.0

        /// How many steps the imaginary job has.
        private var steps: Double { 5 }

        VStack {
            // How far along is read here, so every step builds this closure.

            Text("Step \\(Int(done)) of \\(Int(steps))")

            // A FRACTION, not a count: the division happens here, in Swift,
            // because that is where the numbers are.
            ProgressView(done / steps)
                .frame(height: 8)

            Stepper($done, in: 0...steps, step: 1)

            // The same state said the other way: what is LEFT, so the two
            // bars move opposite ways.
            ProgressView(1 - done / steps)
                .frame(height: 8)
        }
        """

    var body: some View {
        VStack {

            Text("Step \(Int(done)) of \(Int(steps))")
                .font(.system(size: 17))
                .multilineTextAlignment(.center)

            ProgressView(done / steps)
                .tint(Palette.accent)
                .frame(height: 8)

            Stepper($done, in: 0...steps, step: 1)
                .accessibilityIdentifier("progressBar.done")
                .accessibilityLabel("Work done")

            SectionTitle("The same property, as a modifier")

            ProgressView(1 - done / steps)
                .tint(Palette.subtle)
                .frame(height: 8)

        }
        .spacing(12)
    }

    var notes: (any View)? {
        VStack {
            Text("A FRACTION, not a percentage and not a count: 0.4 is four tenths of the "
                + "way through, whatever the work is measured in. The step count is divided "
                + "in Swift, because that is where the numbers are. A value outside 0 to 1 "
                + "is clamped, so a bar is never drawn more than full.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("The value is set in the initializer - `ProgressView(0.4)` - like "
                + "`Toggle(isOn: $on)` or `Path(\"M 28,0 ...\")`. This one shows what is "
                + "LEFT to do, so the two bars move opposite ways as the stepper is "
                + "tapped.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(12)
    }

    /// How many steps the imaginary job has.
    private var steps: Double { 5 }
}
