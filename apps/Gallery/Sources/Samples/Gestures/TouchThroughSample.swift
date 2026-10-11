import SwiftOmniUI

/// Input that goes through a view to the one below - past the view alone, or
/// past its children too.
struct TouchThroughSample: SampleContent, ExampleContent {
    static let id = "touchThrough"
    static let title = "Touch through"
    static let summary = "A layout that lets taps through to what is below, with or without its children."

    /// A gesture sample: a scroller would claim a drag before the example heard
    /// about it, so the page holds the example still.
    static let scrolls = false

    @State private var below = 0
    @State private var child = 0
    @State private var childrenToo = false

    static let code = """
        @State private var below = 0
        @State private var child = 0
        @State private var childrenToo = false

        VStack {
            // Both counts are read here, so a tap on either builds this closure.
            DebugInfoLabel()

            Grid {
                // Underneath, and still reachable.
                ColorPicker(Palette.accent)
                    .frame(height: 120)
                    .onTapGesture { below += 1 }

                // On top. Its own empty area lets taps through to the box below
                // while the label inside still answers - or, with the switch on,
                // the whole of it ignores input, the label included.
                VStack {
                    Text("tap the child")
                        .foregroundStyle(Palette.onBrand)
                        .background(Palette.brand)
                        .padding(EdgeInsets(14, 8))
                        .horizontalAlignment(.center)
                        .verticalAlignment(.center)
                        .onTapGesture { child += 1 }
                }
                .padding(16)
                .letsInputThrough(!childrenToo)
                .allowsHitTesting(!childrenToo)
            }

            Text("below \\(below)   child \\(child)")

            HStack {
                SwitchRow("Children too", $childrenToo)

                Button("Reset", action: { below = 0; child = 0 })
                    
            }
        }
        """

    var body: some View {
        VStack {
            DebugInfoLabel()

            Grid {
                ColorPicker(Palette.accent)
                    .frame(height: 120)
                    .onTapGesture { below += 1 }

                VStack {
                    // The child wears its own colour and its own padding, so
                    // what is the child and what is the empty area around it
                    // can be told apart by eye - and aimed at separately.
                    Text("tap the child")
                        .foregroundStyle(Palette.onBrand)
                        .background(Palette.brand)
                        .padding(EdgeInsets(24, 12))
                        .horizontalAlignment(.center)
                        .verticalAlignment(.center)
                        .onTapGesture { child += 1 }
                }
                .padding(16)
                .letsInputThrough(!childrenToo)
                .allowsHitTesting(!childrenToo)
            }

            Text("below \(below)   child \(child)")
                .font(.system(size: 13))
                .horizontalAlignment(.center)

            HStack {
                SwitchRow("Children too", $childrenToo)

                Button("Reset", action: { below = 0; child = 0 })
                    
            }
            .spacing(7)
            .horizontalAlignment(.center)
        }
        .spacing(12)
    }

    var notes: (any View)? {
        VStack {
            Text("`letsInputThrough(true)` takes only a layout's own empty area out of "
                + "hit testing: a tap there reaches the box below, and the label inside "
                + "still counts. It is what an overlay over a page wants.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("`ignoresInput(true)` takes the view and everything in it out - with the "
                + "switch on, the label stops counting too and every tap reaches the box.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("Neither is the same as disabled: a disabled view still takes the tap "
                + "and does nothing with it, while these are not hit at all.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(8)
    }
}
