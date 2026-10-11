import SwiftOmniUI

/// An outline written as calls - move, line, curve and arc - rather than
/// read from path data; and the inits and helpers that stand beside them.
struct PathSample: SampleContent {
    static let id = "path"
    static let title = "Path"
    static let summary = "A path written as calls: move, addLine, addQuadCurve, addArc - "
        + "and the inits and helpers around it."

    var examples: [Example] {
        [Example(WrittenAsCalls()), Example(MadeAndReused())]
    }
}

/// The command set a `Path { path in ... }` closure answers: `move`, `addLine`,
/// `addLines`, `addCurve`, `addQuadCurve`, `addArc`, `addRelativeArc` and
/// `closeSubpath`.
private struct WrittenAsCalls: ExampleContent {
    static let code = """
        var body: some View {
            HStack {
                // A heart: two quadratic bumps up top, and curves down to the tip.
                Path { path in
                    path.move(to: Point(x: 28, y: 50))
                    path.addQuadCurve(to: Point(x: 4, y: 22), control: Point(x: 4, y: 36))
                    path.addQuadCurve(to: Point(x: 16, y: 8), control: Point(x: 4, y: 8))
                    path.addQuadCurve(to: Point(x: 28, y: 20), control: Point(x: 28, y: 8))
                    path.addQuadCurve(to: Point(x: 40, y: 8), control: Point(x: 28, y: 8))
                    path.addQuadCurve(to: Point(x: 52, y: 22), control: Point(x: 52, y: 8))
                    path.addQuadCurve(to: Point(x: 28, y: 50), control: Point(x: 52, y: 36))
                    path.closeSubpath()
                }
                .fill(Palette.accent)
                .frame(width: 56)
                .frame(height: 56)

                // A wedge: a line out to the rim, an arc most of the way
                // round, and closeSubpath back to the centre. Angles count the
                // way .rotationEffect turns - 0 right, 90 straight down.
                Path { path in
                    path.move(to: Point(x: 28, y: 28))
                    path.addArc(
                        center: Point(x: 28, y: 28), radius: 24,
                        startAngle: .degrees(40), endAngle: .degrees(320),
                        clockwise: false)
                    path.closeSubpath()
                }
                .fill(Palette.accent)
                .frame(width: 56)
                .frame(height: 56)

                // A star is only lines: move once, addLines through the rest.
                Path { path in
                    path.move(to: Point(x: 28, y: 2))
                    path.addLines([
                        Point(x: 43.3, y: 49), Point(x: 3.3, y: 20),
                        Point(x: 52.7, y: 20), Point(x: 12.7, y: 49),
                    ])
                    path.closeSubpath()
                }
                .stroke(Palette.accent)
                .strokeWidth(2)
                .strokeLineJoin(.round)
                .frame(width: 56)
                .frame(height: 56)
            }
            .spacing(16)
        }
        """

    var body: some View {
        HStack {
            Path { path in
                path.move(to: Point(x: 28, y: 50))
                path.addQuadCurve(to: Point(x: 4, y: 22), control: Point(x: 4, y: 36))
                path.addQuadCurve(to: Point(x: 16, y: 8), control: Point(x: 4, y: 8))
                path.addQuadCurve(to: Point(x: 28, y: 20), control: Point(x: 28, y: 8))
                path.addQuadCurve(to: Point(x: 40, y: 8), control: Point(x: 28, y: 8))
                path.addQuadCurve(to: Point(x: 52, y: 22), control: Point(x: 52, y: 8))
                path.addQuadCurve(to: Point(x: 28, y: 50), control: Point(x: 52, y: 36))
                path.closeSubpath()
            }
            .fill(Palette.accent)
            .frame(width: 56)
            .frame(height: 56)

            Path { path in
                path.move(to: Point(x: 28, y: 28))
                path.addArc(
                    center: Point(x: 28, y: 28), radius: 24,
                    startAngle: .degrees(40), endAngle: .degrees(320),
                    clockwise: false)
                path.closeSubpath()
            }
            .fill(Palette.accent)
            .frame(width: 56)
            .frame(height: 56)

            Path { path in
                path.move(to: Point(x: 28, y: 2))
                path.addLines([
                    Point(x: 43.3, y: 49), Point(x: 3.3, y: 20),
                    Point(x: 52.7, y: 20), Point(x: 12.7, y: 49),
                ])
                path.closeSubpath()
            }
            .stroke(Palette.accent)
            .strokeWidth(2)
            .strokeLineJoin(.round)
            .frame(width: 56)
            .frame(height: 56)
        }
        .spacing(16)
        .horizontalAlignment(.center)
    }

    var notes: (any View)? {
        Text("The calls write the same path data `Path(\"M ...\")` reads - the "
            + "drawing that travels is identical either way. `addArc` joins the "
            + "rim from wherever the path stands, so a wedge needs no first line out.")
            .font(.system(size: 12))
            .foregroundStyle(Palette.subtle)
    }
}

/// The initializers that draw a common outline whole - `Path(ellipseIn:)`,
/// `Path(roundedRect:cornerRadius:)` - and `offsetBy` and `applying`, which
/// make the next path from one already written.
private struct MadeAndReused: ExampleContent {
    static let code = """
        var body: some View {
            HStack {
                // Whole outlines from an initializer.
                Path(ellipseIn: Rect(2, 8, 52, 40))
                    .stroke(Palette.accent)
                    .strokeWidth(2)
                    .frame(width: 56)
                    .frame(height: 56)

                Path(roundedRect: Rect(4, 4, 48, 48), cornerRadius: 10)
                    .stroke(Palette.accent)
                    .strokeWidth(2)
                    .frame(width: 56)
                    .frame(height: 56)

                // A path is a value: the next one is made from it.
                let card = Path(roundedRect: Rect(18, 8, 20, 40), cornerRadius: 4)
                card.stroke(Palette.accent)
                    .strokeWidth(2)
                    .frame(width: 56)
                    .frame(height: 56)
                card.applying(.skew(20, 0))
                    .stroke(Palette.subtle)
                    .strokeWidth(2)
                    .frame(width: 56)
                    .frame(height: 56)

                let dot = Path(ellipseIn: Rect(8, 8, 16, 16))
                dot.fill(Palette.accent)
                    .frame(width: 56)
                    .frame(height: 56)
                dot.offsetBy(dx: 16, dy: 14)
                    .fill(Palette.subtle)
                    .frame(width: 56)
                    .frame(height: 56)
            }
            .spacing(16)
        }
        """

    var body: some View {
        HStack {
            Path(ellipseIn: Rect(2, 8, 52, 40))
                .stroke(Palette.accent)
                .strokeWidth(2)
                .frame(width: 56)
                .frame(height: 56)

            Path(roundedRect: Rect(4, 4, 48, 48), cornerRadius: 10)
                .stroke(Palette.accent)
                .strokeWidth(2)
                .frame(width: 56)
                .frame(height: 56)

            VStack(spacing: 0) {
                let card = Path(roundedRect: Rect(18, 8, 20, 40), cornerRadius: 4)
                card.stroke(Palette.accent)
                    .strokeWidth(2)
                    .frame(width: 56)
                    .frame(height: 28)
                card.applying(.skew(20, 0))
                    .stroke(Palette.subtle)
                    .strokeWidth(2)
                    .frame(width: 56)
                    .frame(height: 28)
            }

            VStack(spacing: 0) {
                let dot = Path(ellipseIn: Rect(20, 6, 16, 16))
                dot.fill(Palette.accent)
                    .frame(width: 56)
                    .frame(height: 28)
                dot.offsetBy(dx: 0, dy: 6)
                    .fill(Palette.subtle)
                    .frame(width: 56)
                    .frame(height: 28)
            }
        }
        .spacing(16)
        .horizontalAlignment(.center)
    }

    var notes: (any View)? {
        Text("`Path` conforms to `Sendable` and is a value: `offsetBy(dx:dy:)` "
            + "shifts a copy, `applying(_:)` runs a `ViewTransform` over every "
            + "command's points - the skewed card is the same outline bent, not "
            + "a view leaning.")
            .font(.system(size: 12))
            .foregroundStyle(Palette.subtle)
    }
}
