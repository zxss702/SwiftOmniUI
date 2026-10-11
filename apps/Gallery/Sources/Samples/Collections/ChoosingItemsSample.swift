import SwiftOmniUI

/// Rows chosen by the handful, and the list scrolled to a row from code.
private struct PickList: ExampleContent {
    @State private var chosen: Set<Int> = []
    @Aim(ListContract.self) private var list

    static let code = """
        @State private var chosen: Set<Int> = []
        @Aim(ListContract.self) private var list

        Grid {
            HStack {
                Button("Top", action: { try await list.scrollTo(0, anchor: .start) })
                    
                Button("Row 500", action: { try await list.scrollTo(500, anchor: .start) })
                    
                Button("Clear", action: { chosen = [] })
                    .disabled(chosen.isEmpty)
                    
            }
            .gridRow(0)

            // A Set binding: as many chosen as the user likes.
            List(0..<1_000) { number in
                Text("Row \\(number)").padding(EdgeInsets(14, 10))
            }
            .selection($chosen)
            .aim(list)
            .gridRow(1)

            DebugInfoLabel()
                .gridRow(2)

            Text("\\(chosen.count) chosen")
                .gridRow(2)
        }
        .rows(.auto, .fill, .auto)
        """

    var body: some View {
        Grid {
            HStack {
                Button("Top", action: { try await list.scrollTo(0, anchor: .start) })
                    .font(.system(size: 13))
                    .padding(EdgeInsets(16, 6))
                    

                Button("Row 500", action: { try await list.scrollTo(500, anchor: .start) })
                    .font(.system(size: 13))
                    .padding(EdgeInsets(16, 6))
                    

                Button("Clear", action: { chosen = [] })
                    .font(.system(size: 13))
                    .padding(EdgeInsets(16, 6))
                    .disabled(chosen.isEmpty)
                    
            }
            .spacing(10)
            .horizontalAlignment(.center)
            .gridRow(0)

            List(0..<1_000) { number in
                Text("Row \(number)")
                    .font(.system(size: 14))
                    .padding(EdgeInsets(14, 10))
            }
            .selection($chosen)
            .aim(list)
            .gridRow(1)

            DebugInfoLabel()
                .gridRow(2)

            Text("\(chosen.count) chosen")
                .font(.system(size: 13))
                .foregroundStyle(Palette.accent)
                .gridRow(2)
        }
        .rows(.auto, .fill, .auto)
        .rowSpacing(10)
    }

    var notes: (any View)? {
        Text("Tap rows to choose several; Row 500 scrolls there.")
            .font(.system(size: 12))
            .foregroundStyle(Palette.subtle)
    }
}

/// Several rows chosen at once, and the list moved to a row from code.
struct ChoosingItemsSample: SampleContent {
    static let id = "choosingItems"
    static let title = "Choosing items"
    static let summary = "Rows chosen by the handful, and the list scrolled to a row from code."

    static let scrolls = false
    static let fills = true

    var examples: [Example] {
        [Example(PickList())]
    }
}
