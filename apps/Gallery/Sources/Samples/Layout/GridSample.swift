import SwiftOmniUI

/// One cell of the grids below: words on a colour.
private struct GridCell: View {
    let text: String
    let color: String

    var body: some View {
        Text(text)
            .foregroundStyle(.white)
            .background(Color(color))
            .padding(8)
    }
}

/// Rows and columns described by `GridRow`s, with a spanning cell and a
/// column whose width a switch changes.
struct GridSample: SampleContent {
    static let id = "grid"
    static let title = "Grid"
    static let summary = "Rows of cells in shared columns, one cell spanning them all."

    var examples: [Example] {
        [Example(GridPlacement())]
    }
}

/// Two rows of two cells over a cell spanning both columns - and a column
/// whose width a switch changes.
private struct GridPlacement: ExampleContent {
    @State private var wideSecondColumn = true

    static let code = """
        @State private var wideSecondColumn = true

        VStack {
            // `wideSecondColumn` is read here, so flipping its switch builds
            // this closure - and the cells take their new widths.

            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    GridCell(text: "Column 0, Row 0", color: "#E53935")
                        .frame(height: 64)
                        .frame(maxWidth: .infinity)
                    GridCell(text: "Column 1, Row 0", color: "#1E88E5")
                        .frame(height: 64)
                        .frame(width: wideSecondColumn ? 240 : 120)
                }

                GridRow {
                    GridCell(text: "Column 0, Row 1", color: "#43A047")
                        .frame(height: 64)
                        .frame(maxWidth: .infinity)
                    GridCell(text: "Column 1, Row 1", color: "#8E24AA")
                        .frame(height: 64)
                        .frame(width: wideSecondColumn ? 240 : 120)
                }

                GridRow {
                    GridCell(text: "Row 2, spanning both columns", color: "#F4511E")
                        .gridCellColumns(2)
                        .frame(maxWidth: .infinity)
                }
            }

            // The width is read here, so flipping it rebuilds this closure -
            // and the column follows.
            SwitchRow("Second column twice as wide", $wideSecondColumn)
        }

        private struct GridCell: View {
            let text: String
            let color: String

            var body: some View {
                Text(text)
                    .foregroundStyle(.white)
                    .background(Color(color))
                    .padding(8)
            }
        }
        """

    var body: some View {
        VStack {

            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    GridCell(text: "Column 0, Row 0", color: "#E53935")
                        .frame(height: 64)
                        .frame(maxWidth: .infinity)
                    GridCell(text: "Column 1, Row 0", color: "#1E88E5")
                        .frame(height: 64)
                        .frame(width: wideSecondColumn ? 240 : 120)
                }

                GridRow {
                    GridCell(text: "Column 0, Row 1", color: "#43A047")
                        .frame(height: 64)
                        .frame(maxWidth: .infinity)
                    GridCell(text: "Column 1, Row 1", color: "#8E24AA")
                        .frame(height: 64)
                        .frame(width: wideSecondColumn ? 240 : 120)
                }

                GridRow {
                    GridCell(text: "Row 2, spanning both columns", color: "#F4511E")
                        .gridCellColumns(2)
                        .frame(maxWidth: .infinity)
                }
            }

            // The width is read here, so flipping it rebuilds this closure -
            // and the column follows.
            SwitchRow("Second column twice as wide", $wideSecondColumn)
        }
        .spacing(12)
    }

    var notes: (any View)? {
        VStack {
            Text("A `GridRow`'s children land one to a column in order; a bare child "
                + "stands as a row of its own. `.gridCellColumns(2)` is how a cell "
                + "covers more than one column.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("A column is as wide as its widest cell, so sizing the cells sizes "
                + "the column - `.frame(maxWidth: .infinity)` lets the first take all "
                + "the room the second leaves.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("A cell nothing is placed in stays empty: a `GridRow` shorter than "
                + "the grid leaves its last columns unfilled.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(8)
    }
}
