import Foundation
import SwiftOmniUI
import SwiftOmniUIFoundation

/// `.onOpenURL`: the URLs the platform hands the application, answered here.
struct OpenURLSample: SampleContent, ExampleContent {
    /// The last URL the platform handed over, and how many have arrived.
    @State private var last = "Nothing handed over yet."
    @State private var count = 0

    static let id = "open-url"
    static let title = "Opening URLs"
    static let summary = "A document or link the platform hands the app reaches .onOpenURL."

    static let code = """
        @State private var last = "Nothing handed over yet."

        Text(last)
            .onOpenURL { url in
                last = url.absoluteString
            }
        """

    var notes: (any View)? {
        VStack {
            Text("Drop a file onto the gallery's icon, open a document the app "
                + "owns, or follow a gallery:// link and the URL lands here - "
                + "a link the browser owns answers first.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("The nearest `.onOpenURL` listening answers. Declared once "
                + "under the window's root it hears every URL; a deeper one "
                + "would answer first.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(12)
    }

    var body: some View {
        VStack {
            Image(systemName: {
                #if os(Windows)
                return "\u{E71B}"
                #else
                return "chain-link-symbolic"
                #endif
            }())
            .tint(Palette.accent)

            Text(last)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Palette.accent)
                .multilineTextAlignment(.center)

            if count > 0 {
                Text("\(count) received")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.subtle)
            }
        }
        .spacing(10)
        .onOpenURL { url in
            last = url.absoluteString
            count += 1
        }
        .accessibilityIdentifier("openURL.listener")
    }
}
