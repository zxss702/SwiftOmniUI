import SwiftOmniUI

/// Text dragged from one view and dropped on another.
struct DragAndDropSample: SampleContent, ExampleContent {
    @State private var items = ["Alpha", "Beta", "Gamma"]
    @State private var basket: [String] = []

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

        VStack {
            // What was dropped is read here, so a drop builds this closure.

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
                    .id(item)
                }
            }

            ZStack {
                VStack {
                    Text(basket.isEmpty ? "nothing yet" : "\\(basket.count) dropped")

                    ForEach(Array(basket.enumerated()), id: \\.offset) { pair in
                        Text(pair.element)
                    }
                }
                .padding(24)
            }
            .style("Card")
            .onDrop { text in
                basket.append(text)
            }

            Button("Empty it", action: { basket = [] })
                .disabled(basket.isEmpty)
        }
        """

    var body: some View {
        VStack {

            SectionTitle("Drag from here")

            HStack {
                ForEach(items) { item in
                    ZStack {
                        Text(item)
                            .font(.system(size: 14))
                            .padding(EdgeInsets(12, 8))
                    }
                    .style("Card")
                    .stroke(Palette.accent, width: 1)
                    .shape(.roundedRectangle(8))
                    // What travels is decided before the drag starts: a native
                    // drag session needs its payload at once.
                    .draggable(text: item)
                    .id(item)
                }
            }
            .spacing(8)

            SectionTitle("Drop here")

            ZStack {
                VStack {
                    Text(basket.isEmpty ? "nothing yet" : "\(basket.count) dropped")
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
            .stroke(Palette.outline, width: 1)
            .shape(.roundedRectangle(10))
            .background(Palette.raised)
            .onDrop { text in
                basket.append(text)
            }

            Button("Empty it", action: { basket = [] })
                .font(.system(size: 13))
                .padding(EdgeInsets(16, 6))
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
                + "text when there is something to say. `onDrop` is also what makes a "
                + "view a drop target: without it, nothing over it is heard.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(8)
    }
}
