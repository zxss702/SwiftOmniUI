import SwiftOmniUI

/// A column of a thousand rows, only a window's worth of which exist.
///
/// The counter under the scroller is the measure the sample is about: a row
/// says `onAppear` as its subtree is mounted and `onDisappear` as the host
/// lets it go, so the number standing is the window's reach, not the data's
/// length. Deleting writes the data - the row's identity goes with it, which
/// is what makes it a different list rather than a longer one.
private struct LazyRows: ExampleContent {
    /// Which rows have been deleted.
    @State private var gone: Set<Int> = []

    /// How many rows' subtrees are mounted right now.
    @State private var standing = 0

    static let code = """
        @State private var gone: Set<Int> = []
        @State private var standing = 0

        // The rows still in the list - deleting writes the DATA, and the
        // row's identity goes with it.
        let shown = (0..<1_000).filter { !gone.contains($0) }

        VStack {
            Text("\\(standing) standing of \\(shown.count)")

            ScrollView {
                // Static children mix with the rows: the header and the end
                // mark are ordinary children of the same stack.
                LazyVStack(spacing: 8) {
                    Text("- the top -")

                    ForEach(shown) { row in
                        Grid {
                            Text("Row \\(row)").gridColumn(0)
                            Button("Delete", action: { gone.insert(row) })
                                .gridColumn(1)
                        }
                        .columns(.fill, .auto)
                        // The count is a reading taken as the host mounts and
                        // lets go - the window's reach is all that exists.
                        .onAppear { standing += 1 }
                        .onDisappear { standing -= 1 }
                        .animation(.inherited)
                    }

                    Text("- the end -")
                }
            }
        }
        """

    var body: some View {
        let shown = (0..<1_000).filter { !gone.contains($0) }

        VStack {
            Text("\(standing) standing of \(shown.count)")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Palette.accent)

            ScrollView {
                LazyVStack(spacing: 8) {
                    Text("- the top -")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.subtle)

                    ForEach(shown) { row in
                        Grid {
                            Text("Row \(row)")
                                .font(.system(size: 14))
                                .verticalAlignment(.center)
                                .gridColumn(0)

                            Button("Delete", action: { gone.insert(row) })
                                .font(.system(size: 12))
                                .padding(EdgeInsets(10, 4))
                                .gridColumn(1)
                        }
                        .columns(.fill, .auto)
                        .padding(EdgeInsets(14, 4))
                        .background(Palette.raised)
                        .onAppear { standing += 1 }
                        .onDisappear { standing -= 1 }
                        .animation(.inherited)
                    }

                    Text("- the end -")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.subtle)
                }
            }
        }
        .spacing(10)
    }

    var notes: (any View)? {
        VStack {
            Text("A `LazyVStack` in a `ScrollView` builds a row's subtree only when "
                + "the window the scroller shows reaches it - and lets it go when it "
                + "leaves. The counter is the proof on the screen: of a thousand rows "
                + "a window's worth stand at once, and scrolling asks the rows it "
                + "moves to to appear.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("The scroll room is the whole thousand before most of them exist: "
                + "the unbuilt rows' room is stood for by the measure of the ones "
                + "held, so the thumb is honest from the first moment.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("A `ForEach` row is named by its item's identity - deleting writes "
                + "the data and the row's identity leaves with it, so the stack "
                + "closes over the gap the way `Removing a row` shows a plain one "
                + "doing. Static children mix in freely: the two marks are ordinary "
                + "children of the same stack.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(12)
    }
}

/// The same laziness across - a row of tiles only a window's worth of which
/// exist.
private struct LazyTiles: ExampleContent {
    @State private var standing = 0

    static let code = """
        @State private var standing = 0

        VStack {
            Text("\\(standing) standing of 200")

            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(1...200) { tile in
                        Text("Tile \\(tile)")
                            .frame(width: 140)
                            .frame(height: 160)
                            .onAppear { standing += 1 }
                            .onDisappear { standing -= 1 }
                    }
                }
            }
        }
        """

    var body: some View {
        VStack {
            Text("\(standing) standing of 200")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Palette.accent)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(1...200) { tile in
                        Text("Tile \(tile)")
                            .font(.system(size: 14))
                            .verticalAlignment(.center)
                            .frame(width: 140)
                            .frame(height: 160)
                            .background(Palette.surface)
                            .onAppear { standing += 1 }
                            .onDisappear { standing -= 1 }
                    }
                }
            }
            .frame(height: 200)
        }
        .spacing(10)
    }

    var notes: (any View)? {
        Text("`LazyHStack` is the same window across: a horizontal `ScrollView` "
            + "asks for the tiles in reach and no more. Drag it - the count moves "
            + "a window at a time.")
            .font(.system(size: 12))
            .foregroundStyle(Palette.subtle)
    }
}

/// Shelves in a column - a lazy stack whose rows each hold a lazy stack of
/// their own, the pattern a photo app's albums are cut from.
///
/// Each shelf's scroller gives its `LazyHStack` a window of its own, so a
/// shelf builds its tiles only while the shelf itself stands: a tile neither
/// the column nor its shelf reaches exists at all.
private struct LazyShelves: ExampleContent {
    @State private var standing = 0

    static let code = """
        @State private var standing = 0

        ScrollView {
            LazyVStack(spacing: 18) {
                ForEach(0..<24) { shelf in
                    Shelf(number: shelf, standing: $standing)
                }
            }
        }

        // One shelf: a title and a lazy row of tiles with a window of its own.
        struct Shelf: View {
            let number: Int
            @Binding var standing: Int

            var body: some View {
                VStack {
                    Text("Shelf \\(number)")

                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 8) {
                            ForEach(0..<40) { tile in
                                Text("\\(number).\\(tile)")
                                    .frame(width: 96)
                                    .frame(height: 72)
                                    .onAppear { standing += 1 }
                                    .onDisappear { standing -= 1 }
                            }
                        }
                    }
                    .frame(height: 88)
                }
            }
        }
        """

    var body: some View {
        VStack {
            Text("\(standing) tiles standing")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Palette.accent)

            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(0..<24) { shelf in
                        Shelf(number: shelf, standing: $standing)
                    }
                }
            }
        }
        .spacing(10)
    }

    var notes: (any View)? {
        VStack {
            Text("Nested lazy stacks each narrow by their own window: the column "
                + "mounts only the shelves in reach, and a shelf mounts only the "
                + "tiles in ITS reach. A tile neither window reaches is never built.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("Drag a shelf sideways and the tiles come into existence under the "
                + "finger; scroll down and whole shelves let theirs go. The count is "
                + "both windows' worth, nothing more.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(12)
    }
}

/// A lazy shelf - its header is an ordinary child of the shelf, its tiles a
/// `LazyHStack` narrowed by the shelf's own scroller.
private struct Shelf: View {
    let number: Int
    @Binding var standing: Int

    var body: some View {
        VStack {
            Text("Shelf \(number)")
                .font(.system(size: 12))
                .bold()
                .foregroundStyle(Palette.subtle)
                .horizontalAlignment(.start)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 8) {
                    ForEach(0..<40) { tile in
                        Text("\(number).\(tile)")
                            .font(.system(size: 12))
                            .verticalAlignment(.center)
                            .frame(width: 96)
                            .frame(height: 72)
                            .background(Palette.surface)
                            .onAppear { standing += 1 }
                            .onDisappear { standing -= 1 }
                    }
                }
            }
            .frame(height: 88)
        }
    }
}

/// A grid whose cells are built a row at a time - `.adaptive` columns, so the
/// window's width decides how many.
private struct LazyCells: ExampleContent {
    @State private var standing = 0

    static let code = """
        @State private var standing = 0

        VStack {
            Text("\\(standing) standing of 500")

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 96), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(0..<500) { cell in
                        Text("\\(cell)")
                            .frame(height: 64)
                            .onAppear { standing += 1 }
                            .onDisappear { standing -= 1 }
                    }
                }
            }
        }
        """

    var body: some View {
        VStack {
            Text("\(standing) standing of 500")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Palette.accent)

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 96), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(0..<500) { cell in
                        Text("\(cell)")
                            .font(.system(size: 13))
                            .verticalAlignment(.center)
                            .frame(height: 64)
                            .frame(maxWidth: .infinity)
                            .background(Palette.surface)
                            .onAppear { standing += 1 }
                            .onDisappear { standing -= 1 }
                    }
                }
            }
        }
        .spacing(10)
    }

    var notes: (any View)? {
        VStack {
            Text("`LazyVGrid` fills its columns row first and realizes a row at a "
                + "time: an `.adaptive` column stands for as many as fit the room, "
                + "so making the window wider puts more cells in a row - and the "
                + "same count of rows in reach.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("`LazyHGrid` is the same grid across - it fills its rows column "
                + "first inside a horizontal scroller.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(12)
    }
}

/// The lazy containers: stacks and grids whose children exist only where the
/// window reaches.
struct LazyStacksSample: SampleContent {
    static let id = "lazyStacks"
    static let title = "Lazy stacks & grids"
    static let summary = "LazyVStack, LazyHStack, LazyVGrid - children built where the window "
        + "reaches, and let go where it leaves."

    // Every example here IS a scroller, so the page must not put one inside
    // another: the wrong one moves under the user's finger, and a scroller
    // inside a scroller cannot be given a height worth having.
    static let scrolls = false

    /// Each example is given the WINDOW's height, which is what a scroller
    /// needs to be worth dragging.
    static let fills = true

    var examples: [Example] {
        [Example(LazyRows()), Example(LazyTiles()), Example(LazyShelves()), Example(LazyCells())]
    }
}
