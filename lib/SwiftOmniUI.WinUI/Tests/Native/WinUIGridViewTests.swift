// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

final class WinUIGridViewTests: XCTestCase {
    @MainActor private static func checkDenseRowFramePlacement() {
        // Placement plans omit hidden children but retain source order. Check
        // lookup-free arrangement across holes and reordered retained views.
        for layout in [WinUIStackView(axis: .vertical), WinUIStackView(axis: .horizontal), WinUIGridView()] as [WinUILayoutView] {
            let rows = (0..<5).map { _ in WinUIPathView() }
            for order in [[0, 1, 2, 3, 4], [4, 2, 0, 3, 1], [1, 3, 4, 0, 2]] {
                let items = order.map { index -> WinUILayoutItem in
                    var item = WinUILayoutItem(view: rows[index], isShown: index % 2 == 0)
                    item.values.width = Double(20 + index)
                    item.values.height = Double(12 + index)
                    item.values.margin = EdgeInsets(Double(index))
                    return item
                }
                layout.setItems(items)
                layout.prepareMeasure(width: 320, height: 160)
                let expected = WinUILayoutView.querySize {
                    layout.nativeProposals(width: 320, size: LayoutSize(width: 320, height: 160))
                }
                layout.arrange(width: 320, height: 160)
                XCTAssertEqual(expected.count, 3)
                for proposal in expected {
                    XCTAssertEqual(proposal.view?.placedFrame, proposal.place,
                                   "visible items after hidden/reordered children must keep their own slot")
                }
            }
        }
        // Exercise both rolling edges and the general reorder path. Incoming
        // children already owned by another native panel must move, while the
        // overlapping window stays attached and outgoing children leave.
        for next in [[0, 1, 2, 3], [1, 2, 3], [3, 0, 1], [0, 3, 2], [2, 0, 1], [], [3, 4]] {
            let destination = WinUIGridView(), donor = WinUIGridView()
            let root = WinUIGridView()
            let rows = (0..<5).map { _ in WinUILabelView() }
            destination.setChildren(Array(rows[0..<3]))
            donor.setChildren(Array(rows[3..<5]))
            root.setItems([WinUILayoutItem(view: destination), WinUILayoutItem(view: donor)])
            WinUITestHost.window.show(root)
            WinUITestHost.pump(0.02)
            XCTAssertNotNil(rows[0].layoutOffset(relativeTo: destination))
            XCTAssertNotNil(rows[3].layoutOffset(relativeTo: donor))
            destination.setChildren(next.map { rows[$0] })
            destination.setChildren(next.map { rows[$0] })
            WinUITestHost.pump(0.02)
            for index in rows.indices {
                XCTAssertEqual(rows[index].layoutOffset(relativeTo: destination) != nil,
                               next.contains(index), "native ownership after \(next)")
                XCTAssertEqual(rows[index].layoutOffset(relativeTo: donor) != nil,
                               index >= 3 && !next.contains(index), "foreign ownership after \(next)")
            }
            destination.setChildren([])
            donor.setChildren([])
            WinUITestHost.window.show(nil)
        }
        let grid = WinUIGridView()
        // Native attachment, including the single-child frame fast path,
        // invalidates only children whose actual parent has changed.
        let first = WinUILabelView(), second = WinUILabelView()
        let firstRevision = first.hierarchyRevision
        let secondRevision = second.hierarchyRevision
        grid.setChildren([first])
        grid.setChildren([first])
        XCTAssertEqual(first.hierarchyRevision, firstRevision + 1)
        grid.setChildren([second])
        XCTAssertEqual(first.hierarchyRevision, firstRevision + 2)
        XCTAssertEqual(second.hierarchyRevision, secondRevision + 1)
        grid.setChildren([])
        XCTAssertEqual(second.hierarchyRevision, secondRevision + 2)
        grid.setChildren([first, second])
        grid.setChildren([second, first])
        XCTAssertEqual(first.hierarchyRevision, firstRevision + 3)
        XCTAssertEqual(second.hierarchyRevision, secondRevision + 3)
        grid.setChildren([])
        let text = WinUILabelView()
        text.setText("文件夹内的多行文件名 A filename that wraps at the offered width.swift")
        text.setTextFont(size: 12, attributes: nil, family: nil)
        grid.padding = EdgeInsets(3)
        for direction in [LayoutDirection.leftToRight, .rightToLeft] {
            grid.direction = direction
            for scenario in 0..<8 {
                var values = LayoutValues()
                values.isFrameContent = true
                values.margin = EdgeInsets(2)
                values.horizontal = Int32(scenario % 4)
                values.vertical = Int32((scenario + 1) % 4)
                if scenario == 1 { values.width = 180; values.height = 100 }
                if scenario == 2 { values.minimumWidth = 90; values.maximumHeight = 20 }
                if scenario == 3 { values.maximumWidth = 40; values.minimumHeight = 36 }
                if scenario == 4 { values.flex = 0 }
                if scenario == 5 { values.expandingAxes = .horizontal }
                if scenario == 6 { values.expandingAxes = .vertical }
                let item = WinUILayoutItem(view: text, values: values, isShown: scenario != 7)
                grid.setItems([item])
                for size in [LayoutSize(width: 80, height: 48), LayoutSize(width: 123.5, height: 76.25)] {
                    let bounds = Rect(0, 0, size.width, size.height)
                    let expected = WinUILayoutView.querySize {
                        GridArithmetic.places(of: [item], rows: [], columns: [], rowSpacing: 0,
                                              columnSpacing: 0, padding: grid.padding, in: bounds, direction: direction)
                    }.compactMap { $0 }
                    let actual = WinUILayoutView.querySize {
                        grid.nativeProposals(width: size.width, size: size).map(\.place)
                    }
                    XCTAssertEqual(actual, expected, "dense frame placement scenario \(scenario), \(direction)")
                }
            }
        }
    }

    /// Words with a margin in a cell are measured at the cell's width less the margin, once: on one line, as tall
    /// as without it, and the pass settles.
    func testWordsWithAMarginStandOnOneLineInTheirCell() {
        onUIThread {
            Self.checkDenseRowFramePlacement()
            let host = WinUIRenderer.running {
                VStack {
                    Grid { Text("Waiting for the first render of this scene") }
                    Grid { Text("Waiting for the first render of this scene").padding(8, 4) }
                }
                .horizontalAlignment(.start)
            }
            let labels = host.views(WinUILabelView.self)
            XCTAssertEqual(labels.count, 2)
            XCTAssertEqual(labels[1].frame.height, labels[0].frame.height, "on one line")
            XCTAssertEqual(labels[1].frame.y, 4)
        }
    }
}
