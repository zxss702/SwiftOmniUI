import SwiftOmniUI

/// The application's own session as an environment value: write its animation
/// once and every value without one of its own travels so from then on.
struct ApplicationSessionSample: SampleContent, ExampleContent {
    /// The application as it runs - one for the whole process.
    @Environment private var application: ApplicationSession

    @State private var wide = false

    static let id = "applicationSession"
    static let title = "Application session"
    static let summary = "The application's own session, read and written like any state - here the animation every value takes."

    /// The law the picker stands on, by name.
    @State private var lawName = "Standard"

    static let laws = ["Standard", "Spring", "None"]

    static func law(named name: String) -> Animation {
        switch name {
        case "Spring": .spring(response: 0.32, dampingFraction: 0.6)
        case "None": .linear(duration: 0)
        default: .default
        }
    }

    static let code = """
        @Environment private var application: ApplicationSession
        @State private var wide = false
        @State private var lawName = "Standard"

        static let laws = ["Standard", "Spring", "None"]

        static func law(named name: String) -> Animation {
            switch name {
            case "Spring": .spring(response: 0.32, dampingFraction: 0.6)
            case "None": .linear(duration: 0)
            default: .default
            }
        }

        VStack {
            // `lawName` and `wide` are read here, so a choice or a press builds
            // this closure.

            // One write for the whole application: every value without an
            // animation of its own travels so from now on.
            Picker("Law", selection: $lawName) {
                ForEach(Self.laws, id: \\.self) { Text($0).tag($0) }
            }
            .onChange(of: lawName) { application.animation = Self.law(named: lawName) }

            // No `.animation` here: the panel takes the application's.
            ZStack {}
                .background(wide ? Palette.accent : Palette.brand)
                .frame(width: wide ? 300 : 120, height: 60)
                .shape(.roundedRectangle(8))

            Button("Change") { wide.toggle() }
        }
        """

    var body: some View {
        VStack {

            Text("Pick None, then open another sample: nothing in the application travels.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.subtle)
                .multilineTextAlignment(.center)

            Picker("Law", selection: $lawName) {
                ForEach(Self.laws, id: \.self) { Text($0).tag($0) }
            }
            .onChange(of: lawName) { application.animation = Self.law(named: lawName) }

            ZStack {}
                .background(wide ? Palette.accent : Palette.brand)
                .frame(width: wide ? 300 : 120, height: 60)
                .shape(.roundedRectangle(8))

            Button("Change") { wide.toggle() }
        }
        .spacing(12)
    }

    var notes: (any View)? {
        VStack {
            Text("The application's session holds what is the whole process's: its phase, its open "
                + "scenes, its styles, its animation and the keys it keeps. The scene's and the "
                + "window's sessions are under Windows.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("A view nearer the value still answers first: `.animation(_:)` on a view, "
                + "`@State(animation:)` on a state, `$state.journey.snap(to:)` on one write.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(10)
    }
}
