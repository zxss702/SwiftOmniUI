import SwiftOmniUI

/// A window FOR A VALUE: one per swatch number, the number lent to the window
/// as its own - so writing it makes the same window about another swatch, and
/// the system restores the window for the number it was left on. See
/// `MultiWindowSample`.
struct SwatchWindow: WindowScene {
    /// Which swatch the window is for - its value, lent by its group.
    @Binding var number: Int

    var page: any Page { SwatchPage(number: $number) }
}

/// One swatch: its colour, its number, and a way on to the next.
struct SwatchPage: View {
    /// The window's own value.
    @Binding var number: Int

    /// The window this is the page of - named for its swatch, and closed from
    /// here.
    @Environment private var window: WindowSession

    /// The page itself - its padding.
    @Environment private var page: PageSession

    var body: some View {
        VStack {
            ColorPicker()
                .color(SwatchPage.colour(of: number))
                .frame(height: 150)
                .cornerRadius(12)

            Text("Swatch \(number)")
                .font(.system(size: 20))
                .bold()
                .horizontalAlignment(.center)

            HStack {
                Button("Next", action: { number += 1 })
                    .font(.system(size: 13))
                    .padding(EdgeInsets(14, 6))
                    

                Button("Done", action: { try await window.close() })
                    .font(.system(size: 13))
                    .padding(EdgeInsets(14, 6))
                    
            }
            .spacing(10)
            .horizontalAlignment(.center)
        }
        .spacing(14)
        .onAppear {
            page.contentPadding = EdgeInsets(16)

            window.title = "Swatch \(number)"
            window.width = 300
            window.height = 340
            window.minimumWidth = 240
            window.minimumHeight = 280
        }
        // A written number makes the same window about another swatch, so its
        // name follows.
        .onChange(of: number) { window.title = "Swatch \(number)" }
    }

    /// The colour of a swatch - the gallery's accents, in turn.
    static func colour(of number: Int) -> Color {
        let accents = AccentChoice.allCases
        let index = ((number - 1) % accents.count + accents.count) % accents.count
        return accents[index].color
    }
}
