import SwiftOmniUI

/// The three lifecycle scopes available to every view in a window.
struct WindowPhaseSample: SampleContent, ExampleContent {
    /// The application as it runs.
    @Environment var application: ApplicationSession

    /// This gallery - the scene the page is in.
    @Environment var scene: SceneSession

    /// The window this page is in.
    @Environment var window: WindowSession

    static let id = "windowPhase"
    static let title = "Phases"
    static let summary = "Read application, scene, and window lifecycle as state."

    static let code = """
        @Environment private var application: ApplicationSession
        @Environment private var scene: SceneSession
        @Environment private var window: WindowSession

        VStack {

            Text("application · \\(application.phase)")   // active, inactive or background
            Text("this gallery · \\(scene.phase)")        // active, inactive or background
            Text("this window · \\(window.phase)")        // from created to destroying
        }
        """

    var notes: (any View)? { nil }

    var body: some View {
        VStack {

            PhaseRow(name: "application", value: "\(application.phase)")
            PhaseRow(name: "this gallery", value: "\(scene.phase)")
            PhaseRow(name: "this window", value: "\(window.phase)")

            Text(verdict)
                .font(.system(size: 14))
                .foregroundStyle(Palette.accent)
                .multilineTextAlignment(.center)
        }
        .spacing(10)
    }

    /// What the three say together.
    private var verdict: String {
        if application.phase == .background {
            return "The application is out of sight."
        }

        if application.phase != .active {
            return "Another application is in front."
        }

        if scene.phase != .active {
            return "Another gallery is in front of this one."
        }

        return "This gallery is the one in front."
    }

}

/// One phase: whose it is, and where it stands.
private struct PhaseRow: View {
    let name: String
    let value: String

    var body: some View {
        HStack {
            Text(name)
                .font(.system(size: 13))
                .foregroundStyle(Palette.subtle)
                .frame(width: 110)

            Text(value)
                .font(.system(size: 24))
                .bold()
        }
        .spacing(12)
    }
}
