import SwiftOmniUI

/// A page the toolbar's layers push: its own actions on the bar while it is shown, and a way one page deeper.
///
/// Its actions stand nearer the title than the gallery's, which keep their place at the edge; going back takes them
/// away with the page, and the bar stands as it stood before the push.
struct ToolbarLayerPage: View {
    /// The gallery this page is in - the scene its inspector button opens.
    @Environment var scene: SceneSession

    /// The page itself - what it is called, and its buttons.
    @Environment private var page: PageSession

    /// How deep it stands, from 1.
    let depth: Int

    /// Where the gallery is - a deeper page still pushes onto the same stack.
    let nav: Navigation

    /// The stack this page is on, which "Deeper" pushes onto.
    @Binding var path: [Route]

    /// How many times this page's Share was pressed.
    @State private var shared = 0

    var body: some View {
        VStack {
            Text("Layer \(depth)")
                .font(.system(size: 28))
                .bold()

            Text("Shared \(shared) time(s)")
                .font(.system(size: 14))
                .foregroundStyle(Palette.subtle)

            Text("Go back and this page's actions leave with it.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(12)
        .padding(24)
        .toolbar {
            ToolbarItem("Share") { shared += 1 }
                .id("layer.share")
                .accessibilityIdentifier("layer.share")

            ToolbarItem("Deeper") { path.append(.layer(depth + 1)) }
                .id("layer.deeper")
                .accessibilityIdentifier("layer.deeper")
        }
        .onAppear { page.gallery("Layer \(depth)", scene: scene, nav: nav) }
    }
}
