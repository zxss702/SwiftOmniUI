import SwiftOmniUI

/// A list that asks for thirty more as the user nears its end.
private struct LoadingList: ExampleContent {
    @State private var count = 30
    @State private var loading = false

    static let code = """
        @State private var count = 30
        @State private var loading = false

        Grid {
            HStack {
                Text(loading ? "Loading" : "\\(count) items")
                Button("Start over", action: { count = 30 })
                    .disabled(count <= 30)
                    
            }
            .gridRow(0)

            DebugInfoLabel()
                .gridRow(0)

            List(0..<count) { number in
                Text("Item \\(number + 1)").padding(EdgeInsets(14, 10))
            }
            // Within five items of the end, thirty more - once each time.
            .onEndReached(within: 5) {
                guard !loading, count < 300 else { return }

                loading = true
                try await Task.sleep(for: .milliseconds(400))
                count += 30
                loading = false
            }
            .gridRow(1)
        }
        .rows(.auto, .fill)
        """

    var body: some View {
        Grid {
            HStack {
                Text(loading ? "Loading" : "\(count) items")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.accent)
                    .verticalAlignment(.center)

                Button("Start over", action: { count = 30 })
                    .font(.system(size: 13))
                    .padding(EdgeInsets(16, 6))
                    .disabled(count <= 30)
                    
            }
            .spacing(12)
            .gridRow(0)

            DebugInfoLabel()
                .gridRow(0)

            List(0..<count) { number in
                Text("Item \(number + 1)")
                    .font(.system(size: 14))
                    .padding(EdgeInsets(14, 10))
            }
            .onEndReached(within: 5) {
                guard !loading, count < 300 else { return }

                loading = true
                try await Task.sleep(for: .milliseconds(400))
                count += 30
                loading = false
            }
            .gridRow(1)
        }
        .rows(.auto, .fill)
        .rowSpacing(10)
        // `.task` starts as the view appears and is cancelled as it leaves -
        // here it stands in for the first page of a feed, fetched on show.
        .task {
            loading = true
            try? await Task.sleep(for: .milliseconds(600))
            loading = false
        }
    }

    var notes: (any View)? {
        Text("Scroll towards the end: thirty more arrive, up to three hundred. "
            + "The first fetch is a `.task` - it would be cancelled if the "
            + "page left before it answered.")
            .font(.system(size: 12))
            .foregroundStyle(Palette.subtle)
    }
}

/// A list that grows as the user reads.
struct LoadingItemsSample: SampleContent {
    static let id = "loadingItems"
    static let title = "Loading more items"
    static let summary = "A list that asks for more as the user nears its end."

    static let scrolls = false
    static let fills = true

    var examples: [Example] {
        [Example(LoadingList())]
    }
}
