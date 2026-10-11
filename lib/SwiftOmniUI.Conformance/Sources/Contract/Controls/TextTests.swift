// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// `TextContract` on a host: a label shows its words, wraps or cuts them as the tree says, and shows no more lines
/// than its maximum.
@_spi(Host) public enum TextTests: ConformanceFamily {
    public static let name = "Text"

    public static var cases: [ConformanceCase] {
        [
            Aspects.standsAlone("Text"),
            Aspects.holds(TextContract.selectable, on: "Text", false, then: true),
            Aspects.holds(TextContract.minimumScaleFactor, on: "Text", 1, then: 0.5),
            Aspects.holds(TextContract.textRenderer, on: "Text", "default", then: "annotated"),
            ConformanceCase("aLabelReportsItsFrameAndItsWordsLaidOut", proves: [
                Covered(TextContract.textFrameChanged), Covered(TextContract.textLayoutChanged),
            ]) { s in
                let frames = Received<[Double]>()
                let layout = Received<TextLayoutReport>()
                s.start {
                    VStack {
                        Text("Some words")
                            .onEvent(TextContract.textFrameChanged) { frames.values.append($0) }
                            .onEvent(TextContract.textLayoutChanged) { layout.values.append($0) }
                    }
                }
                try s.settle { !frames.values.isEmpty && !layout.values.isEmpty }
                s.expect(frames.values.isEmpty, false, "its frame reported")
                s.expect(layout.values.isEmpty, false, "and how its words lay")
            },
            ConformanceCase("aLabelShowsItsWords", proves: [
                Covered(TextElementContract.text, on: "Text"),
            ]) { s in
                s.start { VStack { Text("Some words").id("label") } }

                s.expect(try s.held(TextElementContract.text, on: s.element("label")), "Some words")
            },
            ConformanceCase("noMoreLinesStandThanItsMaximum", proves: [
                Covered(TextContract.lineLimit), Covered(TextContract.lineBreak),
            ], needs: [Covered(ButtonContract.clicked)]) { s in
                let lines = State(wrappedValue: 1)
                let frames = Received<[Double]>()
                s.start {
                    VStack {
                        Text(Self.long).lineBreak(.wordWrap).lineLimit(lines.wrappedValue).frame(width: 100)
                            .onEvent(ViewContract.frameChanged) { frames.values.append($0) }.id("label")
                        Button("More").onClicked { lines.wrappedValue = 3 }.id("change")
                    }
                    .horizontalAlignment(.start)
                    .verticalAlignment(.start)
                }
                s.settle { !frames.values.isEmpty }
                let one = frames.values.last.map(FrameReport.size)?[1] ?? 0

                try s.perform(.activate, on: s.element("change"))
                s.settle { (frames.values.last.map(FrameReport.size)?[1] ?? 0) > one * 2 }
                s.expect((frames.values.last.map(FrameReport.size)?[1] ?? 0) > one * 2, true,
                         "three lines stand where one stood")
            },
            ConformanceCase("wordsThatDoNotWrapStandOnOneLine", proves: [
                Covered(TextContract.lineBreak),
            ], needs: [Covered(ButtonContract.clicked)]) { s in
                let wraps = State(wrappedValue: false)
                let frames = Received<[Double]>()
                s.start {
                    VStack {
                        Text(Self.long).lineBreak(wraps.wrappedValue ? .wordWrap : .noWrap).frame(width: 100)
                            .onEvent(ViewContract.frameChanged) { frames.values.append($0) }.id("label")
                        Button("Wrap").onClicked { wraps.wrappedValue = true }.id("change")
                    }
                    .horizontalAlignment(.start)
                    .verticalAlignment(.start)
                }
                s.settle { !frames.values.isEmpty }
                let one = frames.values.last.map(FrameReport.size)?[1] ?? 0

                try s.perform(.activate, on: s.element("change"))
                s.settle { (frames.values.last.map(FrameReport.size)?[1] ?? 0) > one * 2 }
                s.expect((frames.values.last.map(FrameReport.size)?[1] ?? 0) > one * 2, true, "wrapped over lines")
            },
            Aspects.holds(TextContract.lineBreak, on: "Text", .wordWrap, then: .tailTruncation,
                          with: [Write(TextElementContract.text, Self.long)]),
            Aspects.holds(TextContract.lineLimit, on: "Text", 2, then: 1,
                          with: [Write(TextElementContract.text, Self.long)]),
        ]
    }

    /// Words enough to take several lines of a narrow label.
    static let long = "Words enough to take several lines of a label a hundred wide, and more than that"
}
