import SwiftOmniUI

/// A run of cards swiped through, its place held in one shared `@State`.
struct GalleryViewSample: SampleContent, ExampleContent {
    static let id = "galleryView"
    static let title = "GalleryView"
    static let summary = "A run of cards the user swipes through - and Back and Next move by the same state."

    /// The cards: what each picture is called and which file it is.
    static let cards: [Card] = [
        Card(name: "Mural", art: "art_mural.png"),
        Card(name: "Nebula", art: "art_nebula.png"),
        Card(name: "Ridge", art: "art_ridge.png"),
        Card(name: "Bloom", art: "art_bloom.png"),
        Card(name: "Tide", art: "art_tide.png"),
        Card(name: "Prism", art: "art_prism.png"),
        Card(name: "Grove", art: "art_grove.png"),
    ]

    /// One card's face.
    struct Card {
        let name: String
        let art: String
    }

    @State private var shown = 0

    // The cards are turned by a scroller of their own, so the example is not
    // put in a second one: the page's scroller would claim the swipe before it
    // heard about one.
    static let scrolls = false

    // And it takes the whole cell: a gallery wants the room, and the cards are
    // placed in whatever it is given.
    static let fills = true

    static let code = """
        @State private var shown = 0

        struct Card { let name: String; let art: String }

        private let cards = [
            Card(name: "Mural", art: "art_mural.png"),
            Card(name: "Nebula", art: "art_nebula.png"),
            Card(name: "Ridge", art: "art_ridge.png"),
            Card(name: "Bloom", art: "art_bloom.png"),
            Card(name: "Tide", art: "art_tide.png"),
            Card(name: "Prism", art: "art_prism.png"),
            Card(name: "Grove", art: "art_grove.png"),
        ]

        VStack {
            // THE WHOLE CONTROL: one card per item, the item its identity.
            GalleryView(cards, id: \\.name) { card in
                face(card)
            }
            .position($shown)
            .frame(maxHeight: .infinity)

            // The binding is written as the user swipes, so anything under
            // the run follows the hand - and assigning it moves the cards.
            Text("card \\(shown + 1) of \\(cards.count)")

            HStack {
                Button("Back") { shown -= 1 }
                    .disabled(shown <= 0)

                Button("Next") { shown += 1 }
                    .disabled(shown >= cards.count - 1)
            }
        }
        """

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                ColorPicker(Palette.raised)
                    .cornerRadius(14)

                GalleryView(Self.cards, id: \.name) { card in
                    face(card)
                }
                .position($shown)
            }
            .frame(maxHeight: .infinity)
            // The cards stay ON the board: one mid-crossing is cut at the
            // board's edge rather than painted over the page.
            .clipped()

            // A LIVE READING, so it stays with the example rather than going
            // to the notes: the position binding is written as the run moves.
            Text("\(Self.cards[min(max(shown, 0), Self.cards.count - 1)].name) · "
                + "card \(shown + 1) of \(Self.cards.count)")
                .font(.system(size: 13))
                .foregroundStyle(Palette.subtle)
                .multilineTextAlignment(.center)

            HStack {
                // ONE WIDTH FOR EVERY CAPTION: a wrapping row re-measures a
                // child on its own schedule.
                Button("Back", action: { shown -= 1 })
                    .font(.system(size: 13))
                    .padding(EdgeInsets(16, 6))
                    .disabled(shown <= 0)

                Button("Next", action: { shown += 1 })
                    .font(.system(size: 13))
                    .padding(EdgeInsets(16, 6))
                    .disabled(shown >= Self.cards.count - 1)
            }
            .spacing(8)
        }
    }

    /// One card's face - a picture and its name, and nothing at all about where
    /// the card is or which way it faces. That is the gallery's, and keeping
    /// the two apart is what lets one run of cards wear its shape.
    private func face(_ card: Card) -> any View {
        ZStack {
            Image(ImageSource(card.art))
                .scaledToFill()

            Text(card.name)
                .font(.system(size: 18))
                .bold()
                .foregroundStyle(Palette.onBrand)
                .padding(EdgeInsets(12, 10))
                .background(Color("#B3000000"))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .clipped()
        .style("Card")
        .stroke(.transparent)
        .shape(.roundedRectangle(16))
    }

    var notes: (any View)? {
        VStack {
            Text("`GalleryView` is a run of cards the user swipes through. Swipe, "
                + "drag with the mouse or turn a wheel: the run settles on the "
                + "card it is nearest. WHICH of those the run answers is the "
                + "platform's: a finger drags the run itself, while on a desktop "
                + "the cards take a drag of their own.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("`.position($shown)` is which card is in front, written as the "
                + "user moves and glided to when it is assigned - which is what "
                + "Back and Next do. One `@State` joins the run to the caption "
                + "under it, and neither names the other.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(8)
    }
}
