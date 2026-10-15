// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest
import CSwiftOmniUIWinUI

/// Counts actual arithmetic work, including work re-entered through XAML's MeasureOverride.
private final class CountedMeasureLayout: WinUILayoutView {
    override var hasNativeProposals: Bool { true }
    var extent = 40.0
    var calls: [Double?: Int] = [:]
    var arrangements = 0

    override func arrange(in bounds: Rect) { arrangements += 1 }

    override func contentSize(width: Double?) -> LayoutSize {
        calls[width, default: 0] += 1
        return LayoutSize(width: width ?? 80, height: extent)
    }
}

/// Words `depth` grids deep, each grid with words and a stack of its own beside them.
private func nest(_ depth: Int, _ words: String) -> Node {
    guard depth > 0 else { return Text(words).padding(2).node }

    return Grid {
        nest(depth - 1, words)
        Text("beside \(depth)").gridRow(1)
        VStack {
            Text("a \(depth)")
            Text("b \(depth)")
        }
        .gridColumn(1)
    }
    .rows(.auto, .auto)
    .columns(.auto, .fill)
    .padding(2)
    .node
}

final class WinUIMeasurementTests: XCTestCase {
    func testExistingBackgroundColourChangesDoNotRearrangeContent() {
        onUIThread {
            let panel = CountedMeasureLayout()
            panel.setBackground(Color.clear.propValue)
            WinUITestHost.window.show(panel)
            defer { WinUITestHost.window.show(nil) }
            swiftomniui_winui_update_layout(panel.handle)
            let arrangements = panel.arrangements
            let revision = panel.measurementRevision
            let box = panel.boxView
            panel.setBackground(Color.black.opacity(0.1).propValue)
            swiftomniui_winui_update_layout(panel.handle)
            XCTAssertEqual(panel.arrangements, arrangements)
            XCTAssertEqual(panel.measurementRevision, revision)
            XCTAssertTrue(panel.boxView === box)
        }
    }

    func testOnePatchInvalidatesSharedAncestorsOnceAcrossDifferentElements() throws {
        try onUIThread {
            let host = WinUIRenderer.running {
                VStack { Text("First").id("first"); Text("Second").id("second") }
            }
            host.layOut()
            let first = try XCTUnwrap(host.runtime.tree.root?.first(id: .manual("first")))
            let second = try XCTUnwrap(host.runtime.tree.root?.first(id: .manual("second")))
            let stack = try XCTUnwrap(host.views(WinUIStackView.self).first)
            let revision = stack.measurementRevision
            ProgramWrite.perform {
                first.winUI.invalidateMeasurements()
                second.winUI.invalidateMeasurements()
                XCTAssertEqual(stack.measurementRevision, revision + 1)
            }
            XCTAssertEqual(stack.measurementRevision, revision + 1)
        }
    }

    func testMeasurementBetweenWritesRearmsInvalidationInTheSameBatch() {
        onUIThread {
            let child = CountedMeasureLayout()
            let parent = WinUIStackView(axis: .vertical)
            parent.setItems([WinUILayoutItem(view: child)])
            XCTAssertEqual(parent.naturalSize(width: 320).height, 40)
            let revision = parent.measurementRevision
            ProgramWrite.perform {
                child.extent = 60
                child.invalidateMeasurements()
                child.invalidateMeasurements()
                XCTAssertEqual(parent.measurementRevision, revision + 1)
                XCTAssertEqual(parent.naturalSize(width: 320).height, 60)
                child.extent = 90
                child.invalidateMeasurements()
                XCTAssertEqual(parent.measurementRevision, revision + 2)
                XCTAssertEqual(parent.naturalSize(width: 320).height, 90)
            }
        }
    }

    func testNativePreparationDoesNotRepeatNestedContentArithmetic() {
        onUIThread {
            let child = CountedMeasureLayout()
            var root: WinUILayoutView = child
            for _ in 0..<8 {
                let stack = WinUIStackView(axis: .vertical)
                stack.setItems([WinUILayoutItem(view: root)])
                root = stack
            }
            for width in [320.0, 120, 320, 120, 320] {
                XCTAssertEqual(root.naturalSize(width: width).height, 40)
                root.prepareMeasure(width: width)
            }
            XCTAssertEqual(child.calls[320], 1)
            XCTAssertEqual(child.calls[120], 1)
            child.extent = 80
            child.invalidateMeasurements()
            XCTAssertEqual(root.naturalSize(width: 320).height, 80)
            root.prepareMeasure(width: 320)
            XCTAssertEqual(child.calls[320], 2)
        }
    }

    func testLoadedTextRefreshesNativeProposalsWithoutInvalidatingAnUnchangedView() {
        onUIThread {
            let label = WinUILabelView()
            label.setText("Unchanged words")
            let wide = label.measure(width: 280, height: nil)
            let narrow = label.measure(width: 80, height: nil)
            let revision = label.measurementRevision

            XCTAssertFalse(label.refreshMeasurementsAfterAttachment())
            XCTAssertEqual(label.measurementRevision, revision)
            WinUIView.arranging += 1
            XCTAssertEqual(label.measure(width: 280, height: nil), wide)
            XCTAssertEqual(label.measure(width: 80, height: nil), narrow)
            WinUIView.arranging -= 1

            label.setText("Words that now occupy several lines in the narrow proposal")
            XCTAssertTrue(label.refreshMeasurementsAfterAttachment())
            XCTAssertEqual(label.measurementRevision, revision + 1)
            WinUIView.arranging += 1
            XCTAssertNotEqual(label.measure(width: 80, height: nil), narrow,
                              "all remembered proposals must be refreshed before a later resize")
            WinUIView.arranging -= 1
        }
    }

    func testLoadedTextInvalidatesSharedLayoutAncestorsOncePerBatch() {
        onUIThread {
            let first = WinUIStackView(axis: .vertical)
            let second = WinUIStackView(axis: .vertical)
            let root = WinUIStackView(axis: .horizontal)
            first.setItems([WinUILayoutItem(view: WinUILabelView())])
            second.setItems([WinUILayoutItem(view: WinUILabelView())])
            root.setItems([WinUILayoutItem(view: first), WinUILayoutItem(view: second)])
            let revisions = [first, second, root].map(\.measurementRevision)

            WinUILayoutView.commitAttachedTextMeasurements([first, first, second])

            XCTAssertEqual(first.measurementRevision, revisions[0] + 1)
            XCTAssertEqual(second.measurementRevision, revisions[1] + 1)
            XCTAssertEqual(root.measurementRevision, revisions[2] + 1,
                           "both changed labels share one ancestor invalidation")
        }
    }

    func testLoadedTextCallbacksCoalesceAndKeepNativeLabels() throws {
        try onUIThread {
            let host = WinUIRenderer.running {
                VStack {
                    Text("First").id("first")
                    Text("Second").id("second")
                }
                .frame(width: 120)
            }
            for _ in 0..<4 { host.step(); host.layOut() }
            let first = try XCTUnwrap(host.view(id: .manual("first")) as? WinUILabelView)
            let second = try XCTUnwrap(host.view(id: .manual("second")) as? WinUILabelView)
            let stack = try XCTUnwrap(host.views(WinUIStackView.self).first)
            _ = first.measure(width: 120, height: nil)
            _ = second.measure(width: 120, height: nil)
            let before = stack.measurementRevision

            for label in [first, second] {
                label.nativeTextLoaded()
                label.nativeTextLoaded()
            }
            WinUIDoorbell.turn()
            XCTAssertEqual(stack.measurementRevision, before,
                           "a repeated Loaded callback cannot invalidate an unchanged row")

            first.setText("First label now wraps into several lines at this width")
            second.setText("Second label also wraps into several lines at this width")
            for label in [first, second] {
                label.nativeTextLoaded()
                label.nativeTextLoaded()
            }
            WinUIDoorbell.turn()
            XCTAssertEqual(stack.measurementRevision, before + 1,
                           "two changed labels invalidate their shared stack once")
            XCTAssertTrue(host.view(id: .manual("first")) === first)
            XCTAssertTrue(host.view(id: .manual("second")) === second)
        }
    }

    func testAPropertyInvalidatesEachMountedAndPlacingAncestorOnce() throws {
        try onUIThread {
            let host = WinUIRenderer.running {
                ScrollView {
                    VStack { HStack { VStack { Text("File") } } }
                }
                .frame(width: 320, height: 240)
            }
            let text = try XCTUnwrap(host.runtime.tree.root?.first(type: .text))
            let layouts = host.views(WinUILayoutView.self)
            let revisions = layouts.map(\.measurementRevision)
            text.winUI.invalidateMeasurements()
            for (layout, revision) in zip(layouts, revisions) {
                XCTAssertEqual(layout.measurementRevision, revision + 1,
                               "the mounted-parent and placing-parent paths must not invalidate the same layout twice")
            }
        }
    }

    func testNativePreparationReusesArithmeticAtTheSameWidth() {
        onUIThread {
            let child = CountedMeasureLayout()
            let parent = WinUIStackView(axis: .vertical)
            parent.setItems([WinUILayoutItem(view: child)])
            let revision = child.measurements.revision

            let size = parent.naturalSize(width: 320)
            XCTAssertEqual(size.height, 40)
            XCTAssertEqual(child.calls[320], 1, "XAML preparation must not recompute the child's just-sized subtree")
            XCTAssertEqual(child.measurements.revision, revision, "preparation is not content invalidation")
            child.prepareMeasure(width: 320)
            child.prepareMeasure(width: 320)
            XCTAssertEqual(child.calls[320], 1)

            child.extent = 96
            child.invalidateMeasurements()
            XCTAssertEqual(parent.naturalSize(width: 320).height, 96)
            XCTAssertEqual(child.calls[320], 2, "real content changes still discard the preparation and arithmetic")
        }
    }

    func testIndependentNativeMeasurementsStillRefreshAndReportChangedContent() {
        onUIThread {
            let child = CountedMeasureLayout()
            let parent = WinUIStackView(axis: .vertical)
            parent.setItems([WinUILayoutItem(view: child)])
            XCTAssertEqual(parent.naturalSize(width: 320).height, 40)
            let revision = child.measurements.revision

            // Model a size change WinUI observed independently of a Swift property patch.
            child.extent = 96
            _ = child.measure(width: Double(320), height: Double.infinity)
            XCTAssertGreaterThan(child.measurements.revision, revision)
            XCTAssertEqual(parent.naturalSize(width: 320).height, 96, "native size changes still reach the placing parent")
            XCTAssertEqual(child.calls[320], 2)
        }
    }

    func testColdNestedLayoutsSizeEachWidthOnceBeforeNativePreparation() {
        onUIThread {
            for depth in [2, 6, 12] {
                let child = CountedMeasureLayout()
                var root: WinUILayoutView = child
                for level in 0..<depth {
                    let parent: WinUILayoutView
                    switch level % 3 {
                    case 0: parent = WinUIStackView(axis: .vertical)
                    case 1: parent = WinUIZStackView()
                    default: parent = WinUISingleChildView()
                    }
                    parent.setItems([WinUILayoutItem(view: root)])
                    root = parent
                }
                let before = WinUILayoutView.sizings
                XCTAssertEqual(root.naturalSize(width: 320).height, 40)
                XCTAssertEqual(child.calls[320], 1, "depth \(depth) must not multiply native and arithmetic work")
                XCTAssertLessThanOrEqual(WinUILayoutView.sizings - before, depth + 1)
                _ = root.naturalSize(width: 240)
                let sized = WinUILayoutView.sizings
                for width in [320.0, 240, 320, 240] { _ = root.naturalSize(width: width) }
                XCTAssertEqual(child.calls[320], 1)
                XCTAssertEqual(child.calls[240], 1)
                XCTAssertEqual(WinUILayoutView.sizings, sized, "known proposals reuse the subtree")
            }
        }
    }

    func testReturningToACachedWidthPreparesNativeTextAtThatWidth() {
        onUIThread {
            let label = WinUILabelView()
            label.setText("A cached wide proposal must restore these native words after a narrow measurement")
            label.setTextFont(size: 17, attributes: nil, family: nil)
            let layout = WinUIStackView(axis: .vertical)
            layout.setItems([WinUILayoutItem(view: label)])

            _ = layout.naturalSize(width: 320)
            layout.prepareMeasure(width: 320)
            let wide = label.desiredSize
            _ = layout.naturalSize(width: 40)
            layout.prepareMeasure(width: 40)
            XCTAssertGreaterThan(label.desiredSize.height, wide.height)

            _ = layout.naturalSize(width: 320)
            layout.prepareMeasure(width: 320)
            XCTAssertEqual(label.desiredSize, wide, "XAML retains its last proposal, not all cached natural widths")
        }
    }

    func testOpeningAndExpandingDeepLazyRowsDoesBoundedSizingWork() throws {
        try onUIThread {
            let items = State(wrappedValue: Array(0..<10_000))
            let opening = WinUILayoutView.sizings
            let host = WinUIRenderer.running(reducesMotion: true) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items.wrappedValue) { number in
                            ModifiedContent(node: nest(3, "Row \(number)"))
                        }
                        .transition(.opacity)
                    }
                }
                .frame(width: 480, height: 320)
            }
            for _ in 0..<8 { host.step() }
            let lazy = try XCTUnwrap(host.views(WinUILazyView.self).first)
            XCTAssertLessThan(lazy.mounted.count, 80)
            // Count subtree sizings rather than wall time: a few width proposals per
            // visible layout are bounded independently of the ten-thousand-row source.
            XCTAssertLessThanOrEqual(WinUILayoutView.sizings - opening, host.views(WinUILayoutView.self).count * 12)

            let expanding = WinUILayoutView.sizings
            items.wrappedValue.insert(contentsOf: [10_000, 10_001], at: 2)
            for _ in 0..<8 { host.step() }
            XCTAssertLessThan(lazy.mounted.count, 80)
            XCTAssertLessThanOrEqual(WinUILayoutView.sizings - expanding, host.views(WinUILayoutView.self).count * 12)
            let settled = WinUILayoutView.sizings
            for _ in 0..<4 { host.step() }
            XCTAssertEqual(WinUILayoutView.sizings, settled, "the native layout must settle after expansion")
        }
    }

    func testArrangementUsesTheMeasurementForTheRequestedWidth() {
        onUIThread {
            let label = WinUILabelView()
            label.setText("Animate me")
            label.setTextFont(size: 17, attributes: nil, family: nil)
            let unconstrained = label.measure(width: nil, height: nil)
            let wide = label.measure(width: 400, height: nil)
            let narrow = label.measure(width: 40, height: nil)
            XCTAssertGreaterThan(narrow.height, wide.height)
            XCTAssertLessThan(narrow.width, wide.width)
            let clipped = label.measure(width: 400, height: 1)
            XCTAssertLessThan(clipped.height, wide.height)

            WinUIView.arranging += 1
            defer { WinUIView.arranging -= 1 }
            XCTAssertEqual(label.measure(width: nil, height: nil), unconstrained)
            XCTAssertEqual(label.measure(width: 400, height: nil), wide)
            XCTAssertEqual(label.measure(width: 399.7142857, height: nil), wide,
                           "native rounding must not fall back to the narrow or clipped measurement")
            XCTAssertEqual(label.measure(width: 40, height: nil), narrow)
            XCTAssertEqual(label.desiredSize, clipped, "reading a proposal must not remeasure XAML inside Arrange")
        }
    }

    func testANewArrangementWidthRepairsItsAncestorsAfterThePass() {
        onUIThread {
            let label = WinUILabelView()
            label.setText("Animate me")
            label.setTextFont(size: 17, attributes: nil, family: nil)
            let parent = WinUIZStackView()
            var item = WinUILayoutItem(view: label)
            item.values.margin = EdgeInsets(24, 16)
            parent.setItems([item])
            let grandparent = WinUIStackView(axis: .vertical)
            grandparent.setItems([WinUILayoutItem(view: parent)])
            let narrow = grandparent.naturalSize(width: 88)

            WinUIView.arranging += 1
            // This proposal has not been measured. Both ancestors must forget the provisional result,
            // even if repeated layout calculations asked for it more than once in the same pass.
            _ = grandparent.naturalSize(width: 448)
            _ = parent.naturalSize(width: 448)
            WinUIView.arranging -= 1
            WinUIDoorbell.turn()

            WinUIView.arranging += 1
            let wide = grandparent.naturalSize(width: 448)
            WinUIView.arranging -= 1
            XCTAssertGreaterThan(wide.width, narrow.width)
            XCTAssertLessThan(wide.height, narrow.height)
            let sizings = WinUILayoutView.sizings
            WinUIDoorbell.turn()
            XCTAssertEqual(grandparent.naturalSize(width: 448), wide)
            XCTAssertEqual(WinUILayoutView.sizings, sizings, "a known proposal must settle without another turn")
        }
    }

    func testChangedWordsAndFontDiscardMeasurementsAtOtherWidths() {
        onUIThread {
            let label = WinUILabelView()
            label.setText("short")
            label.setTextFont(size: 12, attributes: nil, family: nil)
            let before = label.measure(width: 400, height: nil)
            label.setText("Words changed after both wide and narrow proposals were cached")
            label.setTextFont(size: 24, attributes: nil, family: nil)
            // A measured property patch invalidates its native view through WinUIElement.
            label.invalidateMeasure()
            _ = label.measure(width: 80, height: nil)

            let reference = WinUILabelView()
            reference.setText(label.text)
            reference.setTextFont(size: 24, attributes: nil, family: nil)
            let expected = reference.measure(width: 400, height: nil)
            XCTAssertNotEqual(expected, before)

            WinUIView.arranging += 1
            _ = label.measure(width: 400, height: nil)
            WinUIView.arranging -= 1
            WinUIDoorbell.turn()
            WinUIView.arranging += 1
            defer { WinUIView.arranging -= 1 }
            XCTAssertEqual(label.measure(width: 400, height: nil), expected)
        }
    }

    func testGalleryTextKeepsItsNaturalSizeAndScrollSummaryHeight() throws {
        try onUIThread {
            let width = State(wrappedValue: 480.0)
            let words = State(wrappedValue: "Animate me")
            let font = State(wrappedValue: 17.0)
            let summary = "Fade, move, scale and spin a view - a state write inside withAnimation."
            let host = WinUIRenderer.running(reducesMotion: true) {
                ScrollView {
                    VStack {
                        Text(summary).font(.system(size: 15)).id("summary")
                        Text("Example")
                        ZStack {
                            VStack {
                                ZStack {
                                    Text(words.wrappedValue)
                                        .font(.system(size: font.wrappedValue))
                                        .padding(EdgeInsets(24, 16))
                                        .id("animated-label")
                                }
                                .background(Color("#4828D6"))
                                .shape(.roundedRectangle(32))
                                .clipsContent(true)
                                .horizontalAlignment(.center)
                                .id("capsule")
                                HStack { Button("Fade"); Button("Move"); Button("Scale"); Button("Spin") }
                                    .spacing(8)
                                    .horizontalAlignment(.center)
                            }
                            .spacing(12)
                            .contentPadding(16)
                        }
                        Text("Notes below the example").frame(height: 900)
                    }
                    .spacing(24)
                    .contentPadding(24)
                }
                .frame(width: width.wrappedValue)
                .horizontalAlignment(.start)
            }
            let label = try XCTUnwrap(host.views(WinUILabelView.self).first { $0.text == words.wrappedValue })
            let heading = try XCTUnwrap(host.view(id: .manual("summary")) as? WinUILabelView)
            let capsule = try XCTUnwrap(host.view(id: .manual("capsule")))
            let probe = WinUILabelView()
            let summaryProbe = WinUILabelView()
            summaryProbe.setText(summary)
            summaryProbe.setTextFont(size: 15, attributes: nil, family: nil)

            for (index, offered) in [480.0, 280.0, 480.0].enumerated() {
                withAnimation(nil) {
                    width.wrappedValue = offered
                    if index == 2 {
                        words.wrappedValue = "Animate again"
                        font.wrappedValue = 20
                    }
                }
                for _ in 0..<8 { host.step(); host.layOut() }
                probe.setText(words.wrappedValue)
                probe.setTextFont(size: font.wrappedValue, attributes: nil, family: nil)
                let oneLine = probe.measure(width: nil, height: nil)
                let expectedSummary = summaryProbe.measure(width: offered - 48, height: nil)
                let labelPlace = try XCTUnwrap(label.placed)
                let summaryPlace = try XCTUnwrap(heading.placed)
                let capsulePlace = try XCTUnwrap(capsule.placed)

                XCTAssertEqual(labelPlace.width, oneLine.width, accuracy: 1, "padding must not narrow the words")
                XCTAssertEqual(labelPlace.height, oneLine.height, accuracy: 1, "the capsule stays on one line")
                XCTAssertEqual(capsulePlace.width, oneLine.width + 48, accuracy: 1)
                XCTAssertEqual(capsulePlace.height, oneLine.height + 32, accuracy: 1)
                XCTAssertEqual(summaryPlace.height, expectedSummary.height, accuracy: 1, "no clipped summary")
                XCTAssertEqual(heading.laidOutFrame.height, expectedSummary.height, accuracy: 1)
                XCTAssertEqual(summaryPlace.y, 24, accuracy: 1)
                let sizings = WinUILayoutView.sizings
                for _ in 0..<4 { host.step(); host.layOut() }
                XCTAssertEqual(WinUILayoutView.sizings, sizings, "the text layout must settle")
            }
        }
    }

    /// A change sizes only the layouts above it, each once for each width it is asked about: words changing six
    /// grids deep leave every layout beside them as it was sized - a layout measured at every width asked of it
    /// sized its whole subtree again each time.
    func testAChangeSizesOnlyTheLayoutsAboveIt() {
        onUIThread {
            let words = State(wrappedValue: "short")
            let host = WinUIRenderer.running { ModifiedContent(node: nest(6, words.wrappedValue)) }
            host.layOut()

            let before = WinUILayoutView.sizings
            words.wrappedValue = "words a good deal longer"
            host.settle { host.views(WinUILabelView.self).contains { $0.text == "words a good deal longer" } }
            host.layOut()

            XCTAssertLessThanOrEqual(WinUILayoutView.sizings - before, 60, "a few for each grid above it, none beside")
        }
    }
}
