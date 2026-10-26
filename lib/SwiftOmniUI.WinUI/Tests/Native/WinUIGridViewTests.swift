// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

final class WinUIGridViewTests: XCTestCase {
    @MainActor private static func checkDenseRowFramePlacement() {
        let grid = WinUIGridView()
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
