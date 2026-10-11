import Foundation
import SwiftOmniUI
import SwiftOmniUIFoundation

/// `Text(AttributedString)`: runs keep the look the string wrote for them.
struct AttributedTextSample: SampleContent, ExampleContent {
    static let id = "attributed-text"
    static let title = "Attributed text"
    static let summary = "An AttributedString's runs shown with each run's own look."

    static let code = """
        let words = try? AttributedString(
            markdown: "**Bold** words, _italic_ ones, ~~struck~~ ones and `code`.")

        Text(words ?? AttributedString("plain"))
        """

    var notes: (any View)? {
        VStack {
            Text("Markdown's **bold**, _italic_, ~~strike~~ and `code` arrive as "
                + "presentation intents on Apple's platforms; the free-standing "
                + "Foundation carries a string's runs and its link attribute.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(12)
    }

    var body: some View {
        VStack {
            Text(Self.rich ?? AttributedString("plain text"))
                .font(.system(size: 16))
        }
        .spacing(12)
    }

    /// The attributed string the page draws: the free-standing Foundation
    /// names the link attribute alone, so the runs are composed - keeping the
    /// look the string wrote.
    private static var rich: AttributedString? {
        var link = AttributeContainer()
        link.link = URL(string: "https://swiftomniui.dev")
        return AttributedString("SwiftOmniUI shows attributed runs - ")
            + AttributedString("a link", attributes: link)
            + AttributedString(" beside plain words.")
    }
}
