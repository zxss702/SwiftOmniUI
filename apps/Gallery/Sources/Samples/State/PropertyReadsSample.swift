import SwiftOmniUI

/// Two properties of one model, read in two different closures.
///
/// The point of the sample is which closure is built again: each property is
/// a `@State` of its own, so a write to `visits` reaches the closures that
/// read `visits` and nobody else.
private final class Profile {
    @State var name = ""
    @State var visits = 0
}

/// One model, two properties, two readers - and a write reaches one of them.
struct PropertyReadsSample: SampleContent, ExampleContent {
    @State private var profile = Profile()

    static let id = "propertyReads"
    static let title = "One write, one property"
    static let summary = "Two properties of one model are two states: a write reaches only that property's readers."

    static let code = """
        final class Profile {
            @State var name = ""
            @State var visits = 0
        }

        @State private var profile = Profile()

        // THE OUTER CLOSURE READS NEITHER PROPERTY, so no write builds it
        // again and nothing below is carried along. Each block answers for
        // itself.
        VStack {
            // Writes `visits`. A handler reads when it FIRES, not when it is
            // written, so this closure reads nothing at all.
            VStack {
                Button("Another visit", action: { profile.visits += 1 })
                    
            }

            // Reads `visits`. Only a write to `visits` builds this again.
            VStack {

                Text("visits: \\(profile.visits)")
            }

            // Writes `name` and reads nothing: `profile.$name` is the name's
            // own state, handed to the host whole, so the field is no reader.
            VStack {
                TextField("Type a name", text: profile.$name)            }

            // Reads `name`. Only a write to `name` builds this again.
            VStack {

                Text("name: \\(profile.name)")
            }
        }
        """

    var body: some View {
        // THE OUTER CLOSURE READS NEITHER PROPERTY, so no write builds it
        // again and nothing below is carried along. Each block answers for
        // itself.
        VStack {
            VStack {
                Button("Another visit", action: { profile.visits += 1 })
                    .accessibilityIdentifier("propertyReads.visit")
                    .font(.system(size: 13))
                    .background(Palette.accent)
                    .foregroundStyle(.white)
                    .shape(.roundedRectangle(8))
                    .padding(EdgeInsets(20, 10))
                    
            }

            VStack {

                Text("visits: \(profile.visits)")
                    .font(.system(size: 17))
            }
            .spacing(4)
            .padding(14)
            .background(Palette.surface)

            VStack {
                TextField("Type a name", text: profile.$name)
                    .accessibilityIdentifier("propertyReads.name")
                    .accessibilityLabel("Name")
            }

            VStack {

                Text("name: \(profile.name.isEmpty ? "-" : profile.name)")
                    .font(.system(size: 17))
                    .truncationMode(.tail)
            }
            .spacing(4)
            .padding(14)
            .background(Palette.surface)
        }
        .spacing(14)
    }

    var notes: (any View)? {
        VStack {
            Text("Press Another visit and the FIRST count moves while the second stands "
                + "still; type a name and the second moves while the first stands. One "
                + "model, two properties, and a write is about the property it was made "
                + "to - the same thing two separate pieces of state would do.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("Each block says what it was built FOR - `2 builds, for visits` - and a "
                + "block carried along by a rebuilt parent says `with its parent` instead. "
                + "That is the line to watch: while the counts move one at a time and each "
                + "names its own property, the write reached one block and not the other.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("The control and the reader are separate blocks so that each count is "
                + "about one thing. `profile.$name` is the name's own state, handed to the "
                + "field whole - the field reads nothing, so typing builds only the block "
                + "that shows the name.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("One write that is not yours: press Another visit with the caret still "
                + "in the field and the name count moves once more, because the field, "
                + "losing the focus, hands back its text as the platform finished it - the "
                + "first letter capitalized - and a changed text is a write to `name`. "
                + "Press the button again and only the visits count moves.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(12)
    }
}
