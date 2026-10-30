// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import SwiftOmniUICore

/// A `LazyVGrid`'s columns, and a `Grid`'s `GridRow`s, as the nodes the differ sees.
@MainActor final class GridTests: XCTestCase {
    /// A lazy grid is a `LazyVGrid` node carrying its column items, the names
    /// of every cell it holds, and its spacing - the row gap and the first
    /// column's own gap. Its children wait for the host to ask.
    func testALazyGridCarriesItsColumnsAndSpacing() throws {
        let columns = [
            GridItem(.flexible(minimum: 128, maximum: 764), spacing: 12, alignment: .leading),
            GridItem(.adaptive(minimum: 128, maximum: 764)),
        ]
        let grid = LazyVGrid(columns: columns, spacing: 12) {
            Text("a"); Text("b"); Text("c")
        }
        .node.built

        XCTAssertEqual(grid.type, LazyVGridContract.nodeType)
        XCTAssertEqual(grid.props["flowColumns"], columns.propValue)
        XCTAssertEqual(grid.props["rowSpacing"], PropValue.number(12))
        XCTAssertEqual(grid.props["columnSpacing"], PropValue.number(12))
        XCTAssertEqual(grid.props["items"], ["#0", "#1", "#2"].propValue,
                       "the cells' names cross before any cell exists")
    }

    /// A `Grid` of `GridRow`s lays each row's children one to a column, a bare
    /// child a row of its own spanning the columns the rows make.
    func testAGridOfRowsStampsEachCellItsPlace() throws {
        let grid = Grid(horizontalSpacing: 4, verticalSpacing: 8) {
            GridRow { Text("a"); Text("b") }
            Text("wide")
        }
        let cells = grid.node.built.children

        XCTAssertEqual(grid.node.props["columnSpacing"], .number(4))
        XCTAssertEqual(grid.node.props["rowSpacing"], .number(8))
        XCTAssertEqual(cells.count, 3)
        XCTAssertEqual(cells.map { $0.props["gridRow"] }, [.number(0), .number(0), .number(1)])
        XCTAssertEqual(cells.map { $0.props["gridColumn"] }, [.number(0), .number(1), .number(0)])
        XCTAssertNil(cells[0].props["gridColumnSpan"])
        XCTAssertEqual(cells[2].props["gridColumnSpan"], .number(2),
                       "a bare child spans the columns the rows make")
    }

    /// A row's and the grid's alignments settle where a cell sits: the row's
    /// down axis, the grid's across.
    func testAGridAlignsEachCellAsItsRowAndGridSay() throws {
        let grid = Grid(alignment: .topLeading) {
            GridRow(alignment: .bottom) { Text("a") }
            GridRow { Text("b") }
        }
        let cells = grid.node.built.children

        XCTAssertEqual(cells[0].props["horizontalAlignment"], AxisAlignment.start.propValue)
        XCTAssertEqual(cells[0].props["verticalAlignment"], AxisAlignment.end.propValue,
                       "the row's own alignment wins over the grid's")
        XCTAssertEqual(cells[1].props["verticalAlignment"], AxisAlignment.start.propValue,
                       "the grid's alignment where the row does not say")
    }
}
