import SwiftOmniUI

/// A thousand rows, of which only the ones on screen are built.
private struct LongList: ExampleContent {
    @State private var chosen: Int?

    static let code = """
        @State private var chosen: Int?

        Grid {
            // One view per item, the item its identity - built as the
            // platform's own list shows it, never before.
            List(0..<1_000) { number in
                HStack {
                    Text("\\(number)").frame(width: 90)
                    Text("\\(number * number)")
                }
                .padding(EdgeInsets(14, 10))
            }
            .header(Text("N and N², a thousand times"))
            .footer(Text("That is all of them."))
            .selection($chosen)
            .listStyle(.sidebar)
            .gridRow(0)

            // Built again only for the choice: scrolling builds rows, never
            // the page.
            DebugInfoLabel()
                .gridRow(1)

            Text(chosen.map { "Row \\($0) is chosen." } ?? "Tap a row.")
                .gridRow(1)
        }
        .rows(.fill, .auto)
        """

    var body: some View {
        Grid {
            List(0..<1_000) { number in
                HStack {
                    Text("\(number)")
                        .font(.system(size: 14))
                        .frame(width: 90)
                        .verticalAlignment(.center)

                    Text("\(number * number)")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.subtle)
                        .verticalAlignment(.center)
                }
                .spacing(12)
                .padding(EdgeInsets(14, 10))
            }
            .header(Text("N and N², a thousand times")
                .font(.system(size: 11))
                .bold()
                .foregroundStyle(Palette.subtle)
                .padding(EdgeInsets(14, 8))
                .background(Palette.raised))
            .footer(Text("That is all of them.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
                .padding(EdgeInsets(14, 8)))
            .selection($chosen)
            .listStyle(.sidebar)
            .gridRow(0)

            DebugInfoLabel()
                .gridRow(1)

            Text(chosen.map { "Row \($0) is chosen." } ?? "Tap a row.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.accent)
                .gridRow(1)
        }
        .rows(.fill, .auto)
        .rowSpacing(10)
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
            DebugInfoLabel()

            // A row: one card beside another, each as wide as it says.
            List(1...200) { number in
                Text("Card \\(number)")
                    .multilineTextAlignment(.center)
                    .verticalTextAlignment(.center)
                    .frame(width: 120)
                    .background(Palette.surface)
            }
            .itemsLayout(.row(spacing: 8))
            .frame(height: 80)

            // Each tag as wide as its word.
            List(tags) { tag in
                Text(tag)
                    .padding(EdgeInsets(14, 0))
                    .verticalTextAlignment(.center)
                    .background(Palette.raised)
            }
            .itemsLayout(.row(spacing: 8))
            .frame(height: 40)
        }
        """

    var body: some View {
        VStack {
            DebugInfoLabel()

            List(1...200) { number in
                Text("Card \(number)")
                    .font(.system(size: 14))
                    .multilineTextAlignment(.center)
                    .verticalTextAlignment(.center)
                    .frame(width: 120)
                    .background(Palette.surface)
            }
            .itemsLayout(.row(spacing: 8))
            .frame(height: 80)

            List(Self.tags) { tag in
                Text(tag)
                    .font(.system(size: 13))
                    .padding(EdgeInsets(14, 0))
                    .verticalTextAlignment(.center)
                    .background(Palette.raised)
            }
            .itemsLayout(.row(spacing: 8))
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

        Grid {
            // Columns at least 100 wide: as many as the width holds.
            List(0..<120) { number in
                Text("\\(number)")
                    .multilineTextAlignment(.center)
                    .verticalTextAlignment(.center)
                    .frame(height: 72)
                    .background(hues[number % hues.count])
            }
            .itemsLayout(.grid(minimumItemWidth: 100, spacing: 8))
            .onItemActivated { opened = $0 }
            .gridRow(0)

            DebugInfoLabel()
                .gridRow(1)

            Text(opened.map { "Tile \\($0) opened." } ?? "Tap a tile.")
                .gridRow(1)
        }
        .rows(.fill, .auto)
        """

    var body: some View {
        Grid {
            List(0..<120) { number in
                Text("\(number)")
                    .font(.system(size: 15))
                    .bold()
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .verticalTextAlignment(.center)
                    .frame(height: 72)
                    .background(Self.hues[number % Self.hues.count])
            }
            .itemsLayout(.grid(minimumItemWidth: 100, spacing: 8))
            .onItemActivated { opened = $0 }
            .gridRow(0)

            DebugInfoLabel()
                .gridRow(1)

            Text(opened.map { "Tile \($0) opened." } ?? "Tap a tile.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.accent)
                .gridRow(1)
        }
        .rows(.fill, .auto)
        .rowSpacing(10)
    }

    var notes: (any View)? {
        Text("Turn the device or widen the window: the columns follow the width.")
            .font(.system(size: 12))
            .foregroundStyle(Palette.subtle)
    }
}

/// Items under headings of their own, with a count under each group.
private struct GroupedList: ExampleContent {
    @State private var counts = true

    struct Shelf {
        let name: String
        let items: [String]
    }

    static let shelves = [
        Shelf(name: "Fruit", items: ["Apple", "Pear", "Plum", "Cherry", "Quince", "Apricot"]),
        Shelf(name: "Vegetables", items: ["Leek", "Carrot", "Parsnip", "Beetroot", "Celery"]),
        Shelf(name: "Bakery", items: ["Rye loaf", "Bagel", "Croissant", "Pretzel"]),
        Shelf(name: "Dairy", items: ["Butter", "Kefir", "Cheddar", "Quark", "Cream", "Yoghurt"]),
        Shelf(name: "Pantry", items: ["Rice", "Lentils", "Flour", "Oats", "Honey", "Salt"]),
        Shelf(name: "Drinks", items: ["Water", "Tea", "Coffee", "Juice"]),
    ]

    static let code = """
        @State private var counts = true

        Grid {
            SwitchRow("Counts", $counts)
                .gridRow(0)

            DebugInfoLabel()
                .gridRow(0)

            // A group per shelf, named so two shelves may hold the same item.
            List(groups: shelves.map { shelf in
                let group = ItemsGroup(shelf.items) { item in
                    Text(item).padding(EdgeInsets(14, 10))
                }
                .id(shelf.name)
                .header(Text(shelf.name).bold().padding(EdgeInsets(14, 8)))

                return counts
                    ? group.footer(Text("\\(shelf.items.count) items").padding(EdgeInsets(14, 6)))
                    : group
            })
            .gridRow(1)
        }
        .rows(.auto, .fill)
        """

    var body: some View {
        Grid {
            SwitchRow("Counts", $counts)
                .gridRow(0)

            DebugInfoLabel()
                .gridRow(0)

            List(groups: Self.shelves.map { (shelf: Shelf) -> ItemsGroup<[String], String> in
                let group = ItemsGroup(shelf.items) { item in
                    Text(item)
                        .font(.system(size: 14))
                        .padding(EdgeInsets(14, 10))
                }
                .id(shelf.name)
                .header(Text(shelf.name)
                    .font(.system(size: 12))
                    .bold()
                    .foregroundStyle(Palette.subtle)
                    .padding(EdgeInsets(14, 8))
                    .background(Palette.raised))

                return counts
                    ? group.footer(Text("\(shelf.items.count) items")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.subtle)
                        .padding(EdgeInsets(14, 6)))
                    : group
            })
            .gridRow(1)
        }
        .rows(.auto, .fill)
        .rowSpacing(10)
    }

    var notes: (any View)? {
        Text("Turn Counts off: the groups close up where their footers stood.")
            .font(.system(size: 12))
            .foregroundStyle(Palette.subtle)
    }
}

/// The shapes a list takes: a thousand rows down the page, strips running across it, tiles in columns, and items under
/// headings of their own.
struct ItemsViewSample: SampleContent {
    static let id = "itemsView"
    static let title = "List"
    static let summary = "Only the items on screen are built - down, across, in columns or in groups."

    // Every example IS a scroller, so the page does not put one inside another, and each takes the window's height.
    static let scrolls = false
    static let fills = true

    var examples: [Example] {
        [
            Example(LongList()),
            Example(AcrossList()),
            Example(GridList()),
            Example(GroupedList()),
        ]
    }
}
