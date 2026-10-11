import SwiftOmniUI

/// One choice out of a list, its choice kept two-way as a value.
struct PickerSample: SampleContent, ExampleContent {
    @State private var size = 1
    @State private var changes = 0

    static let id = "picker"
    static let title = "Picker"
    static let summary = "One choice out of a list, with the choice kept as a binding."

    static let sizes = ["Small", "Medium", "Large"]

    static let code = """
        @State private var size = 1
        @State private var changes = 0

        static let sizes = ["Small", "Medium", "Large"]

        VStack {
            // The choice and the count are read here, so a pick builds this
            // closure - and a write of OURS raises no event at all.

            Picker("Size", selection: $size) {
                ForEach(0 ..< Self.sizes.count, id: \\.self) { i in
                    Text(Self.sizes[i]).tag(i)
                }
            }
            .onChange(of: size) { changes += 1 }

            Text("Chosen: \\(Self.sizes[size])")
            Text("Changed \\(changes)x")
        }
        """

    var body: some View {
        VStack {

            Picker("Size", selection: $size) {
                ForEach(0 ..< Self.sizes.count, id: \.self) { i in
                    Text(Self.sizes[i]).tag(i)
                }
            }
            .accessibilityIdentifier("picker.size")
            .accessibilityLabel("Size")
            .onChange(of: size) { changes += 1 }

            Text("Chosen: \(Self.sizes[size])")
                .font(.system(size: 17))
                .multilineTextAlignment(.center)

            Text("Changed \(changes)x")
                .font(.system(size: 13))
                .multilineTextAlignment(.center)

            // `.pickerStyle` is a logical look: segmented where the platform
            // has such a control, a sensible fallback where it has none.
            Picker("Size", selection: $size) {
                ForEach(0 ..< Self.sizes.count, id: \.self) { i in
                    Text(Self.sizes[i]).tag(i)
                }
            }
            .pickerStyle(.segmented)
            .help("The same choice, presented as segments")
        }
        .spacing(12)
    }

    var notes: (any View)? {
        VStack {
            Text("Each choice is a tagged `Text`; the selection state holds the tag of "
                + "the chosen one, so `size` IS the choice - the field reads it and "
                + "writes it both ways.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("`$size` and `.onChange` are one event written twice: the binding "
                + "carries the value, and the handler written beside it still runs - "
                + "whichever order the two are written in.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(12)
    }
}
