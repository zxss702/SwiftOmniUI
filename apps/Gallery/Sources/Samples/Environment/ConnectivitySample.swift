import SwiftOmniUI

/// Whether the internet is reachable, and by what.
struct ConnectivitySample: SampleContent, ExampleContent {
    /// The network, as the host last reported it.
    @Environment var connectivity: Connectivity

    static let id = "connectivity"
    static let title = "Connectivity"
    static let summary = "Whether the internet is reachable and by what - "
        + "updated the moment it changes."

    static let code = """
        struct SaveButton: View {
            @Environment var connectivity: Connectivity

            var body: some View {
                VStack {
                    // The connection is read here, so a change to it builds
                    // this closure.

                    Text(connectivity.networkAccess == .internet
                        ? "online" : "offline · \\(connectivity.networkAccess)")

                    // A host may report one entry per ADAPTER, so repeats
                    // are collapsed for display.
                    Text("via \\(Set(connectivity.connectionProfiles
                        .map { "\\($0)" }).sorted().joined(separator: ", "))")

                    Button("Save to the cloud")
                        .disabled(connectivity.networkAccess != .internet)
                }
            }
        }
        """

    var body: some View {
        // The list is the host's answer as given, and a host may report one
        // entry per adapter, so repeats are collapsed for display and the
        // value stays untouched. Sorted, because a Set's own order changes
        // run to run.
        let profiles = Set(connectivity.connectionProfiles.map { "\($0)" })
            .sorted()
            .joined(separator: ", ")

        return VStack {

            Text(connectivity.networkAccess == .internet ? "online" : "offline")
                .font(.system(size: 34))
                .bold()
                .multilineTextAlignment(.center)

            Text("access · \(connectivity.networkAccess)")
                .font(.system(size: 15))
            Text("via · \(profiles.isEmpty ? "nothing reported" : profiles)")
                .font(.system(size: 15))

            Button("Save to the cloud")
                .disabled(connectivity.networkAccess != .internet)
                .background(Palette.accent)
                .foregroundStyle(.white)
                .shape(.roundedRectangle(8))
                .padding(EdgeInsets(20, 10))
        }
        .spacing(10)
    }

    var notes: (any View)? {
        VStack {
            Text("The button above is enabled by a READ - "
                + "`connectivity.networkAccess == .internet` - so it follows the "
                + "network with no handler anywhere. On a phone, flip airplane "
                + "mode and watch this page change twice; on Android that is "
                + "`adb shell svc wifi disable`.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("A desktop wired to Ethernet may never CHANGE, but the "
                + "values here are still the host's answer, pushed before "
                + "the first render. A host that cannot observe reachability "
                + "reports `.unknown` and no profiles.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(10)
    }
}
