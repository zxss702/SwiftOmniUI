// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// What a view offers its ancestors, folded by each key's reduce on the way up -
// and the reads that answer it.
//
// The mechanism is in Preferences.swift (the boxes, seeds and the fold),
// Differ+Element.swift (the fold after reconciliation, the observer queue)
// and Differ.swift (the same fold on the clean walk). The promises pinned
// here:
//
//   - `.preference` writes reach `.onPreferenceChange` through the key's
//     `reduce`, children in order;
//   - the observer hears the answer once when it mounts and again only when
//     the answer actually moves - a rebuild that answers the same is silent;
//   - `transformPreference` rewrites its subtree's answer before the parent
//     folds it;
//   - `.anchorPreference` stores an anchor a `GeometryProxy` resolves after
//     the host's frame report;
//   - `backgroundPreferenceValue` draws content over the folded answer, and
//     `overlayPreferenceValue` over it;
//   - seeds cross fragments - a `Group` or `ForEach` is transparent to them.

import XCTest
@_spi(Host) @testable import SwiftOmniUICore

/// A sum over whatever children offer - the `MarkdownLayoutKey` shape, where
/// the answer is what every descendant wrote.
private struct SumKey: PreferenceKey {
    static let defaultValue = 0.0

    static func reduce(value: inout Double, nextValue: () -> Double) {
        value += nextValue()
    }
}

private struct FirstKey: PreferenceKey {
    static let defaultValue = 0
    static func reduce(value: inout Int, nextValue: () -> Int) {}
}

/// A collecting key - arrays of what descendants offered, in order.
private struct BlocksKey: PreferenceKey {
    struct Layout: Equatable {
        let id: String
        let bounds: Anchor<Rect>
    }

    static let defaultValue: [Layout] = []

    static func reduce(value: inout [Layout], nextValue: () -> [Layout]) {
        value += nextValue()
    }
}

/// What a handler heard, in order - a class, so a closure can append to it.
private final class Received<Value> {
    var values: [Value] = []
}

/// Writes `width` for `SumKey` and reports builds - the view a state write
/// rebuilds.
private struct Offer: View {
    @State var width: Double

    var body: some View {
        // A composed, Equatable view whose own inputs stay unchanged while
        // the preference written on it moves (the Markdown background path).
        Color.clear
            .preference(key: SumKey.self, value: width)
    }
}

/// Listens to `SumKey` above one child.
private struct Ear: View {
    let heard: Received<Double>
    let inside: () -> any View

    init(heard: Received<Double>, @ViewBuilder inside: @escaping () -> any View) {
        self.heard = heard
        self.inside = inside
    }

    var body: some View {
        VStack { inside() }
            .onPreferenceChange(SumKey.self) { heard.values.append($0) }
    }
}

@MainActor final class PreferenceTests: XCTestCase {
    /// The changed-storages set a revisit asks for, as the renderer names it.
    private var changed: Set<ObjectIdentifier> {
        Renderer.shared.pendingChanges
    }

    // MARK: - The fold

    func testTheObserverHearsTheFoldedAnswerOnce() {
        let renders = Renders()
        let heard = Received<Double>()

        renders.render(stack([Ear(heard: heard) {
            VStack {
                Text("a").preference(key: SumKey.self, value: 3)
                Text("b").preference(key: SumKey.self, value: 4)
            }
        }.node], id: "root"))

        XCTAssertEqual(heard.values, [7],
                       "each child's seed folded in order through reduce")

        let first = Received<Int>()
        renders.render(stack([
            VStack {
                Text("first").preference(key: FirstKey.self, value: 3)
                Text("second").preference(key: FirstKey.self, value: 4)
            }.onPreferenceChange(FirstKey.self) { first.values.append($0) }.node,
        ], id: "root"))
        XCTAssertEqual(first.values, [3], "a sole offer passes through wrappers without reducing the default")

        var value: Any = 3
        var reads = 0
        PreferenceKeyBox(FirstKey.self).reduce(&value) { reads += 1; return 4 }
        XCTAssertEqual(value as? Int, 3)
        XCTAssertEqual(reads, 0, "a reducer that retains the first value does not evaluate the next one")
    }

    func testAnUnchangedAnswerStaysQuiet() {
        let renders = Renders()
        let heard = Received<Double>()
        let offer = Offer(width: 5)

        renders.render(stack([Ear(heard: heard) { offer }.node], id: "root"))
        XCTAssertEqual(heard.values, [5])

        _ = renders.revisit(changed: changed)
        XCTAssertEqual(heard.values, [5],
                       "the clean walk refolds, and an equal answer fires nothing")
    }

    func testAMovedAnswerFiresAgain() {
        let renders = Renders()
        let heard = Received<Double>()
        let offer = Offer(width: 5)

        renders.render(stack([Ear(heard: heard) { offer }.node], id: "root"))
        offer.width = 9

        _ = renders.revisit(changed: changed)
        XCTAssertEqual(heard.values, [5, 9],
                       "the rebuilt child offered again, the fold moved, the ear heard")
    }

    func testANativeTextLayoutReachesAComposedPreferenceBackground() throws {
        let renders = Renders()
        let heard = Received<Double>()
        let tree = {
            stack([Ear(heard: heard) {
                Text("body").backgroundPreferenceValue(Text.LayoutKey.self) { layouts in
                    Color.clear.preference(key: SumKey.self, value: Double(layouts.reduce(0) { $0 + $1.count }))
                }
            }.node], id: "root")
        }
        let patch = renders.settled(tree())
        XCTAssertEqual(heard.values.last, 0)
        let handler = try XCTUnwrap(findEvent(patch, "textLayoutChanged"))
        let rect = Rect(0, 0, 40, 14)
        let report = TextLayoutReport(line: rect, runs: [
            .init(rect: rect, direction: .leftToRight, span: -1, slices: [rect], sliceTexts: ["body"]),
        ])
        XCTAssertTrue(renders.fire(handler, with: [report.propValue]))
        renders.settled(tree(), changed: changed)
        XCTAssertEqual(heard.values.last, 1,
                       "the native layout must replace the background's initial empty offer")
    }

    func testATransformRewritesItsSubtreesAnswer() {
        let renders = Renders()
        let heard = Received<Double>()

        renders.render(stack([Ear(heard: heard) {
            VStack {
                Text("a").preference(key: SumKey.self, value: 3)
                Text("b").preference(key: SumKey.self, value: 4)
            }
            .transformPreference(SumKey.self) { $0 * 10 }
        }.node], id: "root"))

        XCTAssertEqual(heard.values, [70],
                       "the subtree's 7 became 70 before the ear's parent folded it")
    }

    // MARK: - Anchors

    func testAnchorsInTheSameScrollDocumentIgnoreWindowRoundingButRetainLayoutChanges() throws {
        let box = AnchorBox()
        let anchor = Anchor<Rect>(box: box) { source, reader in
            Rect(source.x - reader.x, source.y - reader.y, source.width, source.height)
        }
        func frame(globalY: Double, document: Double, y: Double) throws -> FrameReport {
            try XCTUnwrap(FrameReport([0, 0, 10, 20, 100, globalY, 0, 0, 500, 600, document, 12, y]))
        }
        for offset in [0.0, 0.13, 80.41, 100_000.7] {
            box.update(try frame(globalY: Double(Float(200.25 - offset)), document: 7, y: 200.25))
            let proxy = GeometryProxy(report: try frame(globalY: Double(Float(20.1 - offset)), document: 7, y: 20.1))
            XCTAssertEqual(proxy[anchor], Rect(0, 200.25 - 20.1, 10, 20))
        }
        box.update(try frame(globalY: 100, document: 7, y: 201.25))
        let same = GeometryProxy(report: try frame(globalY: 30, document: 7, y: 20.1))
        XCTAssertEqual(same[anchor].y, 201.25 - 20.1, "a real one-DIP layout change must be preserved")
        let other = GeometryProxy(report: try frame(globalY: 30, document: 8, y: 20.1))
        XCTAssertEqual(other[anchor].y, 70, "different scroll documents still resolve through window coordinates")
        box.update(try XCTUnwrap(FrameReport([0, 0, 10, 20, 100, 120, 0, 0, 500, 600])))
        XCTAssertEqual(same[anchor].y, 90, "a legacy report must clear the old document context")
    }

    func testAnAnchorResolvesAgainstAProxy() {
        let renders = Renders()
        let heard = Received<[BlocksKey.Layout]>()

        let patch = renders.render(stack([
            EarList(heard: heard) {
                Text("block")
                    .anchorPreference(key: BlocksKey.self, value: .bounds) { bounds in
                        [BlocksKey.Layout(id: "one", bounds: bounds)]
                    }
            }.node,
        ], id: "root"))

        guard let layout = heard.values.last?.first else {
            return XCTFail("no folded layouts heard")
        }
        XCTAssertEqual(layout.id, "one")

        // The host's frame report for the anchored child: parent frame
        // (0,0,10,20), window frame (100,200,10,20), safe area (0,0,500,600).
        guard let id = findEvent(patch, "frameChanged")
        else { return XCTFail("the anchored view heard no frame event") }
        XCTAssertTrue(renders.fire(
            id, with: [.numbers([0, 0, 10, 20, 100, 200, 0, 0, 500, 600])]))

        let proxy = GeometryProxy(report: FrameReport(
            frame: Rect(0, 0, 50, 50), global: Rect(110, 220, 50, 50),
            safeAreaRect: Rect(0, 0, 500, 600)))
        XCTAssertEqual(proxy[layout.bounds], Rect(100 - 110, 200 - 220, 10, 20),
                       "the anchor answers in the proxy's own space")
    }

    // MARK: - The backed layers

    func testABackgroundReadsTheFoldedAnswer() {
        let renders = Renders()

        let patch = renders.settled(stack([
            Backed {
                Text("a").preference(key: SumKey.self, value: 3)
                Text("b").preference(key: SumKey.self, value: 4)
            }.node,
        ], id: "root"))

        let texts = collectText(patch)
        XCTAssertTrue(texts.contains("heard 7"),
                       "the background built with the folded answer - \(texts)")
    }

    func testAnOverlayReadsTheFoldedAnswer() {
        let renders = Renders()

        let patch = renders.settled(stack([
            Overlaid {
                Text("a").preference(key: SumKey.self, value: 6)
            }.node,
        ], id: "root"))

        let texts = collectText(patch)
        XCTAssertTrue(texts.contains("over 6"),
                       "the overlay built with the folded answer - \(texts)")
    }

    // MARK: - Fragments pass seeds through

    func testSeedsCrossAFragment() {
        let renders = Renders()
        let heard = Received<Double>()

        renders.render(stack([Ear(heard: heard) {
            Group {
                Text("a").preference(key: SumKey.self, value: 2)
                ForEach([3.0, 5.0]) { n in
                    Text("n").preference(key: SumKey.self, value: n)
                }
            }
        }.node], id: "root"))

        XCTAssertEqual(heard.values, [10],
                       "seeds inside Group and ForEach folded as if written inline")
    }
}

/// Listens for `BlocksKey` above one child.
private struct EarList: View {
    let heard: Received<[BlocksKey.Layout]>
    let inside: () -> any View

    init(
        heard: Received<[BlocksKey.Layout]>,
        @ViewBuilder inside: @escaping () -> any View
    ) {
        self.heard = heard
        self.inside = inside
    }

    var body: some View {
        VStack { inside() }
            .onPreferenceChange(BlocksKey.self) { heard.values.append($0) }
    }
}

/// A view reading `SumKey` behind its content, through the public modifier.
private struct Backed<Inside: View>: View {
    let inside: Inside

    init(@ViewBuilder inside: () -> Inside) {
        self.inside = inside()
    }

    var body: some View {
        VStack { inside }
            .backgroundPreferenceValue(SumKey.self) { sum in
                Text("heard \(Int(sum))")
            }
    }
}

/// The same read drawn over.
private struct Overlaid<Inside: View>: View {
    let inside: Inside

    init(@ViewBuilder inside: () -> Inside) {
        self.inside = inside()
    }

    var body: some View {
        VStack { inside }
            .overlayPreferenceValue(SumKey.self) { sum in
                Text("over \(Int(sum))")
            }
    }
}

/// Every `text` prop anywhere in a patch - what the backed layer wrote.
private func collectText(_ patch: HostPatch, into found: inout [String]) {
    if case .string(let text) = patch.props["text"] { found.append(text) }
    for child in patch.children { collectText(child, into: &found) }
}

private func collectText(_ patch: HostPatch) -> [String] {
    var found: [String] = []
    collectText(patch, into: &found)
    return found
}

/// The handler id of `event` anywhere in a patch, depth first.
private func findEvent(_ patch: HostPatch, _ event: String) -> Int? {
    if let id = patch.events?[Event(event)] { return id }
    for child in patch.children {
        if let id = findEvent(child, event) { return id }
    }
    return nil
}
