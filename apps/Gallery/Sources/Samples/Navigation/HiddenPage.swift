import SwiftOmniUI

/// The page the menu does not always list - see `MenuPage`, where the row is
/// written inside an `if`.
///
/// The list is a view and the destination is a value: `.hidden` is a case of
/// an enum, so a row for it is optional in the plainest sense of the word -
/// written inside an `if`, while the page behind it stays reachable from
/// anywhere that can name the case.
struct HiddenPage: View {
    /// The gallery this page is in - the scene its inspector button opens.
    @Environment var scene: SceneSession

    /// The page itself - what it is called, and its buttons.
    @Environment private var page: PageSession

    let nav: Navigation

    var body: some View {
        ScrollView {
            VStack {
                SectionTitle("A row that is not there")

                Text("Not in the list")
                    .font(.system(size: 26))
                    .bold()

                Text("The menu lists this page only when the Split view sample's "
                    + "switch says so.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.subtle)

                Button("Back to the Navigation samples", action: { nav.openGroup("navigation") })
                    .background(Palette.accent)
                    .foregroundStyle(.white)
                    .shape(.roundedRectangle(8))
                    .padding(EdgeInsets(20, 10))
                    .horizontalAlignment(.center)
                    
            }
            .spacing(14)
            .padding(24)
        }
        .onAppear { page.gallery("Not in the list", scene: scene, nav: nav) }
    }
}
