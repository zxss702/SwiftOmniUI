import SwiftOmniUI

/// The first tab of the tabs demonstration - the one holding a stack of its own.
///
/// It is the ROOT of a `NavigationStack` that lives inside a `TabView`, and
/// that `TabView` is the detail of the same split view every other section
/// is shown in. All three are pages, and pages nest - so a tab may hold a
/// stack, and the stack it holds is its own array.
struct TabsPage: View {
    /// The gallery this page is in - the scene its inspector button opens.
    @Environment var scene: SceneSession

    /// The page itself - what it is called, and its buttons.
    @Environment private var page: PageSession

    let nav: Navigation

    /// This TAB's own stack - a different array from the gallery's, which is
    /// the whole of why each tab keeps its place.
    @Binding var path: [Route]

    var body: some View {
        ScrollView {
            VStack {
                SectionTitle("A section arranged as tabs")

                Text("A TabView of two")
                    .font(.system(size: 26))
                    .bold()

                Text("Push a page, change tabs, come back: it is still on top.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.subtle)

                Button("Push a page onto this tab", action: { path.append(.level(1)) })
                    .background(Palette.accent)
                    .foregroundStyle(.white)
                    .shape(.roundedRectangle(8))
                    .padding(EdgeInsets(20, 10))
                    

                Text("Depth here: \(path.count)")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Palette.accent)
                    .multilineTextAlignment(.center)

                TabsControls(nav: nav, thisTab: .stack)

                // One move, landing where it says: the section becomes home
                // and the group is pushed onto it, so the back button leads
                // home from there.
                Button("Back to the Navigation samples", action: { nav.openGroup("navigation") })
                    .padding(EdgeInsets(20, 10))
                    
            }
            .spacing(14)
            .padding(24)
        }
        .onAppear { page.gallery("Tabs", scene: scene, nav: nav) }
    }
}
