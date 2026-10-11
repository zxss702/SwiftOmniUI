import SwiftOmniUI

/// The accessible meaning and stable external identity of a SwiftOmniUI view.
struct SemanticsSample: SampleContent, ExampleContent {
    @State private var described = true

    @State private var taps = 0

    /// The last thing said out loud, shown - because a machine with no screen
    /// reader running shows nothing at all otherwise, and what was said is the
    /// whole point of the button.
    @State private var said = ""

    static let id = "semantics"
    static let title = "Semantics"
    static let summary = "What a view says about itself - to a screen reader, and to whatever drives the app."

    /// Said once, and both written onto the button and printed under it - so
    /// what the sample shows cannot drift from what the platform was handed.
    private static let says = "Add to favourites"

    private static let hint = "Puts this item on your list"

    static let code = """
        @State private var described = true
        @State private var taps = 0
        @State private var said = ""

        // What a user is told is read here, so throwing the switch builds
        // this closure again.
        VStack {
            DebugInfoLabel()

            HStack {
                // A picture and nothing else. To anybody not looking at it,
                // this control has no name at all.
                Button(icon: ImageSource(light: "nav_media.png", dark: "nav_media_dark.png"), action: { taps += 1 })
                    .style("IconButton")
                    .accessibilityIdentifier("semantics.bare")
                    

                // The same button, saying what it is and what using it does.
                // Written as a value rather than in the chain, so throwing the
                // switch CLEARS the property off the same control instead of
                // building a different one.
                describedButton
            }

            Text("Tapped \\(taps) time\\(taps == 1 ? "" : "s")")

            SwitchRow("Describe the second button", $described)

            // Read as a heading: somewhere a user jumping through the page
            // can land.
            Text("A heading, and drawn the same")
                .accessibilityHeadingLevel(.level1)

            // Said out loud, now, whatever the user was on. An ACT, because
            // it is something that happens at a moment rather than a value a
            // view can hold.
            Button("Announce the count", action: {
                    let words = "Tapped \\(taps) time\\(taps == 1 ? "" : "s")"
                    try await ScreenReader.announce(words)
                    said = words
                })
                

            // Shown as well as said: with no screen reader running there is
            // nothing to see otherwise, and what was said is the point.
            Text(said.isEmpty ? "nothing said yet" : "said: \\(said)")

            // One word takes the panel AND everything in it out of what a
            // screen reader walks; the rule below is a single view taken out.
            ZStack {
                VStack {
                    Text("Skipped")
                    Text("Neither line is read")
                }
            }
            .style("Card")
            .automationExcludedWithChildren(true)

            ColorPicker(Palette.outline)
                .frame(height: 1)
                .accessibilityHidden(true)
        }

        private var describedButton: any View {
            let button = Button(icon: ImageSource(light: "nav_layout.png", dark: "nav_layout_dark.png"), action: { taps += 1 })
                .style("IconButton")
                .accessibilityIdentifier("semantics.described")
                

            return described
                ? button.accessibilityLabel("Add to favourites")
                    .accessibilityHint("Puts this item on your list")
                : button
        }
        """

    var body: some View {
        VStack {
            DebugInfoLabel()

            HStack {
                VStack {
                    Button(icon: ImageSource(light: "nav_media.png", dark: "nav_media_dark.png"), action: { taps += 1 })
                        .style("IconButton")
                        .accessibilityIdentifier("semantics.bare")
                        .aspect(.fit)
                        .frame(width: 64)
                        .frame(height: 64)
                        .stroke(Palette.outline)
                        .strokeWidth(1)
                        .shape(.roundedRectangle(12))
                        

                    Text("A user hears")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.subtle)
                        .multilineTextAlignment(.center)

                    Text("nothing")
                        .font(.system(size: 13))
                        .italic()
                        .foregroundStyle(Palette.subtle)
                        .multilineTextAlignment(.center)
                }
                .spacing(4)
                .frame(width: 150)

                VStack {
                    describedButton

                    Text("A user hears")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.subtle)
                        .multilineTextAlignment(.center)

                    Text(described ? "\(Self.says)\n\(Self.hint)" : "nothing")
                        .font(described ? Font.system(size: 13) : Font.system(size: 13).italic())
                        .foregroundStyle(described ? Palette.accent : Palette.subtle)
                        .multilineTextAlignment(.center)
                }
                .spacing(4)
                .frame(width: 150)
            }
            .spacing(12)
            .horizontalAlignment(.center)

            Text("Tapped \(taps) time\(taps == 1 ? "" : "s")")
                .font(.system(size: 15))
                .multilineTextAlignment(.center)

            SwitchRow("Describe the second button", $described)
                .horizontalAlignment(.center)

            SectionTitle("A heading is what this says it is")

            // Drawn alike and read differently: only the second is somewhere a
            // user jumping through the page can land.
            VStack {
                Text("Drawn large")
                    .font(.system(size: 20))
                    .bold()

                Text("A heading, and drawn the same")
                    .font(.system(size: 20))
                    .bold()
                    .accessibilityHeadingLevel(.level1)
            }
            .spacing(4)

            SectionTitle("Said out loud")

            Button("Announce the count", action: {
                    let words = "Tapped \(taps) time\(taps == 1 ? "" : "s")"
                    try await ScreenReader.announce(words)
                    said = words
                })
                .accessibilityIdentifier("semantics.announce")
                .font(.system(size: 13))
                .padding(EdgeInsets(16, 6))
                .horizontalAlignment(.center)
                

            Text(said.isEmpty ? "nothing said yet" : "said: \(said)")
                .font(.system(size: 12))
                .foregroundStyle(said.isEmpty ? Palette.subtle : Palette.accent)
                .multilineTextAlignment(.center)

            SectionTitle("What a user walks past")

            HStack {
                ZStack {
                    VStack {
                        Text("Walked")
                            .font(.system(size: 15))
                            .bold()

                        Text("Both lines are read")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.subtle)
                    }
                    .spacing(2)
                    .padding(12)
                }
                .style("Card")

                // The whole panel, and everything in it, is not there at all
                // to a screen reader - one word instead of one per view.
                ZStack {
                    VStack {
                        Text("Skipped")
                            .font(.system(size: 15))
                            .bold()

                        Text("Neither line is read")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.subtle)
                    }
                    .spacing(2)
                    .padding(12)
                }
                .style("Card")
                .automationExcludedWithChildren(true)
            }
            .spacing(12)
            .horizontalAlignment(.center)

            // A rule is decoration: a stop that would waste the user's time.
            ColorPicker(Palette.outline)
                .frame(height: 1)
                .accessibilityHidden(true)
        }
        .spacing(12)
    }

    /// The described button, built as a VALUE so that turning the switch off
    /// takes the property off THIS control rather than describing another one.
    /// An absent property restores the host's native default, which is what
    /// makes a modifier written under a condition cost the property and not
    /// the control.
    private var describedButton: any View {
        let button = Button(icon: ImageSource(light: "nav_layout.png", dark: "nav_layout_dark.png"), action: { taps += 1 })
            .style("IconButton")
            .accessibilityIdentifier("semantics.described")
            .aspect(.fit)
            .frame(width: 64)
            .frame(height: 64)
            .stroke(Palette.outline)
            .strokeWidth(1)
            .shape(.roundedRectangle(12))
            

        return described
            ? button.accessibilityLabel(Self.says).accessibilityHint(Self.hint)
            : button
    }

    var notes: (any View)? {
        VStack {
            Text("Two jobs, four modifiers, and they do not stand in for one another. "
                + "`.accessibilityLabel` and `.accessibilityHint` are what a screen reader "
                + "SAYS: the first names the control, the second says what using it does. "
                + "`.accessibilityHeadingLevel` marks a view as a heading, which is how a "
                + "user moves through a long page. `.accessibilityIdentifier` is a handle nobody "
                + "hears - it is what a UI test, a script or an agent driving the "
                + "application asks the platform to find.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("Every control on this page carries one: the two buttons answer to "
                + "`semantics.bare` and `semantics.described`. An id is worth having "
                + "wherever something outside the application has to find a control, and "
                + "it has to stay the same between renders - one that moves with the "
                + "state is one nothing can wait for.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("Turn the switch off and the description is taken off the control it "
                + "was on, rather than a second button being drawn: a property that goes "
                + "away is cleared back to the host's native default. To hear any of it, turn on "
                + "the platform's screen reader - VoiceOver on Apple, TalkBack on "
                + "Android, Narrator on Windows - and touch the two buttons in turn.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(12)
    }
}
