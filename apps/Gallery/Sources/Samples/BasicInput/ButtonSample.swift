import SwiftOmniUI

/// A button wired to a click, beside an outlined one and a disabled one.
struct ButtonSample: SampleContent, ExampleContent {
    @State private var counter = 0
    @State private var confirming = false

    static let id = "button"
    static let title = "Button"
    static let summary = "A tappable button wired to a click, with an outlined "
        + "and a disabled one beside it."

    static let code = """
        @State private var counter = 0

        VStack {
            // The count is read here, so a click builds this closure again.
            DebugInfoLabel()

            Button("Increment", action: { counter += 1 })
                

            Text("Clicked \\(counter) time(s)")

            Button("Outlined", action: { counter += 1 })
                .background(.transparent)
                .stroke(Palette.accent)
                .strokeWidth(1)
                

            Button("Disabled")
                .disabled(true)

            Button("Prominent", action: { counter += 1 })
                .buttonStyle(.borderedProminent)

            Button("A link", action: { counter += 1 })
                .buttonStyle(.link)
                .help("Counts as a click, dressed as a link")
        }
        """

    var body: some View {
        VStack {
            DebugInfoLabel()

            Button("Increment", action: { counter += 1 })
                .background(Palette.accent)
                .foregroundStyle(.white)
                .shape(.roundedRectangle(8))
                .padding(EdgeInsets(20, 10))
                .horizontalAlignment(.center)
                

            Text("Clicked \(counter) time(s)")
                .font(.system(size: 15))
                .multilineTextAlignment(.center)

            Button("Outlined", action: { counter += 1 })
                .background(.transparent)
                .foregroundStyle(Palette.accent)
                .stroke(Palette.accent)
                .strokeWidth(1)
                .shape(.roundedRectangle(8))
                .padding(EdgeInsets(20, 10))
                .horizontalAlignment(.center)
                

            Button("Disabled")
                .disabled(true)
                .padding(EdgeInsets(20, 10))
                .horizontalAlignment(.center)

            // `.buttonStyle` is a logical look, not a platform widget: each
            // host maps it to its own native control.
            Button("Prominent", action: { counter += 1 })
                .buttonStyle(.borderedProminent)

            Button("Plain", action: { counter += 1 })
                .buttonStyle(.plain)

            Button("A link", action: { counter += 1 })
                .buttonStyle(.link)
                .help("Counts as a click, dressed as a link")

            // A key that clicks the button from anywhere in the window, and
            // the platform's own dialog while the binding holds.
            Button("Reset (⌘R)", action: { confirming = true })
                .keyboardShortcut("r")
                .alert("Reset the count?", isPresented: $confirming) {
                    Button("Reset", role: .destructive) { counter = 0 }
                    Button("Keep", role: .cancel) {}
                } message: {
                    Text("This puts the count back to zero.")
                }
        }
        .spacing(12)
    }

    var notes: (any View)? {
        Text("Also `.onPressed` and `.onReleased`, for the moment the button goes "
            + "down and comes up. `.buttonStyle` maps to the platform's own "
            + "button kinds; `.help` is its tooltip.")
            .font(.system(size: 12))
            .foregroundStyle(Palette.subtle)
    }
}
