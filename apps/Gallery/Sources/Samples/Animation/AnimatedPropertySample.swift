import SwiftOmniUI

/// A colour, a size, a padding and a font size, each read off a state the host
/// moves on its own frames.
struct AnimatedPropertySample: SampleContent, ExampleContent {
    @State private var wide = false

    @State private var panelColor = AppColors.lineDark
    @State private var panelHeight = 90.0
    @State private var panelPadding = EdgeInsets(16)
    @State private var captionColor = AppColors.ink
    @State private var captionSize = 17.0

    static let id = "animatedProperty"
    static let title = "Animated properties"
    static let summary = "A colour, a size and a padding carried to a new value by the host."

    static let code = """
        @State private var wide = false

        @State private var panelColor = AppColors.lineDark
        @State private var panelHeight = 90.0
        @State private var panelPadding = EdgeInsets(16)
        @State private var captionColor = AppColors.ink
        @State private var captionSize = 17.0

        VStack {
            // Every property below is driven, and `wide` is read by the
            // handler alone - so this stands at one build while five of them
            // travel at once.
            DebugInfoLabel()

            ZStack {
                Text("A property, carried")
                    .fontSize($captionSize)
                    .foregroundStyle($captionColor)
            }
            .style("Card")
            .background($panelColor)
            .padding($panelPadding)
            .frame(height: $panelHeight)

            Button("Colour", action: {
                try await $panelColor.journey.move(to: AppColors.swiftOrangeDeep, .easeOut(duration: 0.5))
                try await $captionColor.journey.move(to: AppColors.white, .easeOut(duration: 0.5))
            })

            Button("Size", action: {
                wide.toggle()
                try await $panelHeight.journey.move(to: wide ? 160 : 90,
                                                 .easeInOut(duration: 0.4))
            })

            Button("Padding", action: {
                try await $panelPadding.journey.move(to: EdgeInsets(48), .easeOut(duration: 0.4))
                try await $panelPadding.journey.move(to: EdgeInsets(16), .easeOut(duration: 0.4))
            })

            Button("Text size", action: {
                try await $captionSize.journey.move(to: 28, .easeOut(duration: 0.4))
                try await $captionSize.journey.move(to: 17, .easeIn(duration: 0.4))
            })

            Button("Back", action: {
                // EVERYTHING THE OTHER BUTTONS LEAVE CHANGED - the height and
                // the two colours. The padding and the text size send
                // themselves back, so there is nothing here for them; and
                // `wide` is put right with the height, or the next press of
                // Size would ask for the value it already has.
                wide = false

                try await $panelHeight.journey.move(to: 90, .easeInOut(duration: 0.4))
                try await $panelColor.journey.move(to: AppColors.lineDark, .easeOut(duration: 0.4))
                try await $captionColor.journey.move(to: AppColors.ink, .easeOut(duration: 0.4))
            })
        }
        """

    var body: some View {
        VStack {
            DebugInfoLabel()

            ZStack {
                Grid {
                    Text("A property, carried")
                        .fontSize($captionSize)
                        .foregroundStyle($captionColor)
                        .horizontalAlignment(.center)
                        .verticalAlignment(.center)
                }
                .background(AppColors.violetLight)
            }
            .style("Card")
            .background($panelColor)
            .padding($panelPadding)
            .frame(height: $panelHeight)
            .stroke(.transparent)
            .shape(.roundedRectangle(12))

            HStack {
                button("Colour") {
                    try await $panelColor.journey.move(to: AppColors.swiftOrangeDeep, .easeOut(duration: 0.5))

                    // The caption sits on the brand field inside the panel
                    // rather than on the panel itself, so what it goes to is
                    // the colour that reads on the brand.
                    try await $captionColor.journey.move(to: AppColors.white, .easeOut(duration: 0.5))
                }

                button("Size") {
                    wide.toggle()
                    try await $panelHeight.journey.move(to: wide ? 160 : 90,
                                                     .easeInOut(duration: 0.4))
                }

                button("Padding") {
                    try await $panelPadding.journey.move(to: EdgeInsets(48), .easeOut(duration: 0.4))
                    try await $panelPadding.journey.move(to: EdgeInsets(16), .easeOut(duration: 0.4))
                }
            }
            .spacing(8)
            .horizontalAlignment(.center)

            HStack {
                button("Text size") {
                    try await $captionSize.journey.move(to: 28, .easeOut(duration: 0.4))
                    try await $captionSize.journey.move(to: 17, .easeIn(duration: 0.4))
                }

                button("Back") {
                    // EVERYTHING THE OTHER BUTTONS LEAVE CHANGED - the height
                    // and the two colours. The padding and the text size send
                    // themselves back, so there is nothing here for them; and
                    // `wide` is put right with the height, or the next press
                    // of Size would ask for the value it already has.
                    wide = false

                    try await $panelHeight.journey.move(to: 90, .easeInOut(duration: 0.4))
                    try await $panelColor.journey.move(to: AppColors.lineDark, .easeOut(duration: 0.4))
                    try await $captionColor.journey.move(to: AppColors.ink, .easeOut(duration: 0.4))
                }
            }
            .spacing(8)
            .horizontalAlignment(.center)
        }
        .spacing(12)
    }

    var notes: (any View)? {
        VStack {
            Text("Each button moves a bound property on host frames. The build "
                + "counter stays still while colour, size, padding and text move.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("Size moves the panel between 90 and 160 points. Back restores "
                + "the values that remain after their journeys.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(12)
    }

    /// One of the buttons, all of which look the same.
    private func button(_ caption: String, _ act: @escaping EventHandler) -> Button {
        Button(caption, action: act)
            .font(.system(size: 13))
            .padding(EdgeInsets(14, 6))
            
    }
}
