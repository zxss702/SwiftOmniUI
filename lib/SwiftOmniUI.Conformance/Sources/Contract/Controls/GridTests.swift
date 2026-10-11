// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// `GridContract` on a host: each child stands in its cell - fixed, proportional and automatic tracks, the spacing
/// between them, a child spanning several - and moves when the tree changes a track or a spacing; SwiftOmniUI's
/// arithmetic, alike on every host, read from the frames the children report.
@_spi(Host) public enum GridTests: ConformanceFamily {
    public static let name = "Grid"

    public static var cases: [ConformanceCase] {
        [
            Aspects.standsAlone("Grid"),
            Aspects.holds(GridContract.flowColumns, on: "Grid",
                          [GridItem(.fixed(20)), GridItem(.flexible())], then: [GridItem(.fixed(40))]),
            ConformanceCase("eachChildStandsInItsCell", proves: [
                Covered(GridContract.columns), Covered(GridContract.rows),
                Covered(GridContract.columnSpacing), Covered(GridContract.rowSpacing),
            ]) { s in
                let (a, b, c) = (Received<[Double]>(), Received<[Double]>(), Received<[Double]>())
                s.start {
                    VStack {
                        Grid {
                            ColorPicker(.red).frame(width: 50).frame(height: 20).horizontalAlignment(.start)
                                .onEvent(ViewContract.frameChanged) { a.values.append($0) }
                            ColorPicker(.green).frame(height: 20).gridColumn(1)
                                .onEvent(ViewContract.frameChanged) { b.values.append($0) }
                            ColorPicker(.blue).frame(width: 30).frame(height: 40).gridRow(1).gridColumnSpan(2).horizontalAlignment(.end)
                                .onEvent(ViewContract.frameChanged) { c.values.append($0) }
                        }
                        .columns(.fixed(100), .fill)
                        .rows(.auto, .auto)
                        .rowSpacing(10)
                        .columnSpacing(5)
                        .contentPadding(10)
                        .frame(width: 300)
                    }
                    .horizontalAlignment(.start)
                    .verticalAlignment(.start)
                }

                s.settle { c.values.last.map(FrameReport.place) == [260, 40, 30, 40] }
                s.expect(a.values.last.map(FrameReport.place), [10, 10, 50, 20], "a fixed column's start")
                s.expect(b.values.last.map(FrameReport.place), [115, 10, 175, 20], "the rest, past the spacing")
                s.expect(c.values.last.map(FrameReport.place), [260, 40, 30, 40], "across both, a row and its spacing down")
            },
            ConformanceCase("aProportionalRowTakesWhatTheOthersLeave", proves: [
                Covered(GridContract.rows),
            ]) { s in
                let box = Received<[Double]>()
                s.start {
                    VStack {
                        Grid {
                            ColorPicker(.red).frame(height: 30)
                            ColorPicker(.green).gridRow(1).onEvent(ViewContract.frameChanged) { box.values.append($0) }
                            ColorPicker(.blue).frame(height: 20).gridRow(2)
                        }
                        .rows(.auto, .fill, .auto)
                        .frame(width: 100)
                        .frame(height: 200)
                    }
                    .horizontalAlignment(.start)
                    .verticalAlignment(.start)
                }

                s.settle { box.values.last.map(FrameReport.place) == [0, 30, 100, 150] }
                s.expect(box.values.last.map(FrameReport.place), [0, 30, 100, 150])
            },
            ConformanceCase("aChildSpanningRowsStandsAcrossThemAndTheirSpacing", proves: [
                Covered(GridContract.rows), Covered(GridContract.rowSpacing), Covered(GridContract.columns),
            ]) { s in
                let box = Received<[Double]>()
                s.start {
                    VStack {
                        Grid {
                            ColorPicker(.red).gridRowSpan(2).onEvent(ViewContract.frameChanged) { box.values.append($0) }
                            ColorPicker(.green).frame(height: 20).gridColumn(1)
                            ColorPicker(.blue).frame(height: 30).gridRow(1).gridColumn(1)
                        }
                        .columns(.fixed(20), .fill)
                        .rows(.auto, .auto)
                        .rowSpacing(10)
                        .frame(width: 100)
                    }
                    .horizontalAlignment(.start)
                    .verticalAlignment(.start)
                }

                s.settle { box.values.last.map(FrameReport.place) == [0, 0, 20, 60] }
                s.expect(box.values.last.map(FrameReport.place), [0, 0, 20, 60])
            },
            ConformanceCase("aSpacingTheTreeChangesMovesTheCells", proves: [
                Covered(GridContract.columnSpacing), Covered(GridContract.rowSpacing),
            ], needs: [Covered(ButtonContract.clicked)]) { s in
                let wide = State(wrappedValue: false)
                let box = Received<[Double]>()
                s.start {
                    VStack {
                        Grid {
                            ColorPicker(.red).frame(width: 20).frame(height: 20)
                            ColorPicker(.green).frame(width: 20).frame(height: 20).gridColumn(1).gridRow(1)
                                .onEvent(ViewContract.frameChanged) { box.values.append($0) }
                        }
                        .columns(.fixed(20), .fixed(20))
                        .rows(.auto, .auto)
                        .columnSpacing(wide.wrappedValue ? 15 : 5)
                        .rowSpacing(wide.wrappedValue ? 25 : 5)
                        Button("Wider").onClicked { wide.wrappedValue = true }.id("change")
                    }
                    .horizontalAlignment(.start)
                    .verticalAlignment(.start)
                }
                s.settle { box.values.last.map(FrameReport.place) == [25, 25, 20, 20] }

                try s.perform(.activate, on: s.element("change"))
                s.settle { box.values.last.map(FrameReport.place) == [35, 45, 20, 20] }
                s.expect(box.values.last.map(FrameReport.place), [35, 45, 20, 20])
            },
            ConformanceCase("aTrackTheTreeChangesMovesTheCells", proves: [
                Covered(GridContract.columns), Covered(GridContract.rows),
            ], needs: [Covered(ButtonContract.clicked)]) { s in
                let wide = State(wrappedValue: false)
                let box = Received<[Double]>()
                s.start {
                    VStack {
                        Grid {
                            ColorPicker(.red)
                            ColorPicker(.green).gridColumn(1).gridRow(1).onEvent(ViewContract.frameChanged) { box.values.append($0) }
                        }
                        .columns(.fixed(wide.wrappedValue ? 60 : 30), .fixed(20))
                        .rows(.fixed(wide.wrappedValue ? 50 : 10), .fixed(20))
                        Button("Wider").onClicked { wide.wrappedValue = true }.id("change")
                    }
                    .horizontalAlignment(.start)
                    .verticalAlignment(.start)
                }
                s.settle { box.values.last.map(FrameReport.place) == [30, 10, 20, 20] }

                try s.perform(.activate, on: s.element("change"))
                s.settle { box.values.last.map(FrameReport.place) == [60, 50, 20, 20] }
                s.expect(box.values.last.map(FrameReport.place), [60, 50, 20, 20])
            },
        ]
    }
}
