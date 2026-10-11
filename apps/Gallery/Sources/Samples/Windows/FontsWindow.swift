import SwiftOmniUI

/// The window a gallery chooses its font in - a window OF THE GALLERY that
/// opened it: it closes with that gallery, may step aside for another, and
/// changes what this gallery shows and no other. See `MultiWindowSample`.
struct FontsWindow: WindowScene {
    var page: any Page { FontsPage() }
}

/// The families on offer, each set in itself.
struct FontsPage: View {
    /// The gallery's look - the one its scene offers every window of it.
    @Environment private var style: SessionStyle

    /// The window this is the page of - what it is called, and how big.
    @Environment private var window: WindowSession

    /// The page itself - what it is called, and its padding.
    @Environment private var page: PageSession

    /// Families every desktop this gallery runs on has; empty is the
    /// platform's own.
    static let families = ["", "Georgia", "Courier New", "Trebuchet MS"]

    var body: some View {
        VStack {
            Text("The font this gallery's preview is set in.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.subtle)

            ForEach(FontsPage.families) { family in
                let chosen = style.font == family
                let button = Button(family.isEmpty ? "The platform's own" : family, action: { style.font = family })
                    .font(.system(size: 15))
                    .foregroundStyle(chosen ? .white : Palette.text)
                    .background(chosen ? style.accent.color : .transparent)
                    .stroke(chosen ? .transparent : Palette.subtle)
                    .shape(.roundedRectangle(8))
                    .padding(EdgeInsets(14, 8))
                    

                return family.isEmpty ? button : button.font(.custom(family, size: 15))
            }

            // The window closes itself, through its own session.
            Button("Done", action: { try await window.close() })
                .font(.system(size: 13))
                .padding(EdgeInsets(14, 6))
                .frame(maxWidth: .infinity, alignment: .trailing)
                
        }
        .spacing(10)
        .onAppear {
            page.title = "Fonts"
            page.contentPadding = EdgeInsets(16)

            window.title = "Fonts"
            window.width = 320
            window.height = 380
            window.minimumWidth = 260
            window.minimumHeight = 260
        }
    }
}
