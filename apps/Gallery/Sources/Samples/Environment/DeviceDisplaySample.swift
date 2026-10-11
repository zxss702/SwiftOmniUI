import SwiftOmniUI

/// The screen, its density and which way it is turned.
struct DeviceDisplaySample: SampleContent, ExampleContent {
    /// The main display, as the host measures it.
    @Environment var display: DeviceDisplay

    static let id = "deviceDisplay"
    static let title = "DeviceDisplay"
    static let summary = "The screen in pixels and points, and which way it "
        + "is turned - live through a rotation."

    static let code = """
        struct DisplayBadge: View {
            @Environment var display: DeviceDisplay

            var body: some View {
                VStack {
                    // The display is read here, so a turn or a resize builds
                    // this closure.

                    Text("\\(Int(display.width)) × \\(Int(display.height)) px")

                    Text(display.density > 0
                        ? "\\(Int(display.width / display.density)) × "
                            + "\\(Int(display.height / display.density)) pt "
                            + "at \\(display.density)x"
                        : "density not said")

                    Text("\\(display.orientation) · \\(display.rotation)")

                    Text(display.refreshRate > 0
                        ? "\\(Int(display.refreshRate)) Hz"
                        : "refresh not said")
                }
            }
        }
        """

    var body: some View {
        VStack {

            Text("\(Int(display.width)) × \(Int(display.height)) px")
                .font(.system(size: 28))
                .bold()
                .multilineTextAlignment(.center)

            Text(display.density > 0
                ? "\(Int(display.width / display.density)) × "
                    + "\(Int(display.height / display.density)) pt at "
                    + "\(display.density)x"
                : "density not said")
                .font(.system(size: 15))

            Text("orientation · \(display.orientation)")
                .font(.system(size: 15))
            Text("rotation · \(display.rotation)")
                .font(.system(size: 15))
            Text(display.refreshRate > 0
                ? "refresh · \(Int(display.refreshRate)) Hz"
                : "refresh · not said")
                .font(.system(size: 15))
        }
        .spacing(10)
    }

    var notes: (any View)? {
        Text("The host measures the screen in PIXELS; a layout speaks "
            + "points, which is width divided by density. Rotate a phone "
            + "and every number above moves in one push - orientation, "
            + "rotation, and the width and height swapping places. A "
            + "desktop usually answers `.unknown` for both, its window "
            + "being the thing that turns.")
            .font(.system(size: 12))
            .foregroundStyle(Palette.subtle)
    }
}
