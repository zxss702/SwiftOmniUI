import SwiftOmniUI

/// A switch bound to a flag, reporting each flip as the value it now has.
struct SwitchSample: SampleContent, ExampleContent {
    @State private var soundOn = true
    @State private var boldOn = false
    @State private var said = "not thrown yet"

    static let id = "switch"
    static let title = "Switch"
    static let summary = "An on/off toggle, reported as the value it now has."

    static let code = """
        @State private var soundOn = true
        @State private var boldOn = false
        @State private var said = "not thrown yet"

        VStack {
            // The flag is read here, so every flip builds this closure.
            DebugInfoLabel()

            HStack {
                Text("Sound")
                    .verticalAlignment(.center)

                Toggle(isOn: $soundOn)
                    // Runs beside the binding's write-back, carrying what the
                    // switch NOW is rather than what this side guessed.
                    .onChange(of: soundOn) { _, on in said = on ? "thrown on" : "thrown off" }
            }

            Text(soundOn ? "on" : "off")
            Text(said)

            // A toggle as a button that holds its pressed look.
            Toggle(isOn: $boldOn) {
                Label("Bold", systemImage: {
                    #if os(Windows)
                    return "\\u{E8DD}"
                    #else
                    return "text-bold-symbolic"
                    #endif
                }())
            }
            .toggleStyle(.button)
        }
        """

    var body: some View {
        VStack {
            DebugInfoLabel()

            HStack {
                Text("Sound")
                    .font(.system(size: 16))
                    .verticalAlignment(.center)

                Toggle(isOn: $soundOn)
                    .accessibilityIdentifier("switch.sound")
                    .accessibilityLabel("Sound on")
                    .tint(Palette.accent)
                    .onChange(of: soundOn) { _, on in said = on ? "thrown on" : "thrown off" }
            }
            .spacing(12)
            .horizontalAlignment(.center)

            // A toggle as a button that holds its pressed look - a toolbar's,
            // which is what `.toggleStyle(.button)` asks of each host.
            Toggle(isOn: $boldOn) {
                Label("Bold", systemImage: {
                    #if os(Windows)
                    return "\u{E8DD}"
                    #else
                    return "text-bold-symbolic"
                    #endif
                }())
            }
            .toggleStyle(.button)
            .accessibilityIdentifier("switch.bold")

            Text(soundOn ? "on" : "off")
                .font(.system(size: 15))
                .multilineTextAlignment(.center)

            Text(said)
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
                .multilineTextAlignment(.center)
        }
        .spacing(12)
    }

    var notes: (any View)? {
        Text("`.onChange` carries the value the switch now has, and runs after the "
            + "binding has written it - so both hold what the switch is, not what this "
            + "side guessed.")
            .font(.system(size: 12))
            .foregroundStyle(Palette.subtle)
    }
}
