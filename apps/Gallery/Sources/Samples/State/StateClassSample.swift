import SwiftOmniUI

/// What a basket holds, as a class rather than a pile of `@State` in the view.
///
/// The properties the interface draws are `@State` - the same word, the same
/// storage and the same rule as in a view: a write asks the closures that READ
/// that property for another build, and no other. A plain `var` is stored and
/// nothing more, and this one is here to be SEEN not working: pressing the
/// button below raises it and the screen does not follow.
private final class Basket {
    @State var items: [String] = []
    @State var note = ""

    /// Counted for the sample's sake; nothing on screen is meant to follow it.
    var plainTaps = 0

    var summary: String {
        items.isEmpty ? "The basket is empty" : items.joined(separator: ", ")
    }
}

/// A child the basket was LENT to.
///
/// `@Binding`, the same wrapper an Int is borrowed with - a model is a value
/// like any other as far as lending is concerned. `$basket` says: I lend you
/// this, do with it what you want - and `basket.$note` is the note's own
/// state, the `Binding<String>` a TextField takes and the host carries.
private struct NoteRow: View {
    @Binding var basket: Basket

    var body: some View {
        VStack {
            // The field is handed the note's own state and reads nothing; the
            // label below READS `note`, which is what builds this again.

            TextField("A note on the basket", text: basket.$note)
                .accessibilityIdentifier("stateClass.note")
                .accessibilityLabel("A note on the basket")

            Text(basket.note.isEmpty ? "No note yet" : "Note: \(basket.note)")
                .font(.system(size: 17))
                .multilineTextAlignment(.center)
        }
        .spacing(14)
    }
}

/// A model in a class, edited in place - `@State` on its properties is what
/// makes the writes visible, and `@State` on the view is what keeps the
/// instance.
struct StateClassSample: SampleContent, ExampleContent {
    @State private var basket = Basket()

    static let id = "stateClass"
    static let title = "State in a class"
    static let summary = "A class whose properties are @State lives in @State and is edited property by property."

    static let code = """
        final class Basket {
            @State var items: [String] = []
            @State var note = ""

            var plainTaps = 0

            var summary: String {
                items.isEmpty ? "The basket is empty" : items.joined(separator: ", ")
            }
        }

        struct NoteRow: View {
            @Binding var basket: Basket

            var body: some View {
                VStack {
                    // The field is handed the note's own state and reads
                    // nothing; the label READS `note`, so typing rebuilds this.

                    TextField("A note on the basket", text: basket.$note)
                    Text(basket.note.isEmpty ? "No note yet" : "Note: \\(basket.note)")
                }
            }
        }

        @State private var basket = Basket()

        VStack {
            // And this one reads the items, so adding and removing rebuild it
            // - while typing a note leaves it standing.

            Text("\\(basket.items.count) item(s)")

            Text(basket.summary)

            HStack {
                Button("Add", action: { basket.items.append("Item \\(basket.items.count + 1)") })
                    

                Button("Remove", action: { basket.items.removeLast() })
                    .disabled(basket.items.isEmpty)
                    
            }

            NoteRow(basket: $basket)

            Button("Tap a plain property (\\(basket.plainTaps))", action: { basket.plainTaps += 1 })
                
        }
        """

    var body: some View {
        VStack {

            Text("\(basket.items.count) item(s)")
                .font(.system(size: 22))
                .multilineTextAlignment(.center)

            Text(basket.summary)
                .font(.system(size: 15))
                .foregroundStyle(Palette.subtle)
                .multilineTextAlignment(.center)

            HStack {
                Button("Add", action: { basket.items.append("Item \(basket.items.count + 1)") })
                    .background(Palette.accent)
                    .foregroundStyle(.white)
                    .shape(.roundedRectangle(8))
                    .padding(EdgeInsets(20, 10))
                    

                Button("Remove", action: { basket.items.removeLast() })
                    .stroke(Palette.outline, width: 1)
                    .background(.transparent)
                    .foregroundStyle(Palette.subtle)
                    .shape(.roundedRectangle(8))
                    .padding(EdgeInsets(20, 10))
                    .disabled(basket.items.isEmpty)
                    
            }
            .spacing(12)

            NoteRow(basket: $basket)

            Button("Tap a plain property (\(basket.plainTaps))", action: { basket.plainTaps += 1 })
                .stroke(Palette.outline, width: 1)
                .background(.transparent)
                .foregroundStyle(Palette.subtle)
                .shape(.roundedRectangle(8))
                .padding(EdgeInsets(20, 10))
                

        }
        .spacing(14)
    }

    var notes: (any View)? {
        VStack {
            Text("The basket is a class, held in @State. The view's box holds a reference "
                + "to it, so `basket.items.append(…)` never writes through that box - the "
                + "write lands on the property's own @State, and that is what asks for the "
                + "render. Both are needed: @State on the properties makes the writes "
                + "visible, @State on the view keeps the instance across the rebuild.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("The note is written by a child row the basket was lent to - @Binding, "
                + "the same wrapper an Int is borrowed with. `basket.$note` is the note's "
                + "own state, handed to the field whole, and it works the same off the "
                + "view's own @State. No handler either way.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("The plain property's count really is going up - press Add afterwards "
                + "and it jumps to where it got to. A plain `var` is stored and nothing "
                + "more: a cache, a scratch value, anything the interface does not draw - "
                + "and writing it asks for nothing.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("Swift's own @Observable is a different attribute reporting to a "
                + "different listener, and this library does not listen to it: a model "
                + "marked with it can be held in @State, and its writes redraw nothing. "
                + "The compiler says so on the line that holds it. What this library "
                + "hears is @State - in a view or in a class alike.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(10)
    }
}
