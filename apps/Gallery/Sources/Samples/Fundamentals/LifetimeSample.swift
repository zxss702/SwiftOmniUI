import SwiftOmniUI

/// `.onAppear` and `.onDisappear`: what runs as an element comes into the
/// tree and as it leaves, once each.
struct LifetimeSample: SampleContent, ExampleContent {
    /// Whether the card is in the tree at all.
    @State private var shown = true

    /// The card's identity - a new one is a new card.
    @State private var identity = 1

    /// How often the page was built again on purpose, which carries the card,
    /// built with the same inputs, and creates nothing.
    @State private var builds = 0

    /// What the cards have said, oldest first.
    @State private var log: [String] = []

    static let id = "lifetime"
    static let title = "Element lifetime"
    static let summary = "What runs as a view comes into the tree and as it leaves - once each."

    static let code = """
        @State private var shown = true
        @State private var identity = 1
        @State private var builds = 0
        @State private var log: [String] = []

        VStack {
            // Every button builds this closure again. Build this again changes
            // nothing the card is built with, so it carries the card and
            // creates nothing.

            SwitchRow("Show the card", $shown)

            HStack {
                Button("A new card", action: { identity += 1 })
                Button("Build this again · \\(builds)", action: { builds += 1 })
            }

            if shown {
                // A new identity is a new card: the one on screen is
                // destroyed, and this one created.
                LifetimeCard(number: identity, log: $log)
                    .id(identity)
            }

            VStack {
                if log.isEmpty {
                    Text("nothing yet")
                }

                ForEach(Array(log.suffix(6))) { line in
                    Text(line)
                }
            }
        }

        struct LifetimeCard: View {
            let number: Int
            @Binding var log: [String]
            @State private var taps = 0

            var body: some View {
                Button("Card \\(number) · tapped \\(taps)", action: { taps += 1 })
                    
                    // Once, after the render that brings the card in - its
                    // state and its environment are there to use.
                    .onAppear {
                        log.append("\\(log.count + 1) · card \\(number) created")
                    }
                    // Once, after the render that leaves it out - and its
                    // state still answers, which is what saving needs.
                    .onDisappear {
                        log.append("\\(log.count + 1) · card \\(number) destroying, tapped \\(taps)")
                    }
            }
        }
        """

    var body: some View {
        VStack {

            SwitchRow("Show the card", $shown)

            HStack {
                Button("A new card", action: { identity += 1 })
                    .font(.system(size: 13))
                    .padding(EdgeInsets(16, 6))
                    

                Button("Build this again · \(builds)", action: { builds += 1 })
                    .font(.system(size: 13))
                    .padding(EdgeInsets(16, 6))
                    
            }
            .spacing(10)

            if shown {
                LifetimeCard(number: identity, log: $log)
                    .id(identity)
            }

            VStack {
                if log.isEmpty {
                    Text("nothing yet")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.subtle)
                }

                ForEach(Array(log.suffix(6))) { line in
                    Text(line)
                        .font(.system(size: 14, design: .monospaced))
                }
            }
            .spacing(4)
        }
        .spacing(12)
    }

    var notes: (any View)? {
        VStack {
            Text("Switch the card off and on: it is destroyed and created again - a new "
                + "card, counting from nought. A new card does the same to the one on "
                + "screen by giving it a new identity. Build this again builds the page "
                + "once more, which carries the card, built with the same inputs, and "
                + "creates nothing: an element is created once, however many times the "
                + "view around it is built.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("Tap the card before it goes: what it says as it is destroyed is its "
                + "own count, because its state still answers - the place to save what it "
                + "holds. Both are on every view and control and on the pages the library "
                + "builds - a page of your own writes them on its content - and both run "
                + "after the render that made the change.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(12)
    }
}

/// A card that says when it comes and goes, counting its own taps.
private struct LifetimeCard: View {
    let number: Int
    @Binding var log: [String]
    @State private var taps = 0

    var body: some View {
        Button("Card \(number) · tapped \(taps)", action: { taps += 1 })
            .font(.system(size: 15))
            .foregroundStyle(.white)
            .background(Palette.accent)
            .shape(.roundedRectangle(10))
            .padding(EdgeInsets(20, 12))
            
            .onAppear {
                log.append("\(log.count + 1) · card \(number) created")
            }
            .onDisappear {
                log.append("\(log.count + 1) · card \(number) destroying, tapped \(taps)")
            }
    }
}
