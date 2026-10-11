import SwiftOmniUI

/// A layout whose children travel to their new places when the layout changes.
struct LivingLayoutSample: SampleContent, ExampleContent {
    static let id = "livingLayout"
    static let title = "A layout that moves"
    static let summary = "Insert, remove or reorder, and everything else slides to its new place."

    @State private var rows = ["Alpha", "Bravo", "Charlie"]
    @State private var next = 4
    @State private var wide = false

    static let names = ["Delta", "Echo", "Foxtrot", "Golf", "Hotel", "India"]

    static let code = """
        @State private var rows = ["Alpha", "Bravo", "Charlie"]
        @State private var next = 4
        @State private var wide = false

        let names = ["Delta", "Echo", "Foxtrot", "Golf", "Hotel", "India"]

        // NOTHING HERE SAYS "ANIMATE". Where a child sits is worked out by the
        // layout; what carries it from the old place to the new one is the
        // host's engine, so an insert slides everything under it down.
        VStack {
            // `wide` is read in THESE braces - the frames below ask
            // it - so widening the row builds this closure. What the rows do
            // is counted by the reading inside their own stack.

            VStack {
                // INSIDE these braces, because that is where `rows` is read:
                // Add, Remove and Shuffle build this closure, and the views
                // left standing keep their controls.

                ForEach(rows, id: \\.self) { name in
                    ZStack { Text(name) }.style("Card")
                }
            }

            HStack {
                Button("Add", action: {
                    rows.insert(names[next % names.count], at: 0)
                    next += 1
                })
                Button("Remove", action: {
                    if !rows.isEmpty { rows.removeLast() }
                })
                Button("Shuffle", action: { rows.shuffle() })
            }

            // A row whose cell widths change: every child crosses to its new
            // share of the room, because a frame is a frame whoever worked it
            // out.
            HStack {
                Text("one").frame(maxWidth: wide ? .infinity : 110)
                Text("two").frame(maxWidth: .infinity)
                Text("three").frame(maxWidth: wide ? 110 : .infinity)
            }

            Button("Widen the other end", action: { wide.toggle() })
        }
        """

    var body: some View {
        VStack {
            // `wide` is read in THESE braces - the frames below ask
            // it - so widening the row builds this closure. What the rows do
            // is counted by the reading inside their own stack.

            Text("A stack")
                .font(.system(size: 11))
                .tracking(1)
                .foregroundStyle(Palette.subtle)

            VStack {
                // INSIDE these braces, because that is where `rows` is read:
                // Add, Remove and Shuffle build this closure, and the views
                // left standing keep their controls.

                ForEach(rows, id: \.self) { name in
                    ZStack {
                        Text(name)
                            .font(.system(size: 15))
                    }
                    .style("Card")
                    .padding(EdgeInsets(12, 8, 12, 8))
                    .background(Palette.raised)
                    .stroke(.transparent)
                    .frame(height: 40)
                }
            }
            .spacing(6)

            HStack {
                Button("Add", action: {
                    rows.insert(Self.names[next % Self.names.count], at: 0)
                    next += 1
                })

                Button("Remove", action: {
                    if !rows.isEmpty { rows.removeLast() }
                })

                Button("Shuffle", action: { rows.shuffle() })
            }
            .spacing(8)

            Text("A grid, its columns changing width")
                .font(.system(size: 11))
                .tracking(1)
                .foregroundStyle(Palette.subtle)

            HStack {
                cell("one", Palette.brand, wide: wide)
                cell("two", Palette.accent)
                cell("three", Palette.brand, wide: !wide, faded: true)
            }
            .spacing(8)
            .frame(height: 52)

            Button("Widen the other end", action: { wide.toggle() })
        }
        .spacing(10)
    }

    private func cell(
        _ text: String, _ colour: Color, wide: Bool? = nil, faded: Bool = false
    ) -> any View {
        ZStack {
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Palette.onBrand)
        }
        .style("Card")
        .background(colour)
        .opacity(faded ? 0.55 : 1)
        .stroke(.transparent)
        .frame(width: wide == false ? 110 : nil)
        .frame(maxWidth: wide != false ? .infinity : nil)
    }

    var notes: (any View)? {
        VStack {
            Text("Add a row and the ones under it SLIDE down; remove one and "
                + "they close up; shuffle and they cross past each other. The "
                + "example says nothing about animation: it writes "
                + "`rows.insert(…)`, and the layout works out where everything "
                + "belongs the same way it would if nothing moved.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("The grid is the same thing one level up. Its columns change "
                + "width, so every child gets a new place - and a place a child "
                + "is given is somewhere it travels to. A view that ARRIVES "
                + "fades in; one that leaves goes at once and the gap closes "
                + "behind it.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("A layout's own SIZE changing is different, and deliberately: "
                + "drag the window and the children track it exactly, because a "
                + "resize is something a user is doing rather than something "
                + "the interface decided.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(8)
    }
}
