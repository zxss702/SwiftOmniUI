import SwiftOmniUI

/// The window a gallery chooses its accent in - a window OF THE GALLERY that
/// opened it, painting that gallery's bars and no other's. See
/// `MultiWindowSample`.
struct ColoursWindow: WindowScene {
    var page: any Page { ColoursPage() }
}

/// The accents on offer, each drawn in itself.
struct ColoursPage: View {
    /// The gallery's look - the one its scene offers every window of it.
    @Environment private var style: SessionStyle

    /// The window this is the page of - what it is called, and how big.
    @Environment private var window: WindowSession

    /// The page itself - what it is called, and its padding.
    @Environment private var page: PageSession

    var body: some View {
        VStack {
            Text("The accent this gallery's bars are painted in.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.subtle)

            ForEach(AccentChoice.allCases) { accent in
                Button(style.accent == accent ? "✓  \(accent.name)" : accent.name, action: { style.accent = accent })
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .background(accent.color)
                    .shape(.roundedRectangle(8))
                    .padding(EdgeInsets(14, 8))
                    
            }

            // The window closes itself, through its own session.
            Button("Done", action: { try await window.close() })
                .font(.system(size: 13))
                .padding(EdgeInsets(14, 6))
                .frame(maxWidth: .infinity, alignment: .trailing)
                
        }
        .spacing(10)
        .onAppear {
            page.title = "Colours"
            page.contentPadding = EdgeInsets(16)

            window.title = "Colours"
            window.width = 320
            window.height = 340
            window.minimumWidth = 260
            window.minimumHeight = 240
        }
    }
}
