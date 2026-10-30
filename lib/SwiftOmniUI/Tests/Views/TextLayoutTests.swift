// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The rich-text pipeline: a picture standing among words, two texts as one,
// the baseline's lift, an attribute that survives typesetting, and the host's
// layout answer climbing back through `Text.LayoutKey`.
//
// The mechanism is in Text.swift (the runs, the seed and the handler),
// TextLayout.swift / TextLayoutReport.swift (the answer and what crosses) and
// MountedElement+Frames.swift (`reportTextLayout`). The promises pinned here:
//
//   - `Text(Image)` writes one run whose `image` carries the picture's source;
//   - `+` keeps each side's words and look as its own runs;
//   - `.baselineOffset` and `.customAttribute` land where a host can read them;
//   - a fired `textLayoutChanged` fills the box, asks for a render, and the
//     clean walk folds a `Layout` of the new generation - the ear hears it;
//   - a rebuilt text takes the last report over, so the answer keeps saying
//     where the words stand until the host says again.

import XCTest
@_spi(Host) @testable import SwiftOmniUICore

/// An attribute the way Markdown writes one - a payload only the laid-out
/// run answers for.
private struct MappingsAttribute: TextAttribute {
    let mappings: [Int: Int]
}

/// A report of one line and one run, as a host's typesetter would send it.
private func report(
    line: Rect = Rect(0, 0, 100, 14),
    run: Rect = Rect(0, 2, 60, 12),
    span: Int = 0,
    slices: [Rect] = [Rect(0, 2, 30, 12), Rect(30, 2, 60, 12)]
) -> TextLayoutReport {
    TextLayoutReport(lines: [
        .init(rect: line, runs: [
            .init(rect: run, direction: .leftToRight, span: span, slices: slices),
        ]),
    ])
}

/// Listens to `Text.LayoutKey` above one child.
private struct LayoutEar: View {
    let heard: Received<[Text.Layout]>
    let inside: () -> any View

    init(heard: Received<[Text.Layout]>, @ViewBuilder inside: @escaping () -> any View) {
        self.heard = heard
        self.inside = inside
    }

    var body: some View {
        VStack { inside() }
            .onPreferenceChange(Text.LayoutKey.self) { heard.values.append($0) }
    }
}

private final class Received<Value> {
    var values: [Value] = []
}

/// The handler id of `event` anywhere in a patch, depth first.
private func findEvent(_ patch: HostPatch, _ event: String) -> Int? {
    if let id = patch.events?[Event(event)] { return id }
    for child in patch.children {
        if let id = findEvent(child, event) { return id }
    }
    return nil
}

@MainActor final class TextLayoutTests: XCTestCase {
    func testNativeLayoutPublicationRebuildsThePreferenceLayerWithoutRebuildingItsBase() throws {
        struct Base: View {
            let builds: Received<Int>
            let make: () -> Text
            var body: some View {
                builds.values.append(1)
                return make()
            }
        }
        let renders = Renders()
        let builds = Received<Int>()
        let heard = Received<Int>()
        let patch = renders.settled(stack([
            Base(builds: builds, make: { Text("body") })
                .backgroundPreferenceValue(Text.LayoutKey.self) { layouts in
                    heard.values.append(layouts.first?.count ?? 0)
                    return Color.clear
                }.node,
        ], id: "root"))
        let before = builds.values.count
        let handler = try XCTUnwrap(findEvent(patch, "textLayoutChanged"))
        XCTAssertTrue(renders.fire(handler, with: [report().propValue]))
        for _ in 0..<3 { _ = renders.revisit(changed: Renderer.shared.pendingChanges) }
        XCTAssertEqual(heard.values.last, 1, "the dependent layer must receive the native layout")
        XCTAssertEqual(builds.values.count, before,
                       "selection geometry must not rebuild the Markdown view producing that geometry")
    }
    func testTextReportsRefoldOnlyTheChangedBranch() throws {
        let renders = Renders()
        let heard = Received<[Text.Layout]>()
        let unrelated = Received<Int>()
        let patch = renders.settled(stack([
            LayoutEar(heard: heard) { Text("changed") }.node,
            VStack {
                ForEach(0..<500) { index in
                    Text("unrelated \(index)").transformPreference(Text.LayoutKey.self) { layouts in
                        unrelated.values.append(index)
                        return layouts
                    }
                }
            }.node,
        ], id: "root"))
        let previous = unrelated.values.count
        let handler = try XCTUnwrap(findEvent(patch, "textLayoutChanged"))
        XCTAssertTrue(renders.fire(handler, with: [report().propValue]))
        _ = renders.revisit(changed: [])
        XCTAssertEqual(heard.values.count, 2)
        XCTAssertEqual(unrelated.values.count, previous,
                       "one native text report must not refold every other mounted text")
    }
    func testTextOriginReportsDoNotBecomeBusinessGeometryReads() throws {
        let plain = Text("unread")
        XCTAssertNil(plain.node.textLayoutBox)
        XCTAssertTrue(plain.node.preferenceSeeds.isEmpty)
        XCTAssertTrue(plain.node.anchorBoxes.isEmpty)
        XCTAssertTrue(plain.node.events.isEmpty)
        let renders = Renders()
        let unread = renders.settled(stack([plain.node], id: "root"))
        XCTAssertNil(findEvent(unread, "textFrameChanged"))
        XCTAssertNil(findEvent(unread, "textLayoutChanged"))
        let heard = Received<[Text.Layout]>()
        let patch = renders.settled(stack([
            LayoutEar(heard: heard) { Text("body") }.node,
        ], id: "root"))
        let handler = try XCTUnwrap(findEvent(patch, "textFrameChanged"))
        XCTAssertNil(findEvent(patch, "frameChanged"))
        XCTAssertFalse(Text("body").node.reportsFrame)
        XCTAssertTrue(Text("body").onFrameChanged { _ in }.node.reportsFrame)
        let layout = try XCTUnwrap(heard.values.first?.first)
        XCTAssertNil(layout.origin.box.frame)
        XCTAssertTrue(renders.fire(handler, with: [
            .numbers([10, 20, 100, 14, 110, 220, 0, 44, 400, 600])]))
        XCTAssertEqual(layout.origin.box.frame, Rect(110, 220, 100, 14))
    }

    /// A picture among words is a run of one attachment glyph, its source on
    /// the run's `image` - what `NSTextAttachment` and Pango paint of it.
    func testAPictureStandsAsARun() {
        let text = Text(Image("tab_list.png"))

        let spans = text.node.children.first { $0.type == .spans }?.children ?? []
        XCTAssertEqual(spans.count, 1)
        XCTAssertNotNil(spans.first?.props[.image],
                        "the run carries the picture's source")
        XCTAssertNil(spans.first?.props[.text]?.string,
                     "an image run has no words of its own")
    }

    /// `+` keeps each side's words and look as its own runs - a picture run
    /// and a word run under one text.
    func testTwoTextsJoinAsRuns() {
        let joined = Text(Image("tab_list.png")) + Text(" marked")

        let spans = joined.node.children.first { $0.type == .spans }?.children ?? []
        XCTAssertEqual(spans.count, 2)
        XCTAssertNotNil(spans[0].props[.image])
        XCTAssertEqual(spans[1].props[.text]?.string, " marked")
    }

    /// A side of `+` that carries no runs offers itself as one, its own props
    /// along - a styled side keeps its look.
    func testAStyledSideKeepsItsLook() {
        let joined = Text("let ") + Text("counter").baselineOffset(2)

        let spans = joined.node.children.first { $0.type == .spans }?.children ?? []
        XCTAssertEqual(spans.count, 2)
        XCTAssertEqual(spans[0].props[.text]?.string, "let ")
        XCTAssertEqual(spans[1].props[.baselineOffset]?.number, 2,
                       "the lift rode the side into its run")
    }

    /// `.baselineOffset` lands on the text where a host's attributes read it.
    func testTheBaselineLiftCrosses() {
        let text = Text("lifted").baselineOffset(-3)

        XCTAssertEqual(text.node.props[.baselineOffset]?.number, -3)
    }

    /// `.customAttribute` lands on the text's layout box - the store a laid-out
    /// run is answered from.
    func testAnAttributeIsWrittenForTheRuns() {
        let text = Text("mapped").customAttribute(MappingsAttribute(mappings: [0: 4]))

        let kept = text.node.textLayoutBox?.attributes[ObjectIdentifier(MappingsAttribute.self)]
        XCTAssertEqual((kept as? MappingsAttribute)?.mappings, [0: 4])
    }

    /// The wire shape a host sends decodes back into the same report - lines,
    /// runs, directions, span numbers and slices.
    func testAReportCrossesAndComesBack() {
        let sent = report()
        let back = TextLayoutReport(propValue: sent.propValue)

        XCTAssertEqual(back, sent)
    }

    /// A filled box's layout walks lines, runs and slices the way
    /// `MarkdownLayoutKey`'s reader does - each with its bounds, the run
    /// carrying direction, span and the text's attributes.
    func testAReportedLayoutReadsAsTheRunsDo() {
        let box = TextLayoutBox()
        box.attributes[ObjectIdentifier(MappingsAttribute.self)] = MappingsAttribute(mappings: [0: 4])
        box.fill(report())

        let layout = Text.Layout(box: box, anchorBox: AnchorBox())
        XCTAssertEqual(Array(layout).count, 1)

        let line = layout[0]
        XCTAssertEqual(line.typographicBounds.rect, Rect(0, 0, 100, 14))
        XCTAssertEqual(Array(line).count, 1)

        let run = line[0]
        XCTAssertEqual(run.typographicBounds.rect, Rect(0, 2, 60, 12))
        XCTAssertEqual(run.layoutDirection, LayoutDirection.leftToRight)
        XCTAssertEqual(run.count, 2)
        XCTAssertEqual(run[0].typographicBounds.rect, Rect(0, 2, 30, 12))
        XCTAssertEqual(run[1].typographicBounds.rect, Rect(30, 2, 60, 12))
        XCTAssertEqual(run[MappingsAttribute.self]?.mappings, [0: 4],
                       "the attribute the text carried answers off the run")
    }

    /// A run whose text wrote no attribute answers none - and a `+` carries
    /// each side's attributes into the answer's runs.
    func testAnAttributeNobodyWroteAnswersNothing() {
        let box = TextLayoutBox()
        box.fill(report())

        XCTAssertNil(Text.Layout(box: box, anchorBox: AnchorBox())[0][0][MappingsAttribute.self])
    }

    /// A laid-out run's generation is what two folded layouts compare by:
    /// same report, same answer; a new report, a moved one.
    func testALayoutAgreesOnlyWithItsOwnGeneration() {
        let box = TextLayoutBox()
        let before = Text.Layout(box: box, anchorBox: AnchorBox())
        box.fill(report())
        let after = Text.Layout(box: box, anchorBox: AnchorBox())

        XCTAssertNotEqual(before, after)
        XCTAssertEqual(after, Text.Layout(box: box, anchorBox: AnchorBox()),
                       "two folds of one report answer the same layout")
    }

    /// The whole road: a text under an ear writes its seed; the host's report
    /// fires `textLayoutChanged`, asks for a render, and the clean walk folds
    /// a `Layout` of the new generation the ear hears.
    func testAHostReportClimbsBackThroughTheKey() {
        let renders = Renders()
        let heard = Received<[Text.Layout]>()

        let patch = renders.settled(stack([
            LayoutEar(heard: heard) { Text("body") }.node,
        ], id: "root"))

        XCTAssertEqual(heard.values.count, 1)
        XCTAssertEqual(heard.values[0].count, 1)
        XCTAssertTrue(heard.values[0][0].isEmpty,
                      "before the host answers, the layout stands empty")

        guard let id = findEvent(patch, "textLayoutChanged")
        else { return XCTFail("the text heard no layout event") }

        XCTAssertTrue(renders.fire(id, with: [report().propValue]))
        XCTAssertFalse(Renderer.shared.pendingTextPreferences.isEmpty,
                       "a host-pushed report identifies the preference branch to refresh")

        _ = renders.revisit(changed: [])
        XCTAssertEqual(heard.values.count, 2,
                       "the fold answered anew and the ear heard it")

        guard let layout = heard.values[1].first
        else { return XCTFail("no layout heard") }
        XCTAssertEqual(Array(layout).count, 1)
        XCTAssertEqual(layout[0].typographicBounds.rect, Rect(0, 0, 100, 14))
        XCTAssertEqual(layout[0][0].typographicBounds.rect, Rect(0, 2, 60, 12))
        XCTAssertEqual(layout[0][0].count, 2)
    }

    /// A text rebuilt under one element takes the last report over - the
    /// folded answer is the same generation, so the ear stays quiet and a
    /// reader sees the words where they stood.
    func testARebuiltTextKeepsTheLastReport() {
        let renders = Renders()
        let heard = Received<[Text.Layout]>()
        let tree = { stack([LayoutEar(heard: heard) { Text("body") }.node], id: "root") }

        let patch = renders.settled(tree())
        guard let id = findEvent(patch, "textLayoutChanged")
        else { return XCTFail("the text heard no layout event") }

        XCTAssertTrue(renders.fire(id, with: [report().propValue]))
        _ = renders.revisit(changed: [])
        XCTAssertEqual(heard.values.count, 2)
        Renderer.shared.clearInvalidation()

        // A fresh describe rebuilds every node; the rebuilt text's box took
        // the report over, so the folded answer moves nothing.
        _ = renders.renderFromScratch(tree())
        XCTAssertEqual(heard.values.count, 2,
                       "the rebuilt text answered the same generation")

        // And the rebuilt element's own handler keeps hearing the host.
        let patch2 = renders.render(tree())
        guard let id2 = findEvent(patch2, "textLayoutChanged") ?? findEvent(patch, "textLayoutChanged")
        else { return XCTFail("the rebuilt text heard no layout event") }
        XCTAssertTrue(renders.fire(id2, with: [
            report(line: Rect(0, 0, 200, 14)).propValue]))
        _ = renders.revisit(changed: [])
        XCTAssertEqual(heard.values.count, 3,
                       "a new report through the rebuilt element moves the answer")
        XCTAssertEqual(heard.values[2][0][0].typographicBounds.rect, Rect(0, 0, 200, 14))
    }
}
