import SwiftOmniUI

/// How dark the gallery's own demonstration paints - kept as the text it is
/// spelled with, which is what makes conformance one line.
enum Shade: String, PersistentValue {
    case quiet
    case bold
}

extension PersistentKey {
    /// How many times the user has pressed the button, ever.
    static let visits = PersistentKey("dev.swiftomniui.gallery.visits", of: Int.self)

    /// What the user is called.
    static let who = PersistentKey("dev.swiftomniui.gallery.who", of: String.self)

    /// Whether the panel below paints loudly.
    static let shade = PersistentKey("dev.swiftomniui.gallery.shade", of: Shade.self)
}

/// `@State` under a key is state the application KEEPS - the value is there
/// again the next time the app opens, with nothing to load and nothing to save.
struct PersistentStateSample: SampleContent, ExampleContent {
    @State(persistentKey: .visits) private var visits = 0
    @State(persistentKey: .who) private var who = ""
    @State(persistentKey: .shade) private var shade = Shade.quiet

    static let id = "persistent-state"
    static let title = "Persistent state"
    static let summary = "State under a key survives the app being closed."

    static let code = """
        // A key can hold what the platform's settings store holds - and an
        // enum over one of those is one line, kept as the text it is spelled
        // with.
        enum Shade: String, PersistentValue {
            case quiet
            case bold
        }

        extension PersistentKey {
            static let visits = PersistentKey("dev.swiftomniui.gallery.visits", of: Int.self)
            static let who = PersistentKey("dev.swiftomniui.gallery.who", of: String.self)
            static let shade = PersistentKey("dev.swiftomniui.gallery.shade", of: Shade.self)
        }

        // Into the application's session as it is made, so the host knows
        // what to read before the first view is built:
        @Environment private var application: ApplicationSession

        init() {
            application.persistentKeys = [.visits, .who, .shade]
        }

        // And then it is ordinary state:
        @State(persistentKey: .visits) private var visits = 0
        @State(persistentKey: .who) private var who = ""
        @State(persistentKey: .shade) private var shade = Shade.quiet

        VStack {
            // Every one of the three kept values is read here, so this is what
            // a write rebuilds - and the reading names which one it was for.
            DebugInfoLabel()

            Text("Pressed \\(visits) times, ever")

            HStack {
                Button("Press", action: { visits += 1 })
                    

                Button("Start over", action: { visits = 0 })
                    .disabled(visits == 0)
                    
            }

            TextField("Your name", text: $who)

            Text(who.isEmpty ? "Welcome back" : "Welcome back, \\(who)")

            Button(shade == .quiet ? "quiet" : "bold", action: { shade = shade == .quiet ? .bold : .quiet })
                

            ColorPicker()
                .color(shade == .bold ? Palette.accent : Palette.surface)
        }
        """

    var notes: (any View)? {
        VStack {
            Text("Close the app completely and open it again: the count and the name "
                + "are where you left them.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("The value written beside the state - `= 0` - is what it holds when "
                + "the store has nothing under that name, so the default stays where "
                + "it can be seen. Reading and writing are exactly what they are on any "
                + "other @State: nothing is awaited, and a write reaches the store by "
                + "itself.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("The application LISTS its keys, in its session's persistentKeys. That is not "
                + "ceremony: a settings store is read one key at a time and offers no "
                + "list of what it holds, so naming them is what puts the values in "
                + "memory before the first view asks for one.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("They are kept in the platform's own settings store - NSUserDefaults, "
                + "SharedPreferences, ApplicationDataContainer - beside whatever else "
                + "the app keeps there. So a key can hold only what such a store holds: "
                + "a whole number, a number, true or false, or text. An enum over one of "
                + "those is one line, as Shade is here.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(12)
    }

    var body: some View {
        VStack {
            DebugInfoLabel()

            Text("Pressed \(visits) times, ever")
                .font(.system(size: 22))
                .multilineTextAlignment(.center)

            HStack {
                Button("Press", action: { visits += 1 })
                    .background(Palette.accent)
                    .shape(.roundedRectangle(8))
                    .padding(EdgeInsets(20, 10))
                    

                Button("Start over", action: { visits = 0 })
                    .stroke(Palette.outline)
                    .strokeWidth(1)
                    .background(.transparent)
                    .foregroundStyle(Palette.subtle)
                    .shape(.roundedRectangle(8))
                    .padding(EdgeInsets(20, 10))
                    .disabled(visits == 0)
                    
            }
            .spacing(12)
            .horizontalAlignment(.center)

            TextField($who)
                .accessibilityIdentifier("persistent-state.who")
                .accessibilityLabel("Your name")
                .placeholder("Your name")

            Text(who.isEmpty ? "Welcome back" : "Welcome back, \(who)")
                .font(.system(size: 17))
                .multilineTextAlignment(.center)

            // A key whose value is an enum - kept as the word it is spelled
            // with, so anything else that opens the store can read it.
            HStack {
                Text("Shade")
                    .verticalAlignment(.center)

                Button(shade == .quiet ? "quiet" : "bold", action: { shade = shade == .quiet ? .bold : .quiet })
                    .stroke(Palette.outline)
                    .strokeWidth(1)
                    .background(.transparent)
                    .foregroundStyle(Palette.subtle)
                    .shape(.roundedRectangle(8))
                    .padding(EdgeInsets(16, 8))
                    
            }
            .spacing(12)

            ColorPicker()
                .frame(height: 48)
                .color(shade == .bold ? Palette.accent : Palette.surface)
                .cornerRadius(8)
        }
        .spacing(14)
    }
}
