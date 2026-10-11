import SwiftOmniUI

/// The two non-wrapping stack directions.
struct StackLayoutSample: SampleContent, ExampleContent {
    static let id = "stackLayout"
    static let title = "Stack layouts"
    static let summary = "Children top to bottom or left to right."

    static let code = """
        VStack {
            StackCell(text: "One")
            StackCell(text: "Two")
            StackCell(text: "Three")
        }
        .spacing(8)

        HStack {
            StackCell(text: "One")
            StackCell(text: "Two")
            StackCell(text: "Three")
        }
        .spacing(8)

        // Where a child sits in the room its stack gives it.
        VStack {
            StackCell(text: "start")
                .frame(maxWidth: .infinity, alignment: .leading)

            StackCell(text: "center")

            StackCell(text: "end")
                .frame(maxWidth: .infinity, alignment: .trailing)

            StackCell(text: "fill")
                .frame(maxWidth: .infinity)
        }
        .spacing(8)

        private struct StackCell: View {
            let text: String

            var body: some View {
                Text(text)
                    .foregroundStyle(.white)
                    .background(Palette.accent)
                    .padding(EdgeInsets(14, 8))
            }
        }
        """

    var body: some View {
        VStack {
            SectionTitle("Vertical")

            VStack {
                StackCell(text: "One")
                StackCell(text: "Two")
                StackCell(text: "Three")
            }
            .spacing(8)

            SectionTitle("Horizontal")

            HStack {
                StackCell(text: "One")
                StackCell(text: "Two")
                StackCell(text: "Three")
            }
            .spacing(8)

            SectionTitle("Alignment")

            VStack {
                StackCell(text: "start")
                    .frame(maxWidth: .infinity, alignment: .leading)

                StackCell(text: "center")

                StackCell(text: "end")
                    .frame(maxWidth: .infinity, alignment: .trailing)

                StackCell(text: "fill")
                    .frame(maxWidth: .infinity)
            }
            .spacing(8)
        }
        .spacing(12)
    }

    var notes: (any View)? {
        Text("`.horizontalAlignment` places a child across the room its stack gives it.")
            .font(.system(size: 12))
            .foregroundStyle(Palette.subtle)
    }
}

/// One block of colour with a word in it, so an arrangement is visible.
private struct StackCell: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .background(Palette.accent)
            .padding(EdgeInsets(14, 8))
            .multilineTextAlignment(.center)
    }
}
