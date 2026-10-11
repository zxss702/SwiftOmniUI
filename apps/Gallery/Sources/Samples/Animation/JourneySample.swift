import SwiftOmniUI

/// A value that changes TRAVELS - the default, and the three laws it can travel
/// under.
struct JourneySample: SampleContent, ExampleContent {
    static let id = "journeys"
    static let title = "Journeys"
    static let summary = "Assign the state and the control travels there - at a length, on a spring, or not at all."

    static let laws = ["Default", "Spring", "Long and slow", "None"]

    static func law(_ index: Int) -> Animation? {
        switch index {
        case 1: .spring(response: 0.32)
        case 2: .easeInOut(duration: 0.9)
        case 3: nil
        default: .default
        }
    }

    @State private var law = 2
    @State private var wide = false
    @State private var warm = false

    static let code = """
        @State private var law = 2
        @State private var wide = false
        @State private var warm = false

        static let laws = ["Default", "Spring", "Long and slow", "None"]

        static func law(_ index: Int) -> Animation? {
            switch index {
            case 1: .spring(response: 0.32)
            case 2: .easeInOut(duration: 0.9)
            case 3: nil
            default: .default
            }
        }

        // NOTHING HERE SAYS "ANIMATE". A value that changes is a setpoint: the
        // tree says where the panel is going and the host carries it there.
        VStack {
            // The panels are described from `wide`, `warm` and `law`, read
            // here, so a press builds this closure once and the host walks
            // the rest.

            ColorPicker()
                .color(warm ? Palette.accent : Palette.brand)
                .frame(width: wide ? 300 : 120)
                .frame(height: wide ? 120 : 60)
                .cornerRadius(wide ? 32 : 8)
                .animation(Self.law(law))

            // The same panel, told to stay still. `.animation` is per view.
            ColorPicker()
                .color(warm ? Palette.accent : Palette.brand)
                .frame(width: wide ? 300 : 120)
                .frame(height: wide ? 120 : 60)
                .cornerRadius(wide ? 32 : 8)
                .animation(nil)

            // And the same panel again, with a rule: everything travels
            // EXCEPT how big it is, which arrives. The last rule that names a
            // value is the one that answers for it.
            ColorPicker()
                .color(warm ? Palette.accent : Palette.brand)
                .frame(width: wide ? 300 : 120)
                .frame(height: wide ? 120 : 60)
                .cornerRadius(wide ? 32 : 8)
                .animation(Self.law(law))
                .animation(nil, value: wide)

            HStack {
                Button("Size", action: { wide.toggle() })
                Button("Colour", action: { warm.toggle() })
                Button(Self.laws[law], action: { law = (law + 1) % Self.laws.count })
            }
        }
        """

    var body: some View {
        VStack {

            Text("A change that travels")
                .font(.system(size: 11))
                .tracking(1)
                .foregroundStyle(Palette.subtle)

            panel(travels: true)

            Text("The same, told to stay still")
                .font(.system(size: 11))
                .tracking(1)
                .foregroundStyle(Palette.subtle)

            panel(travels: false)

            Text("The same, holding only its size still")
                .font(.system(size: 11))
                .tracking(1)
                .foregroundStyle(Palette.subtle)

            sized()

            HStack {
                Button("Size", action: { wide.toggle() })
                Button("Colour", action: { warm.toggle() })
                Button(Self.laws[law], action: { law = (law + 1) % Self.laws.count })
            }
            .spacing(8)
        }
        .spacing(10)
    }

    /// One panel, either travelling at the chosen law or arriving at once.
    private func panel(travels: Bool) -> any View {
        ColorPicker()
            .color(warm ? Palette.accent : Palette.brand)
            .frame(width: wide ? 300 : 120)
            .frame(height: wide ? 110 : 56)
            .cornerRadius(wide ? 28 : 8)
            .animation(travels ? Self.law(law) : nil)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The same panel with a RULE: everything travels except how big it is.
    private func sized() -> any View {
        ColorPicker()
            .color(warm ? Palette.accent : Palette.brand)
            .frame(width: wide ? 300 : 120)
            .frame(height: wide ? 110 : 56)
            .cornerRadius(wide ? 28 : 8)
            .animation(Self.law(law))
            .animation(nil, value: wide)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var notes: (any View)? {
        VStack {
            Text("Press Size or Colour. The first panel travels, the second "
                + "arrives immediately, and the third holds only its size still.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("Change the law to compare eased, spring, slow and immediate "
                + "animation. SwiftOmniUI sends destinations; the host supplies the frames.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(8)
    }
}
