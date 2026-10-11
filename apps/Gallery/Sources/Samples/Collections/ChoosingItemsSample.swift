import SwiftOmniUI

/// Rows chosen by the handful: a Set binding holds as many as the user picks.
private struct PickList: ExampleContent {
    @State private var chosen: Set<Int> = []

    static let code = """
        @State private var chosen: Set<Int> = []

        VStack {
            // A Set binding: as many chosen as the user likes.
            List(0..<1_000) { number in
                Text("Row \\(number)").padding(EdgeInsets(14, 10))
            }
            .selection($chosen)
            .frame(maxHeight: .infinity)

            HStack {
                Button("Clear") { chosen = [] }
                    .disabled(chosen.isEmpty)

                Text("\\(chosen.count) chosen")
            }
        }
        """

    var body: some View {
        VStack(spacing: 10) {
            List(0..<1_000) { number in
                Text("Row \(number)")
                    .font(.system(size: 14))
                    .padding(EdgeInsets(14, 10))
            }
            .selection($chosen)
            .frame(maxHeight: .infinity)

            HStack {
                Button("Clear", action: { chosen = [] })
                    .font(.system(size: 13))
                    .padding(EdgeInsets(16, 6))
                    .disabled(chosen.isEmpty)

                Text("\(chosen.count) chosen")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.accent)
            }
            .spacing(10)
        }
    }

    var notes: (any View)? {
        Text("Tap rows to choose them, and Clear to let them all go. "
            + "A `Set` binding says choosing more than one is allowed.")
            .font(.system(size: 12))
            .foregroundStyle(Palette.subtle)
    }
}

/// Rows chosen by the handful.
struct ChoosingItemsSample: SampleContent {
    static let id = "choosingItems"
    static let title = "Choosing items"
    static let summary = "Rows chosen by the handful - a Set binding holds them all."

    static let scrolls = false
    static let fills = true

    var examples: [Example] {
        [Example(PickList())]
    }
}
