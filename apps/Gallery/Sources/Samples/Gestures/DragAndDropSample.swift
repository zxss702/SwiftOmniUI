import SwiftOmniUI

/// Text dragged from one view and dropped on another.
struct DragAndDropSample: SampleContent, ExampleContent {
    @State private var items = ["Alpha", "Beta", "Gamma"]
    @State private var basket: [String] = []
    @State private var over = false
    @State private var finished = "nothing dragged yet"

    static let id = "dragAndDrop"
    static let title = "Drag and drop"
    static let summary = "Carrying something from one view to another."

    // A gesture sample is not put in a scroller: a scroller would claim the
    // drag before the example heard about it, so the page holds the example
    // still - see SampleContent.scrolls.
    static let scrolls = false

    static let code = """
        @State private var items = ["Alpha", "Beta", "Gamma"]
        @State private var basket: [String] = []
        @State private var over = false
        @State private var finished = "nothing dragged yet"

        VStack {
            // The two runs and what the last drag did are read here, so a drop
            // builds this closure.
            DebugInfoLabel()

            HStack {
                ForEach(items) { item in
                    ZStack {
                        Text(item)
                            .padding(EdgeInsets(12, 8))
                    }
                    .style("Card")
                    .stroke(Palette.accent)
                    .shape(.roundedRectangle(8))
                    // What travels is decided before the drag starts: a
                    // native drag session needs its payload at once.
                    .draggable(text: item)
                    // The view that was DRAGGED hears when its own drag ends,
                    // wherever it ended.
                    .onDropCompleted { finished = "\\(item): drop finished" }
                    .id(item)
                }
            }

            Text(finished)

            ZStack {
                VStack {
                    Text(over
                        ? "let go to drop it"
                        : (basket.isEmpty ? "nothing yet" : "\\(basket.count) dropped"))

                    ForEach(Array(basket.enumerated()), id: \\.offset) { pair in
                        Text(pair.element)
                    }
                }
                .padding(24)
            }
            .style("Card")
            // Lit while something is over it and dark again once it leaves,
            // which is what the two events are for.
            .stroke(over ? Palette.accent : Palette.outline)
            .strokeWidth(over ? 2 : 1)
            .shape(.roundedRectangle(10))
            .background(over ? Palette.selected : Palette.raised)
            .onDragOver { over = true }
            .onDragLeave { over = false }
            // A drop is not a leave, so the light comes down here too.
            .onDrop { text in
                basket.append(text)
                over = false
            }

            Button("Empty it", action: { basket = [] })
                .disabled(basket.isEmpty)
                
        }
        """

    var body: some View {
        VStack {
            DebugInfoLabel()

            SectionTitle("Drag from here")

            HStack {
                ForEach(items) { item in
                    ZStack {
                        Text(item)
                            .font(.system(size: 14))
                            .padding(EdgeInsets(12, 8))
                    }
                    .style("Card")
                    .stroke(Palette.accent)
                    .strokeWidth(1)
                    .shape(.roundedRectangle(8))
                    .draggable(text: item)
                    // The view that was DRAGGED hears when its own drag ends,
                    // wherever it ended.
                    .onDropCompleted { finished = "\(item): drop finished" }
                    .id(item)
                }
            }
            .spacing(8)

            Text(finished)
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
                .multilineTextAlignment(.center)

            SectionTitle("Drop here")

            ZStack {
                VStack {
                    Text(over
                        ? "let go to drop it"
                        : (basket.isEmpty ? "nothing yet" : "\(basket.count) dropped"))
                        .font(.system(size: 15))
                        .multilineTextAlignment(.center)

                    ForEach(Array(basket.enumerated()), id: \.offset) { pair in
                        Text(pair.element)
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.subtle)
                            .multilineTextAlignment(.center)
                    }
                }
                .spacing(4)
                .padding(24)
            }
            .style("Card")
            // Lit while something is over it and dark again once it leaves,
            // which is what the two events are for.
            .stroke(over ? Palette.accent : Palette.outline)
            .strokeWidth(over ? 2 : 1)
            .shape(.roundedRectangle(10))
            .background(over ? Palette.selected : Palette.raised)
            .onDragOver { over = true }
            .onDragLeave { over = false }
            // A drop is not a leave, so the light comes down here too.
            .onDrop { text in
                basket.append(text)
                over = false
            }

            Button("Empty it", action: { basket = [] })
                .font(.system(size: 13))
                .padding(EdgeInsets(16, 6))
                .horizontalAlignment(.center)
                .disabled(basket.isEmpty)
                
        }
        .spacing(12)
    }

    var notes: (any View)? {
        VStack {
            Text("What travels is a STRING, decided before the drag starts: a native "
                + "drag session needs its payload at once, so `draggable(text:)` says it "
                + "up front.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("Reading what was dropped is asynchronous - it may be coming from "
                + "another application - so the host reads it, and `onDrop` runs with the "
                + "text when there is something to say.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("`onDragOver` runs again and again while a drag is held over the "
                + "target, not once, so it SETS the highlight rather than counting; "
                + "`onDragLeave` runs when the drag goes away without being let go. A "
                + "drop is not a leave, so `onDrop` takes the highlight down as well.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("Both of those belong to a view that ACCEPTS a drop, and `onDrop` is "
                + "what makes a view one - written without it, neither ever runs. "
                + "`onDropCompleted` is the other end: it belongs to the view that was "
                + "dragged, so it needs `draggable(text:)` beside it, and it runs when "
                + "that drag ends wherever it ended - over the basket, or over nothing "
                + "at all.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(8)
    }
}
