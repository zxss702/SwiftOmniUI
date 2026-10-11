import SwiftOmniUI

/// DeviceInfo and AppInfo - the two providers whose facts mostly stand still:
/// what machine this is, and what app this is.
struct DeviceInfoSample: SampleContent, ExampleContent {
    /// The machine's facts - the formFactor is the one the gallery itself builds
    /// by, listing desktop chrome only where it draws.
    @Environment var device: DeviceInfo

    /// The app's facts, from its own manifest.
    @Environment var app: AppInfo

    static let id = "deviceInfo"
    static let title = "DeviceInfo & AppInfo"
    static let summary = "What machine this is and what app this is - the "
        + "facts a layout branches on."

    static let code = """
        struct AboutBox: View {
            @Environment var device: DeviceInfo
            @Environment var app: AppInfo

            var body: some View {
                VStack {
                    // The device never changes, so this stands at one build.

                    Text("\\(app.name) \\(app.versionString) "
                        + "(\\(app.buildString))")
                    Text(app.packageName)

                    Text("\\(device.manufacturer) \\(device.model)")
                    Text("\\(device.platform) \\(device.versionString) · "
                        + "\\(device.formFactor) · \\(device.deviceType)")
                    Text(device.name.isEmpty ? "not said" : device.name)
                }
            }
        }
        """

    var body: some View {
        VStack {

            Text("\(app.name) \(app.versionString) (\(app.buildString))")
                .font(.system(size: 22))
                .bold()
                .multilineTextAlignment(.center)

            Text(app.packageName)
                .font(.system(size: 15))

            Text("device · \(device.manufacturer) \(device.model)")
                .font(.system(size: 15))
            Text("system · \(device.platform) \(device.versionString)")
                .font(.system(size: 15))
            Text("formFactor · \(device.formFactor), \(device.deviceType)")
                .font(.system(size: 15))
            Text("name · \(device.name.isEmpty ? "not said" : device.name)")
                .font(.system(size: 15))
        }
        .spacing(10)
    }

    var notes: (any View)? {
        VStack {
            Text("The formFactor is the value this gallery itself builds by: the "
                + "window wears a title bar and lists the TitleBar sample only "
                + "where device.formFactor answers .desktop. It is known BEFORE the "
                + "first render, so the first tree already has it - which "
                + "pages exist is decided while the tree is built.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("Headless - a test, a host that could not say - everything "
                + "here answers its default, .unknown included, which the "
                + "catalog reads as \"show everything\".")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(10)
    }
}
