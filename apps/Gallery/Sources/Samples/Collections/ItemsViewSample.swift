import SwiftOmniUI

/// A thousand rows, of which only the ones on screen are built.
private struct LongList: ExampleContent {
    @State private var chosen: Int?

    static let code = """
        @State private var chosen: Int?

        VStack {
            // One view per item, the item its identity - built as the
            // platform's own list shows it, never before.
            List(0..<1_000) { number in
                HStack {
                    Text("\\(number)").frame(width: 90)
                    Text("\\(number * number)")
                }
                .padding(EdgeInsets(14, 10))
            }
            .selection($chosen)
            .listStyle(.sidebar)
            .frame(maxHeight: .infinity)

            // Built again only for the choice: scrolling builds rows, never
            // the page.
            Text(chosen.map { "Row \\($0) is chosen." } ?? "Tap a row.")
        }
        """

    var body: some View {
        VStack(spacing: 10) {
            List(0..<1_000) { number in
                HStack {
                    Text("\(number)")
                        .font(.system(size: 14))
                        .frame(width: 90)

                    Text("\(number * number)")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.subtle)
                }
                .spacing(12)
                .padding(EdgeInsets(14, 10))
            }
            .selection($chosen)
            .listStyle(.sidebar)
            .frame(maxHeight: .infinity)

            Text(chosen.map { "Row \($0) is chosen." } ?? "Tap a row.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.accent)
        }
        // `.safeAreaInset` pins a bar to an edge of the WINDOW, over the
        // content - here a status strip along the bottom.
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text("\(chosen.map { "Row \($0)" } ?? "none")")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.subtle)
            }
            .padding(EdgeInsets(8, 4))
            .background(Palette.raised)
        }
    }

    var notes: (any View)? {
        Text("Scroll to the end, and tap a row to choose it.")
            .font(.system(size: 12))
            .foregroundStyle(Palette.subtle)
    }
}

/// Two strips running across: cards of one width, and tags as wide as their words.
private struct AcrossList: ExampleContent {
    static let tags = [
        "State", "Binding", "Journey", "Engine", "Animation", "Placement", "Environment", "Scene", "WindowScene",
        "Page", "Aim", "Style", "ColorScheme", "Gesture", "Frame", "Conversion", "Sample", "Identity", "Session",
        "Persistence",
    ]

    static let code = """
        VStack {

            // A row: one card beside another, each as wide as it says.
            ScrollView(.horizontal) {
                LazyHStack(alignment: .center, spacing: 8) {
                    ForEach(1...200) { number in
                        Text("Card \\(number)")
                            .multilineTextAlignment(.center)
                            .frame(width: 120)
                            .background(Palette.surface)
                    }
                }
            }
            .frame(height: 80)

            // Each tag as wide as its word.
            ScrollView(.horizontal) {
                LazyHStack(alignment: .center, spacing: 8) {
                    ForEach(tags) { tag in
                        Text(tag)
                            .padding(EdgeInsets(14, 0))
                            .background(Palette.raised)
                    }
                }
            }
            .frame(height: 40)
        }
        """

    var body: some View {
        VStack {

            ScrollView(.horizontal) {
                LazyHStack(alignment: .center, spacing: 8) {
                    ForEach(1...200) { number in
                        Text("Card \(number)")
                            .font(.system(size: 14))
                            .multilineTextAlignment(.center)
                            .frame(width: 120)
                            .background(Palette.surface)
                    }
                }
            }
            .frame(height: 80)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .center, spacing: 8) {
                    ForEach(Self.tags) { tag in
                        Text(tag)
                            .font(.system(size: 13))
                            .padding(EdgeInsets(14, 0))
                            .background(Palette.raised)
                    }
                }
            }
            .frame(height: 40)
        }
        .spacing(12)
    }

    var notes: (any View)? {
        Text("Swipe both strips: the cards share one width, and every tag is as wide as its word.")
            .font(.system(size: 12))
            .foregroundStyle(Palette.subtle)
    }
}

/// Tiles in as many columns as the width holds.
private struct GridList: ExampleContent {
    @State private var opened: Int?

    static let hues: [Color] = [.tomato, .orange, .teal, .steelBlue, .purple, .firebrick]

    static let code = """
        @State private var opened: Int?

        VStack {
            // Columns at least 100 wide: as many as the width holds.
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                    ForEach(0..<120) { number in
                        Text("\\(number)")
                            .frame(height: 72)
                            .frame(maxWidth: .infinity)
                            .background(hues[number % hues.count])
                            .onTapGesture { opened = number }
                    }
                }
            }
            .frame(maxHeight: .infinity)

            Text(opened.map { "Tile \\($0) opened." } ?? "Tap a tile.")
        }
        """

    var body: some View {
        VStack(spacing: 10) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                    ForEach(0..<120) { number in
                        Text("\(number)")
                            .font(.system(size: 15))
                            .bold()
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .frame(height: 72)
                            .frame(maxWidth: .infinity)
                            .background(Self.hues[number % Self.hues.count])
                            .onTapGesture { opened = number }
                    }
                }
            }
            .frame(maxHeight: .infinity)

            Text(opened.map { "Tile \($0) opened." } ?? "Tap a tile.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.accent)
        }
    }

    var notes: (any View)? {
        Text("Turn the device or widen the window: the columns follow the width.")
            .font(.system(size: 12))
            .foregroundStyle(Palette.subtle)
    }
}

/// The shapes a list takes: a thousand rows down the page, strips running across it, tiles in columns.
struct ItemsViewSample: SampleContent {
    static let id = "itemsView"
    static let title = "List"
    static let summary = "Only the items on screen are built - down, across or in columns."

    // Every example IS a scroller, so the page does not put one inside another, and each takes the window's height.
    static let scrolls = false
    static let fills = true

    var examples: [Example] {
        [
            Example(LongList()),
            Example(AcrossList()),
            Example(GridList()),
        ]
    }
}
