import SwiftOmniUI

/// A tap and a double tap on a whole view.
struct TapSample: SampleContent, ExampleContent {
    @State private var taps = 0

    static let id = "tap"
    static let title = "Tap"
    static let summary = "The whole view answers, not a button inside it."

    // A gesture sample is not put in a scroller: a scroller would claim the
    // drag before the example heard about it, so the page holds the example
    // still - see SampleContent.scrolls.
    static let scrolls = false

    static let code = """
        @State private var taps = 0

        VStack {
            // The count is read here, so every tap builds this closure.

            ZStack {
                Text("Tap anywhere on this box")
                    .padding(24)
            }
            .style("Card")
            .stroke(Palette.accent)
            .shape(.roundedRectangle(10))
            .onTapGesture { taps += 1 }

            ZStack {
                Text("Double-tap this one to reset")
                    .padding(24)
            }
            .style("Card")
            .stroke(Palette.outline)
            .shape(.roundedRectangle(10))
            .onTapGesture(count: 2) { taps = 0 }

            Text("Tapped \\(taps) time(s)")
        }
        """

    var body: some View {
        VStack {

            ZStack {
                Text("Tap anywhere on this box")
                    .font(.system(size: 15))
                    .padding(24)
                    .multilineTextAlignment(.center)
            }
            .style("Card")
            .stroke(Palette.accent, width: 1)
            .shape(.roundedRectangle(10))
            .onTapGesture { taps += 1 }

            ZStack {
                Text("Double-tap this one to reset")
                    .font(.system(size: 15))
                    .padding(24)
                    .multilineTextAlignment(.center)
            }
            .style("Card")
            .stroke(Palette.outline, width: 1)
            .shape(.roundedRectangle(10))
            .onTapGesture(count: 2) { taps = 0 }

            Text("Tapped \(taps) time(s)")
                .font(.system(size: 17))
                .multilineTextAlignment(.center)
        }
        .spacing(12)
    }

    var notes: (any View)? {
        Text("Any view answers a tap: every card on a group's page is a view with "
            + "`.onTapGesture` on it.")
            .font(.system(size: 12))
            .foregroundStyle(Palette.subtle)
    }
}
