import SwiftOmniUI

/// A strip of tiles a fixed distance apart - the shape the horizontal scroller
/// below is cut from.
private func tileStrip() -> some View {
    ScrollView(.horizontal) {
        HStack {
            ForEach(1...40) { tile in
                Text("Tile \(tile)")
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                    .frame(width: 140)
                    .frame(height: 100)
                    .background(Palette.surface)
            }
        }
        .spacing(20)
    }
    .scrollIndicators(.hidden, axes: .horizontal)
}

/// Forty numbered lines - the same strip wherever one is needed below.
private func numberedLines() -> some View {
    ScrollView {
        VStack {
            ForEach(1...40) { line in
                Text("Line \(line)")
                    .font(.system(size: 14))
                    .padding(EdgeInsets(8, 6))
            }
        }
    }
}

/// The heading over one column.
private func columnTitle(_ text: String) -> Text {
    Text(text)
        .font(.system(size: 12))
        .bold()
        .foregroundStyle(Palette.subtle)
        .multilineTextAlignment(.center)
}

/// A vertical scroller and a horizontal one - the two directions a ScrollView
/// takes.
private struct Directions: ExampleContent {
    static let code = """
        VStack {
            // Down the page, by default.
            ScrollView {
                VStack {
                    ForEach(1...40) { line in
                        Text("Line \\(line)")
                            .padding(EdgeInsets(8, 6))
                    }
                }
            }
            .frame(maxHeight: .infinity)

            // Across it, asked for with `.horizontal`.
            ScrollView(.horizontal) {
                HStack {
                    ForEach(1...40) { tile in
                        Text("Tile \\(tile)")
                            .frame(width: 140)
                            .frame(height: 100)
                    }
                }
                .spacing(20)
            }
            .frame(height: 100)
            .scrollIndicators(.hidden, axes: .horizontal)
        }
        """

    var body: some View {
        VStack(spacing: 12) {
            columnTitle("VERTICAL")

            numberedLines()
                .frame(maxHeight: .infinity)

            columnTitle("HORIZONTAL - BAR HIDDEN")

            tileStrip()
                .frame(height: 100)
        }
    }

    var notes: (any View)? {
        VStack {
            Text("A ScrollView holds one view and scrolls it; several children are "
                + "wrapped in a stack. `ScrollView(.horizontal)` runs the other way, "
                + "and `.scrollIndicators(.hidden, axes:)` takes its bar away.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("The strip above has no bar: drag it, and the tiles move with "
                + "nothing at the edge to say so.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(8)
    }
}

/// A scroller moved from code: the buttons ask a proxy for a row by its
/// identity.
private struct ReaderStrip: ExampleContent {
    static let code = """
        VStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack {
                        ForEach(1...40) { line in
                            Text("Line \\(line)")
                                .padding(EdgeInsets(8, 6))
                        }
                    }
                }
                .frame(maxHeight: .infinity)

                HStack {
                    Button("Top") { proxy.scrollTo(1) }
                    Button("Line 20") { proxy.scrollTo(20) }
                    Button("End") { proxy.scrollTo(40) }
                }
            }
        }
        """

    var body: some View {
        VStack(spacing: 10) {
            columnTitle("MOVED FROM CODE")

            ScrollViewReader { proxy in
                numberedLines()
                    .frame(maxHeight: .infinity)

                HStack {
                    Button("Top", action: { proxy.scrollTo(1) })
                        .font(.system(size: 13))
                        .padding(EdgeInsets(16, 6))

                    Button("Line 20", action: { proxy.scrollTo(20) })
                        .font(.system(size: 13))
                        .padding(EdgeInsets(16, 6))

                    Button("End", action: { proxy.scrollTo(40) })
                        .font(.system(size: 13))
                        .padding(EdgeInsets(16, 6))
                }
                .spacing(16)
            }
        }
    }

    var notes: (any View)? {
        VStack {
            Text("`ScrollViewReader` hands the buttons a proxy, and `scrollTo` asks "
                + "for a row by the identity it was given - here, by its number.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("The proxy is not a state: nothing is written anywhere, and no "
                + "view is built again for the movement.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(8)
    }
}

/// The bar down the side, asked for and taken away.
private struct BarStrips: ExampleContent {
    static let code = """
        struct BarStrips: View {
            var body: some View {
                HStack {
                    barCase(.visible)
                    barCase(.hidden)
                }
                .spacing(12)
            }

            private func barCase(_ visibility: ScrollIndicatorVisibility) -> some View {
                ScrollView {
                    VStack {
                        ForEach(1...40) { line in
                            Text("Line \\(line)")
                                .padding(EdgeInsets(6, 4))
                        }
                    }
                }
                .scrollIndicators(visibility, axes: .vertical)
            }
        }
        """

    var body: some View {
        HStack(spacing: 12) {
            barCase(.visible, "scrollIndicators(.visible, axes: .vertical)")

            barCase(.hidden, "scrollIndicators(.hidden, axes: .vertical)")
        }
    }

    /// One scroller with the setting that made it named underneath, so the pair
    /// reads as one difference rather than as two scrollers.
    private func barCase(_ visibility: ScrollIndicatorVisibility, _ caption: String) -> some View {
        VStack(spacing: 6) {
            ScrollView {
                VStack {
                    ForEach(1...40) { line in
                        Text("Line \(line)")
                            .font(.system(size: 13))
                            .padding(EdgeInsets(6, 4))
                    }
                }
            }
            .scrollIndicators(visibility, axes: .vertical)
            .frame(maxHeight: .infinity)

            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(Palette.subtle)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    var notes: (any View)? {
        Text("`.hidden` takes the bar away and nothing brings it back; `.visible` asks for "
            + "one that stays whether or not a drag is under way. Where the platform draws "
            + "an overlay bar that fades on its own, the two look alike until the scroller "
            + "is dragged.")
            .font(.system(size: 12))
            .foregroundStyle(Palette.subtle)
    }
}

/// A scroller: both directions, moved from code, and its bar.
struct ScrollViewSample: SampleContent {
    static let id = "scrollView"
    static let title = "ScrollView"
    static let summary = "A scrollable container - both directions, moved from code, and its bar."

    // Every example here IS a scroller, so the page must not put one inside
    // another: the wrong one moves under the user's finger, and a scroller
    // inside a scroller cannot be given a height worth having.
    static let scrolls = false

    /// Each example is given the WINDOW's height, which is what a scroller
    /// needs to be worth dragging.
    static let fills = true

    var examples: [Example] {
        [Example(Directions()), Example(ReaderStrip()), Example(BarStrips())]
    }
}
