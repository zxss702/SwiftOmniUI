import SwiftOmniUI

/// Dots marking a place in a sequence: their shape, their cap and a lone one.
struct PositionIndicatorSample: SampleContent, ExampleContent {
    @State private var step = 0
    @State private var cap = 5.0

    static let id = "positionIndicator"
    static let title = "PositionIndicator"
    static let summary = "A place in a sequence, drawn as dots - with or without a run of cards."

    static let code = """
        @State private var step = 0
        @State private var cap = 5.0

        private static let steps = ["Describe", "Diff", "Send", "Render"]

        VStack {
            // The step is read here, so moving between pages builds this
            // closure - one build a page, whatever the movement costs.
            DebugInfoLabel()

            Text(Self.steps[step])

            PositionIndicator()
                .count(Self.steps.count)
                .position(step)
                .indicatorColor(Palette.outline)
                .selectedIndicatorColor(Palette.accent)

            PositionIndicator()
                .count(Self.steps.count)
                .position(step)
                .indicatorsShape(.square)
                .indicatorColor(Palette.outline)
                .selectedIndicatorColor(Palette.accent)

            HStack {
                Button("Back", action: { step -= 1 })
                    .disabled(step <= 0)
                    

                Button("Next", action: { step += 1 })
                    .disabled(step >= Self.steps.count - 1)
                    
            }

            // Twelve items twice, at two caps. `maximumVisible` is a ceiling
            // on the DOTS and not on the items: `count` is twelve in both
            // rows, and the stepper takes the second row's dots away one at a
            // time.
            Text("Twelve items, maximumVisible(12)")

            PositionIndicator()
                .count(12)
                .position(step)
                .maximumVisible(12)
                .indicatorColor(Palette.outline)
                .selectedIndicatorColor(Palette.accent)

            Text("The same twelve, maximumVisible(\\(Int(cap)))")

            PositionIndicator()
                .count(12)
                .position(step)
                .maximumVisible(Int(cap))
                .indicatorColor(Palette.outline)
                .selectedIndicatorColor(Palette.accent)

            Stepper($cap, in: 4...12)

            // One item twice. `hideSingle` is true by default, so the
            // left-hand one draws NOTHING at all - a lone dot says nothing
            // about where the user is - and the right-hand one asks for it.
            HStack {
                VStack {
                    Text("hideSingle(true)")

                    PositionIndicator()
                        .count(1)
                        .position(0)
                        .hideSingle(true)
                        .indicatorColor(Palette.outline)
                        .selectedIndicatorColor(Palette.accent)
                }

                VStack {
                    Text("hideSingle(false)")

                    PositionIndicator()
                        .count(1)
                        .position(0)
                        .hideSingle(false)
                        .indicatorColor(Palette.outline)
                        .selectedIndicatorColor(Palette.accent)
                }
            }
        }
        """

    private static let steps = ["Describe", "Diff", "Send", "Render"]

    var body: some View {
        VStack {
            DebugInfoLabel()

            Text(Self.steps[step])
                .font(.system(size: 20))
                .bold()
                .multilineTextAlignment(.center)

            PositionIndicator()
                .count(Self.steps.count)
                .position(step)
                .indicatorColor(Palette.outline)
                .selectedIndicatorColor(Palette.accent)
                .horizontalAlignment(.center)

            PositionIndicator()
                .count(Self.steps.count)
                .position(step)
                .indicatorsShape(.square)
                .indicatorColor(Palette.outline)
                .selectedIndicatorColor(Palette.accent)
                .horizontalAlignment(.center)

            HStack {
                Button("Back", action: { step -= 1 })
                    .font(.system(size: 13))
                    .padding(EdgeInsets(16, 6))
                    .disabled(step <= 0)
                    

                Button("Next", action: { step += 1 })
                    .font(.system(size: 13))
                    .padding(EdgeInsets(16, 6))
                    .disabled(step >= Self.steps.count - 1)
                    
            }
            .spacing(10)
            .horizontalAlignment(.center)

            // Twelve items twice, at two caps. `maximumVisible` is a ceiling
            // on the DOTS and not on the items: `count` is twelve in both
            // rows, and the stepper takes the second row's dots away one at a
            // time.
            Text("Twelve items, maximumVisible(12)")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
                .horizontalAlignment(.center)

            PositionIndicator()
                .count(12)
                .position(step)
                .maximumVisible(12)
                .indicatorColor(Palette.outline)
                .selectedIndicatorColor(Palette.accent)
                .horizontalAlignment(.center)

            Text("The same twelve, maximumVisible(\(Int(cap)))")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
                .horizontalAlignment(.center)

            PositionIndicator()
                .count(12)
                .position(step)
                .maximumVisible(Int(cap))
                .indicatorColor(Palette.outline)
                .selectedIndicatorColor(Palette.accent)
                .horizontalAlignment(.center)

            Stepper($cap, in: 4...12)
                .accessibilityIdentifier("positionIndicator.cap")
                .accessibilityLabel("How many dots")
                .horizontalAlignment(.center)

            // One item twice. `hideSingle` is true by default, so the
            // left-hand one draws NOTHING at all - a lone dot says nothing
            // about where the user is - and the right-hand one asks for it.
            HStack {
                VStack {
                    Text("hideSingle(true)")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.subtle)
                        .multilineTextAlignment(.center)

                    PositionIndicator()
                        .count(1)
                        .position(0)
                        .hideSingle(true)
                        .indicatorColor(Palette.outline)
                        .selectedIndicatorColor(Palette.accent)
                        .horizontalAlignment(.center)
                }
                .spacing(6)

                VStack {
                    Text("hideSingle(false)")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.subtle)
                        .multilineTextAlignment(.center)

                    PositionIndicator()
                        .count(1)
                        .position(0)
                        .hideSingle(false)
                        .indicatorColor(Palette.outline)
                        .selectedIndicatorColor(Palette.accent)
                        .horizontalAlignment(.center)
                }
                .spacing(6)
            }
            .spacing(32)
            .horizontalAlignment(.center)
        }
        .spacing(12)
    }

    var notes: (any View)? {
        VStack {
            Text("The usual home for one is under a GalleryView. Both take a `position`, so "
                + "one @State joins them - which is also what makes a PositionIndicator useful "
                + "on its own, as above.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("Nothing about it is the user's to change, so there is no binding "
                + "overload - `position` is told to it.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("`maximumVisible` is a ceiling on the DOTS: both rows above say "
                + "`count(12)`, and only the number drawn moves as the stepper does - "
                + "which is what keeps a long sequence's dots a readable width.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("`hideSingle` is true by default, which is why an indicator over a "
                + "ONE-item list draws nothing at all: a lone dot says nothing about where "
                + "the user is. The two columns above are that same one-item indicator, "
                + "both ways round.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(8)
    }
}
