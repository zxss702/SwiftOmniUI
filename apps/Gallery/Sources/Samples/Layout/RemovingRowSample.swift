import SwiftOmniUI

/// A row taken away, and the stack closing over it.
struct RemovingRowSample: SampleContent, ExampleContent {
    static let id = "removingRow"
    static let title = "Removing a row"
    static let summary = "A row fades where it stands, and the stack closes over it."

    /// The rows, and which of them have gone.
    static let rows = ["Milk", "Bread", "Coffee", "Apples", "Butter", "Rice"]

    @State private var gone: Set<String> = []
    @State private var atOnce: Set<String> = []
    @State private var slow = false

    static let code = """
        static let rows = ["Milk", "Bread", "Coffee", "Apples", "Butter", "Rice"]

        @State private var gone: Set<String> = []
        @State private var atOnce: Set<String> = []
        @State private var slow = false

        // A PLAIN VStack. Nothing here ASKS for animation: the row is HIDDEN,
        // which fades it where it stands, and the rows under it are then given
        // new places - which is somewhere they travel to. The one line about
        // animation is the switch turning it OFF.
        VStack {
            // INSIDE the stack's own braces, because that is where `gone` and
            // `atOnce` are read: deleting a row builds this closure, and a
            // reading taken outside it would be about a stack the delete never
            // rebuilds.

            ForEach(Self.rows, id: \\.self) { row in
                HStack {
                    Text(row)

                    Spacer()

                    Button("Delete", action: { remove(row) })
                }
                .hidden(gone.contains(row) || atOnce.contains(row))
                // What the switch below chooses: a row told to travel at NO
                // animation goes at once, and the stack still closes over it.
                .animation(atOnce.contains(row) ? nil : .default)
            }
        }

        SwitchRow("The row fades first", $slow)

        Button("Bring them back", action: {
            gone.removeAll()
            atOnce.removeAll()
        })

        /// Takes a row away - fading it where it stands, or at once.
        private func remove(_ row: String) {
            if slow {
                gone.insert(row)
            } else {
                atOnce.insert(row)
            }
        }
        """

    var body: some View {
        VStack {
            VStack {
                // INSIDE the stack's own braces, because that is where `gone`
                // and `atOnce` are read: deleting a row builds this closure,
                // and a reading taken outside it would be about a stack the
                // delete never rebuilds.

                ForEach(Self.rows, id: \.self) { row in
                    HStack {
                        Text(row)
                            .font(.system(size: 15))

                        Spacer()

                        Button("Delete", action: { remove(row) })
                            .font(.system(size: 12))
                            .padding(EdgeInsets(10, 4))
                    }
                    .padding(EdgeInsets(14, 6))
                    .background(Palette.raised)
                    .frame(height: 46)
                    .hidden(gone.contains(row) || atOnce.contains(row))
                    // The other half of the sample: a row told to travel at no
                    // animation goes at once, and the stack still closes over it.
                    .animation(atOnce.contains(row) ? nil : .default)
                }
            }
            .spacing(6)

            SwitchRow("The row fades first", $slow)

            Button("Bring them back", action: {
                gone.removeAll()
                atOnce.removeAll()
            })
        }
        .spacing(12)
    }

    /// Takes a row away - fading it where it stands, or at once.
    private func remove(_ row: String) {
        if slow {
            gone.insert(row)
        } else {
            atOnce.insert(row)
        }
    }

    var notes: (any View)? {
        VStack {
            Text("Delete a row. It FADES where it stands and the rows under it "
                + "then close over the gap - a plain `VStack`, and not a line in "
                + "the example ASKING for animation: the row is hidden, and the "
                + "ones below it are given new places.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("`The row fades first` chooses how the row itself leaves. "
                + "Turned off, the row is told `.animation(nil)` and goes at "
                + "once - the stack still closes over it, because where a "
                + "child sits is always somewhere it travels to.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("`Bring them back` is the same thing the other way round: the "
                + "rows appear at nothing and come up while everything below "
                + "them moves down to make room.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(8)
    }
}
