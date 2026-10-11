import SwiftOmniUI

/// The color scheme as a value a view can branch on.
struct AppThemeSample: SampleContent, ExampleContent {
    /// The application's information, where the color scheme is read.
    @Environment var app: AppInfo

    static let id = "appTheme"
    static let title = "ColorScheme"
    static let summary = "The colorScheme as a value a view can branch on - "
        + "updated live when the system switches."

    static let code = """
        struct ThemeBadge: View {
            @Environment var app: AppInfo

            var body: some View {
                VStack {
                    // The color scheme is read here, so a change to it builds this
                    // closure.

                    Text("\\(app.colorScheme)")

                    // LOGIC on the color scheme - a different WORD, not a colour.
                    // A colour that differs by color scheme is Color(light:dark:),
                    // which follows by itself.
                    Text(app.colorScheme == .dark
                        ? "lights off - a view can choose calmer artwork"
                        : "lights on - a view can choose vivid artwork")
                }
            }
        }
        """

    var body: some View {
        VStack {

            Text("\(app.colorScheme)")
                .font(.system(size: 34))
                .bold()
                .multilineTextAlignment(.center)

            Text(app.colorScheme == .dark
                ? "lights off - a view can choose calmer artwork"
                : "lights on - a view can choose vivid artwork")
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
        }
        .spacing(10)
    }

    var notes: (any View)? {
        VStack {
            Text("Switch the SYSTEM's appearance and the word above follows "
                + "in the same breath.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("Use this for LOGIC - a different picture, a different word. A "
                + "colour should not need it: a `Color(light:dark:)` reads the colorScheme "
                + "as the view wearing it is built, so a colorScheme change builds exactly "
                + "the views wearing one again.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(8)
    }
}
