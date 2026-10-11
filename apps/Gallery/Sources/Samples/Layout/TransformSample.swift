import SwiftOmniUI

/// One colour per family, so the three rows read apart at a glance rather than
/// as one long run of identical squares.
private enum Family {
    /// The two chains that differ only in the ORDER they are written in.
    static let order = Palette.accent

    /// The four ways of turning a view.
    static let turn = Palette.brand

    /// The three ways of resizing one.
    static let size = Color(light: AppColors.amber, dark: AppColors.windowYellow)
}

/// A view turned, tipped and scaled after layout, about an anchor it can move.
struct TransformSample: SampleContent, ExampleContent {
    static let id = "transform"
    static let title = "Transforms"
    static let summary = "Turning, tipping and resizing a view after it has been laid out."

    /// Whether the page wears its transforms - one switch over every example,
    /// so throwing it flies the whole page between plain squares and turned,
    /// tipped, grown ones.
    @State private var transformed = true

    static let code = """
        @State private var transformed = true

        VStack {
            // ONE SWITCH over every example below. Each transform is written
            // as a choice between itself and none, so throwing it sends the
            // whole page to its turned, grown self and back - and a changed
            // transform TRAVELS, so the boxes fly rather than jump.
            SwitchRow("Transforms", $transformed)

            // A GET IN THESE BRACES, which is what makes THIS row a reader:
            // it is built again on every throw, and its count is what that
            // costs. Each row of boxes below reads the switch in its own
            // braces, so each of them is a reader of its own.
            HStack {
                Text(transformed ? "every transform on" : "plain squares")

            }

            // THE SAME TWO MODIFIERS, in the order they are written: the move
            // lands somewhere else - written after the turn it is a plain
            // move right, written before it, the turn's centre moved with it.
            HStack {
                box(Family.order)
                    .rotationEffect(transformed ? 45 : 0)
                    .offset(x: transformed ? 28 : 0)

                box(Family.order)
                    .offset(x: transformed ? 28 : 0)
                    .rotationEffect(transformed ? 45 : 0)
            }

            HStack {
                // Flat, in the plane of the screen.
                box(Family.turn)
                    .rotationEffect(transformed ? 20 : 0)

                // Tipped about the horizontal axis: the top goes away.
                box(Family.turn)
                    .rotation3DEffect(transformed ? 55 : 0, axis: (x: 1, y: 0, z: 0))

                // Turned about the vertical axis: one side goes away.
                box(Family.turn)
                    .rotation3DEffect(transformed ? 55 : 0, axis: (x: 0, y: 1, z: 0))

                // The same turn about the top left corner instead of the
                // middle, which is what an anchor moves.
                box(Family.turn)
                    .rotationEffect(transformed ? 20 : 0, anchor: .topLeading)
            }

            // A WIDER GAP than the rows above: a scaled box is drawn outside
            // the room the layout gave it, so the spacing has to leave what
            // it grows into or the three of them touch.
            HStack {
                // Drawing only - the room the layout gave it does not change.
                box(Family.size)
                    .scaleEffect(transformed ? 1.6 : 1)

                // The same factor sideways only: wider, and no taller.
                box(Family.size)
                    .scaleEffect(x: transformed ? 1.6 : 1)

                // And the other axis on its own: taller, and no wider.
                box(Family.size)
                    .scaleEffect(y: transformed ? 1.6 : 1)
            }
            .spacing(44)
        }

        func box(_ colour: Color) -> ColorPicker {
            ColorPicker(colour)
                .frame(width: 44)
                .frame(height: 44)
        }

        /// One colour per family, so the three rows read apart at a glance.
        private enum Family {
            /// The two chains that differ only in the ORDER they are written in.
            static let order = Palette.accent

            /// The four ways of turning a view.
            static let turn = Palette.brand

            /// The three ways of resizing one.
            static let size = Color(light: AppColors.amber, dark: AppColors.windowYellow)
        }
        """

    var body: some View {
        VStack {
            SwitchRow("Transforms", $transformed)

            // A GET IN THESE BRACES, which is what makes THIS row a reader:
            // it is built again on every throw, and its count is what that
            // costs. Each row of boxes below reads the switch in its own
            // braces, so each of them is a reader of its own.
            HStack {
                Text(transformed ? "every transform on" : "plain squares")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.subtle)

            }
            .spacing(10)

            // The same two modifiers in both chains; only the order differs,
            // so the only thing the row shows is that order is what a chain
            // MEANS.
            HStack {
                piece(
                    box(Family.order)
                        .rotationEffect(transformed ? 45 : 0)
                        .offset(x: transformed ? 28 : 0),
                    "rotate, then move")

                piece(
                    box(Family.order)
                        .offset(x: transformed ? 28 : 0)
                        .rotationEffect(transformed ? 45 : 0),
                    "move, then rotate")
            }
            .spacing(44)

            HStack {
                piece(box(Family.turn).rotationEffect(transformed ? 20 : 0), "rotation")
                piece(box(Family.turn).rotation3DEffect(transformed ? 55 : 0, axis: (x: 1, y: 0, z: 0)), "rotationX")
                piece(box(Family.turn).rotation3DEffect(transformed ? 55 : 0, axis: (x: 0, y: 1, z: 0)), "rotationY")
                piece(
                    box(Family.turn)
                        .rotationEffect(transformed ? 20 : 0, anchor: .topLeading),
                    "top leading")
            }
            .spacing(24)

            // The same square and the same factor three times, so the only
            // thing the row shows is which axis each modifier reaches - and a
            // WIDER GAP than the violet row, because a scaled box is drawn
            // outside its room and would otherwise touch its neighbours.
            HStack {
                piece(box(Family.size).scaleEffect(transformed ? 1.6 : 1), "scale")
                piece(box(Family.size).scaleEffect(x: transformed ? 1.6 : 1), "scaleX")
                piece(box(Family.size).scaleEffect(y: transformed ? 1.6 : 1), "scaleY")
            }
            .spacing(44)
        }
        .spacing(22)
    }

    var notes: (any View)? {
        VStack {
            Text("One switch throws every example on the page at once. Each transform is "
                + "written as a choice between itself and none, and a changed transform "
                + "travels - so the boxes fly to their turned, tipped, grown selves and back.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("Modifiers compose in the order they are written. The orange row writes "
                + "the same rotation and the same offset both ways: written after the turn "
                + "the move is a plain 28 to the right; written before it, the turn moves "
                + "the moved square's own centre.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("`rotationEffect` turns a view within the plane of the screen, so a square "
                + "stays square; `rotation3DEffect` with an `x` or `y` axis tips it out of "
                + "that plane, so it becomes a trapezium. All of them turn about the "
                + "anchor, the middle until it is moved - the fourth violet box turns "
                + "about its top leading corner.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("A transform happens after the layout: the view keeps the room it was "
                + "given, and only what is drawn moves. `scale` is both axes at once and "
                + "`scaleX` and `scaleY` one each; all three multiply the size the layout "
                + "gave, so 1 is that size and 0.5 half of it. A scaled view overlaps its "
                + "neighbour without pushing it aside, which is why the amber row is spaced "
                + "wider than the violet one.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(8)
    }

    /// The square every example transforms - sized here, because a transform
    /// is about what is DRAWN and the room each one gets has to be the same.
    ///
    /// - Parameter colour: which family this square belongs to.
    /// - Returns: the square, ready to be transformed.
    private func box(_ colour: Color) -> ColorPicker {
        ColorPicker(colour)
            .frame(width: 44)
            .frame(height: 44)
    }

    /// One piece with its caption, so a row reads as labelled examples rather
    /// than bare boxes. The gap under the box is what a scaled one grows into.
    private func piece(_ view: any View, _ caption: String) -> any View {
        VStack {
            view

            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(Palette.subtle)
                .multilineTextAlignment(.center)
        }
        .spacing(22)
    }
}
