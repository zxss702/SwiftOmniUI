import SwiftOmniUI

/// A page pushed for one thing chosen from the search box.
///
/// What it shows arrives as a VALUE of the route - `.item("Alpha")` - which is
/// what lets two of these be on the stack at once showing different things.
/// The value never crosses to the host: the host is sent the page built from
/// it, and knows nothing about routes or their arguments.
struct ItemPage: View {
    /// The gallery this page is in - the scene its inspector button opens.
    @Environment var scene: SceneSession

    /// The page itself - what it is called, and its buttons.
    @Environment private var page: PageSession

    let item: String

    let nav: Navigation

    /// The stack this page is on, so "Back" takes it off.
    @Binding var path: [Route]

    var body: some View {
        ZStack {
            VStack {
                SectionTitle("Pushed page")

                Text(item.isEmpty ? "Nothing selected" : item)
                    .font(.system(size: 28))
                    .bold()
                    .multilineTextAlignment(.center)

                Text("Pushed by `path.append(.item(\"\(item)\"))`.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.subtle)
                    .multilineTextAlignment(.center)

                Button("Back", action: { path.removeLast() })
                    .padding(EdgeInsets(20, 10))
                    .horizontalAlignment(.center)
                    
            }
            .spacing(16)
        }
        .style("Card")
        .padding(24)
        .padding(24)
        .background(Palette.surface)
        .stroke(.transparent)
        .shape(.roundedRectangle(12))
        .verticalAlignment(.center)
        .onAppear {
            page.gallery(item.isEmpty ? "Item" : item, scene: scene, nav: nav)
        }
    }
}
