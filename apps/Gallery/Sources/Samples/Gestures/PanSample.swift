import SwiftOmniUI

/// A view dragged about under a finger.
struct PanSample: SampleContent, ExampleContent {
    /// Where the box was left - where the last drag ended.
    @State private var panX = 0.0
    @State private var panY = 0.0

    /// Where the box IS right now: the committed place plus whatever the
    /// finger has added since the drag began.
    @State private var liveX = 0.0
    @State private var liveY = 0.0

    static let id = "pan"
    static let title = "Pan"
    static let summary = "Dragging a view from where it was to where it is let go."

    // A gesture sample is not put in a scroller: a scroller would claim the
    // drag before the example heard about it, so the page holds the example
    // still - see SampleContent.scrolls.
    static let scrolls = false

    static let code = """
        @State private var panX = 0.0
        @State private var panY = 0.0
        @State private var liveX = 0.0
        @State private var liveY = 0.0

        VStack {
            ZStack {
                ColorPicker(Palette.accent)
                    .frame(width: 64)
                    .frame(height: 64)
                    .offset(x: liveX, y: liveY)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                liveX = panX + value.translation.width
                                liveY = panY + value.translation.height
                            }
                            .onEnded { _ in
                                panX = liveX
                                panY = liveY
                            }
                    )
            }
            .frame(height: 200)

            Text("Moved \\(Int(liveX)), \\(Int(liveY))")

            Button("Put it back") {
                panX = 0
                panY = 0
                liveX = 0
                liveY = 0
            }
        }
        """

    var body: some View {
        VStack {
            // A fixed box for it to move inside, so the layout does not follow
            // the view about.
            ZStack {
                ColorPicker(Palette.accent)
                    .cornerRadius(10)
                    .frame(width: 64)
                    .frame(height: 64)
                    .offset(x: liveX, y: liveY)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                liveX = panX + value.translation.width
                                liveY = panY + value.translation.height
                            }
                            .onEnded { _ in
                                panX = liveX
                                panY = liveY
                            }
                    )
            }
            .style("Card")
            .stroke(Palette.outline, width: 1)
            .shape(.roundedRectangle(10))
            .frame(height: 200)

            Text("Moved \(Int(liveX)), \(Int(liveY))")
                .font(.system(size: 15))
                .multilineTextAlignment(.center)

            Button("Put it back", action: {
                    panX = 0
                    panY = 0
                    liveX = 0
                    liveY = 0
                })
                .font(.system(size: 13))
                .padding(EdgeInsets(16, 6))
        }
        .spacing(12)
    }

    var notes: (any View)? {
        VStack {
            Text("`translation` is measured from where the drag BEGAN, not from "
                + "the last report - which is why `onChanged` adds it to where the "
                + "view was left, and `onEnded` commits the move.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("Each report is a state write and a render; `Put it back` writes "
                + "the same two states once, and the box jumps home.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(8)
    }
}
