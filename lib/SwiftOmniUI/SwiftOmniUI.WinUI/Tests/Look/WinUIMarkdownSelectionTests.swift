// SPDX-FileCopyrightText: 2026 Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import Observation
import XCTest

private struct SelectionBlockLayout: Equatable, Sendable {
    let id: String
    let bounds: Anchor<Rect>
    let textLayouts: [Text.Layout]
}

private struct SelectionBlocksKey: PreferenceKey {
    static let defaultValue: [SelectionBlockLayout] = []
    static func reduce(value: inout [SelectionBlockLayout], nextValue: () -> [SelectionBlockLayout]) {
        value.append(contentsOf: nextValue())
    }
}

private struct SelectionLayoutInput: Equatable, Sendable {
    let anchors: [SelectionBlockLayout]
    let size: Size
}

@MainActor
private final class SelectionProbe {
    var anchors: [SelectionBlockLayout] = []
    var resolvedBounds: [Rect] = []
    var textOrigins: [Point] = []
    var sliceCounts: [Int] = []
    var containerSize: Size = .zero
    var dragEvents: [String] = []
    var hoverEvents: [String] = []
    var tapEvents: [String] = []
    var layoutUpdates = 0
    var lastProxy: GeometryProxy?
}

private struct ProbeSelectableText: ViewModifier {
    let id: String
    func body(content: Content) -> some View {
        content
            .backgroundPreferenceValue(Text.LayoutKey.self) { layouts in
                Color.clear
                    .backgroundPreferenceValue(SelectionBlocksKey.self) { nested in
                        let nestedTexts = nested.flatMap { $0.textLayouts }
                        Color.clear.anchorPreference(key: SelectionBlocksKey.self, value: .bounds) { bounds in
                            [
                                SelectionBlockLayout(
                                    id: id,
                                    bounds: bounds,
                                    textLayouts: layouts.filter { !nestedTexts.contains($0) }
                                )
                            ]
                        }
                    }
            }
    }
}

private struct ProbeSelectableContainer: ViewModifier {
    let probe: SelectionProbe
    @State private var selectedRect: Rect?

    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: "SelectionDocumentSpace")
            .backgroundPreferenceValue(SelectionBlocksKey.self) { anchors in
                GeometryReader { geometry in
                    Color.clear
                        .onChange(of: SelectionLayoutInput(anchors: anchors, size: geometry.size), initial: true) {
                            probe.layoutUpdates += 1
                            probe.lastProxy = geometry
                            probe.anchors = anchors
                            probe.containerSize = geometry.size
                            probe.resolvedBounds = anchors.map { geometry[$0.bounds] }
                            probe.textOrigins = anchors.flatMap { block in
                                block.textLayouts.map { geometry[$0.origin] }
                            }
                            probe.sliceCounts = anchors.flatMap { block in
                                block.textLayouts.map { layout in
                                    layout.reduce(0) { sum, line in
                                        sum + line.reduce(0) { $0 + $1.count }
                                    }
                                }
                            }
                        }
                }
            }
            .background {
                Canvas { context, _ in
                    if let rect = selectedRect {
                        var path = Path()
                        path.addRect(rect)
                        context.fill(path, with: .color(Color("#0000FF")))
                    }
                }
                .blendMode(.multiply)
                .allowsHitTesting(false)
            }
            .overlay {
                Canvas { context, _ in
                    if let rect = selectedRect {
                        var path = Path()
                        path.addRect(rect)
                        context.fill(path, with: .color(Color("#00FF00")))
                    }
                }
                .blendMode(.normal)
                .opacity(0.32)
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        probe.dragEvents.append("changed:\(Int(value.startLocation.x)),\(Int(value.startLocation.y))->\(Int(value.location.x)),\(Int(value.location.y))")
                        selectedRect = Rect(
                            min(value.startLocation.x, value.location.x),
                            min(value.startLocation.y, value.location.y),
                            abs(value.location.x - value.startLocation.x),
                            max(10, abs(value.location.y - value.startLocation.y))
                        )
                    }
                    .onEnded { value in
                        probe.dragEvents.append("ended:\(Int(value.location.x)),\(Int(value.location.y))")
                    }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    probe.hoverEvents.append("active:\(Int(point.x)),\(Int(point.y))")
                case .ended:
                    probe.hoverEvents.append("ended")
                }
            }
            .onTapGesture(count: 3) { probe.tapEvents.append("tap3") }
            .onTapGesture(count: 2) { probe.tapEvents.append("tap2") }
            .onTapGesture(count: 1) { probe.tapEvents.append("tap1") }
    }
}

final class WinUIMarkdownSelectionTests: XCTestCase {
    func testSelectableModifierPipelineProducesLayoutAndDrag() throws {
        try onUIThread {
            let probe = SelectionProbe()
            let host = WinUIRenderer.running {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        Text("First selectable line")
                            .modifier(ProbeSelectableText(id: "line1"))
                        Text("Second selectable line")
                            .modifier(ProbeSelectableText(id: "line2"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .modifier(ProbeSelectableContainer(probe: probe))
                }
                .frame(width: 400, height: 300)
            }

            host.settle {
                !probe.sliceCounts.isEmpty && probe.sliceCounts.allSatisfy { $0 > 0 } && probe.containerSize.width > 0
            }

            let allViewsDesc = host.views(WinUIView.self).map { "\(type(of: $0))(\($0.number)):\($0.frame):hear=\($0.hearing)" }
            let liveBounds = probe.lastProxy.map { g in probe.anchors.map { g[$0.bounds] } } ?? []
            let liveOrigins = probe.lastProxy.map { g in probe.anchors.flatMap { $0.textLayouts.map { g[$0.origin] } } } ?? []
            print("SEL_PROBE updates=\(probe.layoutUpdates) size=\(probe.containerSize) anchors=\(probe.anchors.count) bounds=\(probe.resolvedBounds) liveBounds=\(liveBounds) origins=\(probe.textOrigins) liveOrigins=\(liveOrigins) slices=\(probe.sliceCounts)")
            print("SEL_PROBE views=\(allViewsDesc)")

            XCTAssertGreaterThan(probe.containerSize.width, 0)
            XCTAssertEqual(probe.anchors.count, 2)
            XCTAssertEqual(probe.sliceCounts.count, 2)
            XCTAssertTrue(probe.resolvedBounds.allSatisfy { $0.width > 0 && $0.height > 0 }, "bounds=\(probe.resolvedBounds)")
            XCTAssertTrue(probe.sliceCounts.allSatisfy { $0 > 0 }, "slices=\(probe.sliceCounts)")

            // Find the view that holds drag hearing
            let dragViews = host.views(WinUIView.self).filter { $0.hearing.contains(.drags) }
            let pointerViews = host.views(WinUIView.self).filter { $0.hearing.contains(.pointer) }
            let target = try XCTUnwrap(dragViews.first)
            let reachesAt10 = target.reaches(10, 10)
            let hitsAt10 = target.hits(10, 10)
            print("SEL_PROBE dragViews=\(dragViews.count) pointerViews=\(pointerViews.count) targetFrame=\(target.frame) hits=\(hitsAt10) reaches=\(reachesAt10)")
            target.heard(.drag(.started, x: 0, y: 0, at: Point(x: 10, y: 10), from: Point(x: 10, y: 10)))
            target.heard(.drag(.running, x: 80, y: 2, at: Point(x: 90, y: 12), from: Point(x: 10, y: 10)))
            target.heard(.drag(.completed, x: 80, y: 2, at: Point(x: 90, y: 12), from: Point(x: 10, y: 10)))
            host.settle { probe.dragEvents.count >= 2 }

            print("SEL_PROBE dragEvents=\(probe.dragEvents) canvases=\(host.views(WinUICanvasView.self).map(\.frame))")
            XCTAssertFalse(probe.dragEvents.isEmpty)
        }
    }

    func testFixedContainerResolvesAnchorBoundsWhenGeometrySizeIsConstant() throws {
        try onUIThread {
            let probe = SelectionProbe()
            let host = WinUIRenderer.running {
                VStack(alignment: .leading, spacing: 8) {
                    Text("First selectable line")
                        .modifier(ProbeSelectableText(id: "line1"))
                    Text("Second selectable line")
                        .modifier(ProbeSelectableText(id: "line2"))
                    Spacer()
                }
                .frame(width: 400, height: 300, alignment: .topLeading)
                .modifier(ProbeSelectableContainer(probe: probe))
            }

            host.settle {
                !probe.sliceCounts.isEmpty && probe.sliceCounts.allSatisfy { $0 > 0 } && probe.containerSize.width > 0
            }
            // Give native layout / FrameFollowers extra frames to settle without changing geometry.size.
            for _ in 0..<10 {
                host.runtime.pump.turn()
                host.layOut()
            }
            let liveBounds = probe.lastProxy.map { g in probe.anchors.map { g[$0.bounds] } } ?? []
            let liveOrigins = probe.lastProxy.map { g in probe.anchors.flatMap { $0.textLayouts.map { g[$0.origin] } } } ?? []
            print("SEL_FIXED updates=\(probe.layoutUpdates) size=\(probe.containerSize) probeBounds=\(probe.resolvedBounds) liveBounds=\(liveBounds) probeOrigins=\(probe.textOrigins) liveOrigins=\(liveOrigins)")

            XCTAssertTrue(probe.resolvedBounds.allSatisfy { $0.width > 0 && $0.height > 0 },
                          "onChange(SelectionLayoutInput) never received non-zero anchor bounds: probeBounds=\(probe.resolvedBounds) liveBounds=\(liveBounds)")
        }
    }

    func testFixedScrollViewContainerWithLazyVStackAndCoordinateSpace() {
        onUIThread {
            let probe = SelectionProbe()
            let host = WinUIRenderer.running {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        Text("First selectable line")
                            .modifier(ProbeSelectableText(id: "line1"))
                        Text("Second selectable line")
                            .modifier(ProbeSelectableText(id: "line2"))
                        Text("Third selectable line")
                            .modifier(ProbeSelectableText(id: "line3"))
                        Text("Fourth selectable line")
                            .modifier(ProbeSelectableText(id: "line4"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .coordinateSpace(name: "SelectionDocumentSpace")
                    .modifier(ProbeSelectableContainer(probe: probe))
                }
                .frame(width: 400, height: 300)
            }

            host.settle {
                !probe.sliceCounts.isEmpty && probe.sliceCounts.allSatisfy { $0 > 0 } && probe.containerSize.width > 0
            }
            // Let all pending layout/frame callbacks finish even if geometry.size stops changing.
            for _ in 0..<10 {
                host.runtime.pump.turn()
                host.layOut()
            }
            let liveBounds = probe.lastProxy.map { g in probe.anchors.map { g[$0.bounds] } } ?? []
            let liveOrigins = probe.lastProxy.map { g in probe.anchors.flatMap { $0.textLayouts.map { g[$0.origin] } } } ?? []
            let namedFrame = probe.lastProxy.map { $0.frame(in: .named("SelectionDocumentSpace")) }
            print("SEL_SCROLL_FIXED updates=\(probe.layoutUpdates) size=\(probe.containerSize) named=\(String(describing: namedFrame)) probeBounds=\(probe.resolvedBounds) liveBounds=\(liveBounds) probeOrigins=\(probe.textOrigins) liveOrigins=\(liveOrigins) slices=\(probe.sliceCounts)")

            // Also test tap counts and Canvas redraw.
            let tapViews = host.views(WinUIView.self).filter { $0.hearing.contains(.taps) }
            probe.tapEvents.removeAll()
            for view in tapViews {
                view.heard(.tap(run: 1))
                host.settle { probe.tapEvents.count == 1 }
                view.heard(.tap(run: 2))
                host.settle { probe.tapEvents.count == 2 }
                view.heard(.tap(run: 3))
                host.settle { probe.tapEvents.count == 3 }
            }
            print("SEL_SCROLL_FIXED tapViews=\(tapViews.count) tapEvents=\(probe.tapEvents)")

            XCTAssertEqual(probe.tapEvents, ["tap1", "tap2", "tap3"])
            XCTAssertTrue(probe.resolvedBounds.allSatisfy { $0.width > 0 && $0.height > 0 },
                          "onChange(SelectionLayoutInput) had empty anchor bounds: probeBounds=\(probe.resolvedBounds) liveBounds=\(liveBounds)")
        }
    }

    func testSelectableOutsideScrollViewAndObservableCanvas() {
        onUIThread {
            let probe = SelectionProbe()
            let host = WinUIRenderer.running {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        Text("First selectable line")
                            .modifier(ProbeSelectableText(id: "line1"))
                        Text("Second selectable line")
                            .modifier(ProbeSelectableText(id: "line2"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 400, height: 300)
                .coordinateSpace(name: "SelectionDocumentSpace")
                .modifier(ProbeSelectableContainer(probe: probe))
            }

            host.settle {
                !probe.sliceCounts.isEmpty && probe.sliceCounts.allSatisfy { $0 > 0 } && probe.containerSize.width > 0
            }
            for _ in 0..<15 {
                host.runtime.pump.turn()
                host.layOut()
            }
            let liveBounds = probe.lastProxy.map { g in probe.anchors.map { g[$0.bounds] } } ?? []
            let liveOrigins = probe.lastProxy.map { g in probe.anchors.flatMap { $0.textLayouts.map { g[$0.origin] } } } ?? []
            print("SEL_OUTSIDE updates=\(probe.layoutUpdates) size=\(probe.containerSize) probeBounds=\(probe.resolvedBounds) liveBounds=\(liveBounds) probeOrigins=\(probe.textOrigins) liveOrigins=\(liveOrigins) slices=\(probe.sliceCounts)")

            XCTAssertTrue(probe.resolvedBounds.allSatisfy { $0.width > 0 && $0.height > 0 },
                          "Outside ScrollView lost anchor bounds when size stayed constant: probeBounds=\(probe.resolvedBounds) liveBounds=\(liveBounds)")
        }
    }
}

@Observable
private final class ObservableSelectionState {
    var highlightRect: Rect?
    var canvasDraws = 0
}

private struct ObservableSelectableView: View {
    let probe: SelectionProbe
    @State private var model = ObservableSelectionState()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(0..<30, id: \.self) { index in
                    Text("Selectable paragraph number \(index) with enough words to lay out cleanly.")
                        .modifier(ProbeSelectableText(id: "p-\(index)"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .coordinateSpace(name: "SelectionDocumentSpace")
            .backgroundPreferenceValue(SelectionBlocksKey.self) { anchors in
                GeometryReader { geometry in
                    Color.clear
                        .onChange(of: SelectionLayoutInput(anchors: anchors, size: geometry.size), initial: true) {
                            probe.layoutUpdates += 1
                            probe.containerSize = geometry.size
                            probe.anchors = anchors
                            probe.lastProxy = geometry
                            probe.resolvedBounds = anchors.map { geometry[$0.bounds] }
                            probe.textOrigins = anchors.flatMap { $0.textLayouts.map { geometry[$0.origin] } }
                            var counts: [Int] = []
                            for anchor in anchors {
                                for layout in anchor.textLayouts {
                                    var sum = 0
                                    for line in layout {
                                        for run in line { sum += run.count }
                                    }
                                    counts.append(sum)
                                }
                            }
                            probe.sliceCounts = counts
                        }
                }
            }
            .overlay {
                Canvas { context, _ in
                    model.canvasDraws += 1
                    if let rect = model.highlightRect {
                        context.fill(Path(rect), with: .color(.blue.opacity(0.4)))
                    }
                }
                .blendMode(.multiply)
                .allowsHitTesting(false)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        probe.dragEvents.append("drag:\(Int(value.startLocation.x)),\(Int(value.startLocation.y))->\(Int(value.location.x)),\(Int(value.location.y))")
                        model.highlightRect = Rect(0, 0, max(10, abs(value.location.x - value.startLocation.x)), 20)
                    }
            )
        }
        .frame(width: 400, height: 300)
    }
}

extension WinUIMarkdownSelectionTests {
    func testObservableCanvasRedrawAndManyLazyRowsLayoutTiming() {
        onUIThread {
            let probe = SelectionProbe()
            let host = WinUIRenderer.running {
                ObservableSelectableView(probe: probe)
            }

            host.settle {
                !probe.sliceCounts.isEmpty && probe.sliceCounts.allSatisfy { $0 > 0 } && probe.containerSize.width > 0
            }
            for _ in 0..<40 {
                host.runtime.pump.turn()
                host.layOut()
            }
            let liveBounds = probe.lastProxy.map { g in probe.anchors.map { g[$0.bounds] } } ?? []
            let zeroBoundsInProbe = probe.resolvedBounds.filter { $0.width <= 0 || $0.height <= 0 }.count
            let zeroBoundsLive = liveBounds.filter { $0.width <= 0 || $0.height <= 0 }.count
            print("SEL_MANY updates=\(probe.layoutUpdates) anchors=\(probe.anchors.count) size=\(probe.containerSize) zeroInProbe=\(zeroBoundsInProbe) zeroLive=\(zeroBoundsLive) firstProbe=\(String(describing: probe.resolvedBounds.first)) firstLive=\(String(describing: liveBounds.first))")

            let dragTarget = host.views(WinUIView.self).first { $0.hearing.contains(.drags) }
            XCTAssertNotNil(dragTarget)
            let targetOrigin = dragTarget?.origin ?? Point(x: 0, y: 0)
            dragTarget?.heard(.drag(.started, x: 0, y: 0, at: Point(x: targetOrigin.x + 10, y: targetOrigin.y + 10), from: Point(x: targetOrigin.x + 10, y: targetOrigin.y + 10)))
            dragTarget?.heard(.drag(.running, x: 90, y: 4, at: Point(x: targetOrigin.x + 100, y: targetOrigin.y + 14), from: Point(x: targetOrigin.x + 10, y: targetOrigin.y + 10)))
            dragTarget?.heard(.drag(.completed, x: 90, y: 4, at: Point(x: targetOrigin.x + 100, y: targetOrigin.y + 14), from: Point(x: targetOrigin.x + 10, y: targetOrigin.y + 10)))
            host.settle { !probe.dragEvents.isEmpty }
            let canvasDrawProps = host.views(WinUICanvasView.self).map {
                if case .values(let items)? = $0.sourceElement?.value(.drawable) { return items.count }
                return 0
            }
            print("SEL_MANY dragEvents=\(probe.dragEvents) canvasDrawCounts=\(canvasDrawProps) modelDraws=\(probe.tapEvents.count)")

            XCTAssertEqual(zeroBoundsLive, 0)
            XCTAssertEqual(zeroBoundsInProbe, 0, "onChange(SelectionLayoutInput) saw zero bounds when Text.Layout arrived!")
            XCTAssertTrue(canvasDrawProps.contains(where: { $0 > 0 }), "Canvas did not redraw with non-empty commands when @Observable model changed! props=\(canvasDrawProps)")
        }
    }

    func testNestedMakeTextSelectableAndDelayedBlockAnchorResolveWhenGeometrySizeConstant() {
        onUIThread {
            let probe = SelectionProbe()

            struct DelayedSelectableBlockView: View {
                let probe: SelectionProbe
                @State private var showExtraBlock = false

                var body: some View {
                    VStack(alignment: .leading, spacing: 12) {
                        Button("Show Extra") {
                            showExtraBlock = true
                        }
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                // Outer nested selectable (like Blockquote) wrapping inner selectable (like InlineContentView)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("First nested selectable line")
                                        .backgroundPreferenceValue(Text.LayoutKey.self) { layouts in
                                            Color.clear
                                                .backgroundPreferenceValue(SelectionBlocksKey.self) { nested in
                                                    let nestedTexts = nested.flatMap { $0.textLayouts }
                                                    Color.clear.anchorPreference(key: SelectionBlocksKey.self, value: .bounds) { bounds in
                                                        [SelectionBlockLayout(id: "inner-1", bounds: bounds, textLayouts: layouts.filter { !nestedTexts.contains($0) })]
                                                    }
                                                }
                                        }
                                }
                                .padding(.leading, 12)
                                .backgroundPreferenceValue(Text.LayoutKey.self) { layouts in
                                    Color.clear
                                        .backgroundPreferenceValue(SelectionBlocksKey.self) { nested in
                                            let nestedTexts = nested.flatMap { $0.textLayouts }
                                            Color.clear.anchorPreference(key: SelectionBlocksKey.self, value: .bounds) { bounds in
                                                [SelectionBlockLayout(id: "outer-quote", bounds: bounds, textLayouts: layouts.filter { !nestedTexts.contains($0) })]
                                            }
                                        }
                                }

                                if showExtraBlock {
                                    Text("Delayed appended selectable line")
                                        .backgroundPreferenceValue(Text.LayoutKey.self) { layouts in
                                            Color.clear
                                                .backgroundPreferenceValue(SelectionBlocksKey.self) { nested in
                                                    let nestedTexts = nested.flatMap { $0.textLayouts }
                                                    Color.clear.anchorPreference(key: SelectionBlocksKey.self, value: .bounds) { bounds in
                                                        [SelectionBlockLayout(id: "delayed-2", bounds: bounds, textLayouts: layouts.filter { !nestedTexts.contains($0) })]
                                                    }
                                                }
                                        }
                                }
                            }
                            .frame(width: 400, height: 300, alignment: .topLeading)
                            .coordinateSpace(name: "SelectionDocumentSpace")
                            .backgroundPreferenceValue(SelectionBlocksKey.self) { anchors in
                                GeometryReader { geometry in
                                    Color.clear
                                        .onChange(of: SelectionLayoutInput(anchors: anchors, size: geometry.size), initial: true) { _, _ in
                                            probe.layoutUpdates += 1
                                            probe.anchors = anchors
                                            probe.containerSize = geometry.size
                                            probe.lastProxy = geometry
                                            probe.resolvedBounds = anchors.map { geometry[$0.bounds] }
                                            probe.textOrigins = anchors.flatMap { $0.textLayouts.map { geometry[$0.origin] } }
                                            probe.sliceCounts = anchors.flatMap { $0.textLayouts.map { $0.flatMap { $0.flatMap { $0 } }.count } }
                                        }
                                }
                            }
                        }
                        .frame(width: 400, height: 300)
                    }
                    .frame(width: 500, height: 400)
                }
            }

            let host = WinUIRenderer.running {
                DelayedSelectableBlockView(probe: probe)
            }
            host.settle { probe.anchors.count == 2 && probe.resolvedBounds.allSatisfy { $0.width > 0 && $0.height > 0 } }
            let initialZeroBounds = probe.resolvedBounds.filter { $0.width <= 0 || $0.height <= 0 }.count
            XCTAssertEqual(initialZeroBounds, 0, "Nested initial blocks had zero bounds: \(probe.resolvedBounds)")

            // Now mount a delayed block while containerSize stays fixed at 400x300.
            let button = host.views(WinUIButtonView.self).first
            XCTAssertNotNil(button)
            button?.invoke()
            host.settle { probe.anchors.count == 3 && probe.resolvedBounds.allSatisfy { $0.width > 0 && $0.height > 0 } }
            for _ in 0..<25 {
                host.runtime.pump.turn()
                host.layOut()
            }
            let delayedZeroBounds = probe.resolvedBounds.filter { $0.width <= 0 || $0.height <= 0 }.count
            let liveBounds: [Rect] = probe.lastProxy.map { g in probe.anchors.map { g[$0.bounds] } } ?? []
            let liveZeroBounds = liveBounds.filter { $0.width <= 0 || $0.height <= 0 }.count
            print("SEL_DELAYED updates=\(probe.layoutUpdates) anchors=\(probe.anchors.count) bounds=\(probe.resolvedBounds) origins=\(probe.textOrigins)")
            XCTAssertEqual(probe.anchors.count, 3)
            XCTAssertEqual(liveZeroBounds, 0)
            XCTAssertEqual(delayedZeroBounds, 0, "onChange(SelectionLayoutInput) saw zero bounds for delayed block!")
            let firstMinY = probe.resolvedBounds.first?.y ?? 999
            let lastMinY = probe.resolvedBounds.last?.y ?? 0
            XCTAssertTrue(lastMinY > firstMinY)
        }
    }

    func testCodeBlockSelectionHighlightAlignmentInNavigationSplitView() throws {
        try onUIThread {
            let probe = SelectionProbe()
            let code = """
            @echo off
            setlocal DisableDelayedExpansion
            "%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0.scripts\\msix\\Package.ps1" %*
            set "LUI_EXIT=%ERRORLEVEL%"
            if not "%LUI_EXIT%"=="0" echo Packaging failed. See the log path printed above.
            """
            let columns = State(wrappedValue: NavigationSplitViewVisibility.all)
            let host = WinUIRenderer.running(room: LayoutSize(width: 1400, height: 900)) {
                NavigationSplitView(columnVisibility: columns.projectedValue) {
                    Text("Sidebar")
                        .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 400)
                } detail: {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            Text(code)
                                .padding(.all, 16)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                                .modifier(ProbeSelectableText(id: "code"))
                                .compositingGroup()
                                .drawingGroup()
                        }
                        .modifier(ProbeSelectableContainer(probe: probe))
                        .padding(.all, 16)
                    }
                }
            }
            host.settle {
                !probe.textOrigins.isEmpty
                    && !probe.resolvedBounds.isEmpty
                    && probe.resolvedBounds.allSatisfy { $0.width > 0 && $0.height > 0 }
                    && !probe.sliceCounts.isEmpty
                    && probe.sliceCounts.allSatisfy { $0 > 0 }
            }
            for _ in 0..<10 {
                host.runtime.pump.turn()
                host.layOut()
            }
            let textView = try XCTUnwrap(host.views(WinUILabelView.self).first(where: { $0.text.contains("@echo off") }))
            let canvases = host.views(WinUICanvasView.self)
            let scroll = try XCTUnwrap(host.views(WinUIScrollView.self).last)
            let textOriginInWindow = textView.origin
            let scrollOriginInWindow = scroll.origin
            let canvasOriginsInWindow = canvases.map(\.origin)
            let reportedTextOrigin = try XCTUnwrap(probe.textOrigins.first)
            let reportedBounds = try XCTUnwrap(probe.resolvedBounds.first)
            let firstSliceRect = probe.anchors.first?.textLayouts.first?.first?.first?.typographicBounds.rect ?? Rect(0, 0, 0, 0)
            print("SEL_NSV textWin=\(textOriginInWindow) scrollWin=\(scrollOriginInWindow) canvasesWin=\(canvasOriginsInWindow) reportedOrigin=\(reportedTextOrigin) reportedBounds=\(reportedBounds) firstSlice=\(firstSliceRect) containerSize=\(probe.containerSize)")
            // Text sits at 16pt (LazyVStack padding) + 16pt (code block padding) inside the ScrollView,
            // while SelectionHighlightLayer Canvas sits at 16pt inside the ScrollView (`origin` in container coords).
            let expectedRelativeX = textOriginInWindow.x - (canvasOriginsInWindow.last?.x ?? scrollOriginInWindow.x)
            let expectedRelativeY = textOriginInWindow.y - (canvasOriginsInWindow.last?.y ?? scrollOriginInWindow.y)
            XCTAssertEqual(reportedTextOrigin.x, expectedRelativeX, accuracy: 2.0, "reportedOrigin=\(reportedTextOrigin) vs expectedRelativeX=\(expectedRelativeX)")
            XCTAssertEqual(reportedTextOrigin.y, expectedRelativeY, accuracy: 2.0, "reportedOrigin=\(reportedTextOrigin) vs expectedRelativeY=\(expectedRelativeY)")
        }
    }

    func testFileEdittingViewLayoutSelectionAlignment() throws {
        try onUIThread {
            let probe = SelectionProbe()
            let code = """
            @echo off
            setlocal DisableDelayedExpansion
            "%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0.scripts\\msix\\Package.ps1" %*
            set "LUI_EXIT=%ERRORLEVEL%"
            if not "%LUI_EXIT%"=="0" echo Packaging failed. See the log path printed above.
            """
            let columns = State(wrappedValue: NavigationSplitViewVisibility.all)
            let path = State(wrappedValue: ["doc"])
            let host = WinUIRenderer.running(room: LayoutSize(width: 1200, height: 800)) {
                NavigationSplitView(columnVisibility: columns.projectedValue) {
                    Text("Sidebar")
                        .navigationSplitViewColumnWidth(min: 256, ideal: 256, max: 640)
                } detail: {
                    NavigationStack(path: path.projectedValue) {
                        Text("Root")
                            .navigationDestination(for: String.self) { _ in
                                ScrollView {
                                    LazyVStack(alignment: .leading) {
                                        ForEach(["code"], id: \.self) { _ in
                                            Text(code)
                                                .padding(.all, 16)
                                                .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                                                .modifier(ProbeSelectableText(id: "code"))
                                                .compositingGroup()
                                                .drawingGroup()
                                        }
                                        .foregroundColor(Color.black)
                                    }
                                    .modifier(ProbeSelectableContainer(probe: probe))
                                    .padding(.all, 16)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .safeAreaInset(edge: .top, spacing: 0) {
                                    HStack {
                                        Text("LogorythiaUI > package-msix.bat")
                                    }
                                    .frame(height: 32)
                                }
                                .background(Color.white)
                            }
                    }
                }
            }
            host.settle {
                !probe.textOrigins.isEmpty
                    && !probe.resolvedBounds.isEmpty
                    && probe.resolvedBounds.allSatisfy { $0.width > 0 && $0.height > 0 }
                    && !probe.sliceCounts.isEmpty
                    && probe.sliceCounts.allSatisfy { $0 > 0 }
            }
            let textView = try XCTUnwrap(host.views(WinUILabelView.self).first(where: { $0.text.contains("@echo off") }))
            let canvases = host.views(WinUICanvasView.self)
            let overlayCanvas = try XCTUnwrap(canvases.last)
            let reportedOrigin = try XCTUnwrap(probe.textOrigins.first)
            let reportedBounds = try XCTUnwrap(probe.resolvedBounds.first)
            let expectedRelativeX = textView.origin.x - overlayCanvas.origin.x
            let expectedRelativeY = textView.origin.y - overlayCanvas.origin.y
            XCTAssertEqual(reportedOrigin.x, expectedRelativeX, accuracy: 2.0, "textOrigin=\(reportedOrigin) vs expected=(\(expectedRelativeX), \(expectedRelativeY)) textWin=\(textView.origin) canvasWin=\(overlayCanvas.origin)")
            XCTAssertEqual(reportedOrigin.y, expectedRelativeY, accuracy: 2.0, "textOrigin=\(reportedOrigin) vs expected=(\(expectedRelativeX), \(expectedRelativeY)) textWin=\(textView.origin) canvasWin=\(overlayCanvas.origin)")
            XCTAssertEqual(reportedBounds.x, 0, accuracy: 2.0, "resolvedBounds=\(reportedBounds)")
            XCTAssertEqual(reportedBounds.y, 0, accuracy: 2.0, "resolvedBounds=\(reportedBounds)")
        }
    }

    func testCodeMarkdownForEachDirectSelectable() throws {
        try onUIThread {
            let probe = SelectionProbe()
            let code = """
            @echo off
            set "LUI_EXIT=%ERRORLEVEL%"
            """
            let columns = State(wrappedValue: NavigationSplitViewVisibility.all)
            let host = WinUIRenderer.running(room: LayoutSize(width: 1200, height: 800)) {
                NavigationSplitView(columnVisibility: columns.projectedValue) {
                    Text("Sidebar")
                        .navigationSplitViewColumnWidth(min: 256, ideal: 256, max: 640)
                } detail: {
                    ScrollView {
                        ForEach(["b1", "b2"], id: \.self) { id in
                            Text(id == "b1" ? code : "after")
                                .padding(.all, 16)
                                .modifier(ProbeSelectableText(id: id))
                        }
                        .modifier(ProbeSelectableContainer(probe: probe))
                        .padding(.all, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            host.settle {
                !probe.textOrigins.isEmpty
                    && probe.resolvedBounds.count == 2
                    && probe.resolvedBounds.allSatisfy { $0.width > 0 && $0.height > 0 }
                    && probe.sliceCounts.count == 2
                    && probe.sliceCounts.allSatisfy { $0 > 0 }
            }
            let textView = try XCTUnwrap(host.views(WinUILabelView.self).first(where: { $0.text.contains("@echo off") }))
            let secondView = try XCTUnwrap(host.views(WinUILabelView.self).first(where: { $0.text == "after" }))
            let canvases = host.views(WinUICanvasView.self)
            XCTAssertEqual(canvases.count, 2, "Selection container wraps the ForEach fragment once instead of distributing per block")
            XCTAssertEqual(probe.textOrigins.count, 2)
            let overlayCanvas = canvases[1]
            XCTAssertGreaterThanOrEqual(overlayCanvas.laidOutFrame.height,
                                        textView.laidOutFrame.height + secondView.laidOutFrame.height - 1.0)
            let reportedOrigin = try XCTUnwrap(probe.textOrigins.first)
            let expectedRelativeX = textView.origin.x - overlayCanvas.origin.x
            let expectedRelativeY = textView.origin.y - overlayCanvas.origin.y
            XCTAssertEqual(reportedOrigin.x, expectedRelativeX, accuracy: 2.0, "textOrigin=\(reportedOrigin) vs expected=(\(expectedRelativeX), \(expectedRelativeY)) textWin=\(textView.origin) canvasWin=\(overlayCanvas.origin)")
            XCTAssertEqual(reportedOrigin.y, expectedRelativeY, accuracy: 2.0, "textOrigin=\(reportedOrigin) vs expected=(\(expectedRelativeX), \(expectedRelativeY)) textWin=\(textView.origin) canvasWin=\(overlayCanvas.origin)")
        }
    }

    func testCodeMarkdownMixedChineseAndSpansFullLineSelectionBounds() throws {
        try onUIThread {
            let probe = SelectionProbe()
            let para = Text("感谢您对 ")
                + Text("JsonData").bold()
                + Text(" 产生兴趣并有意愿为其贡献代码！为了降低沟通成本并优化代码审查体验，请仔细阅读以下要求。")
            let h1 = Text("提交代码与 PR 规范").bold()

            let host = WinUIRenderer.running(room: LayoutSize(width: 1024, height: 678)) {
                ScrollView {
                    ForEach(["h1", "p1"], id: \.self) { id in
                        (id == "h1" ? h1 : para)
                            .font(.system(size: id == "h1" ? 22 : 16))
                            .modifier(ProbeSelectableText(id: id))
                            .compositingGroup()
                            .drawingGroup()
                    }
                    .modifier(ProbeSelectableContainer(probe: probe))
                    .padding(.all, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            host.settle {
                probe.resolvedBounds.count == 2
                    && probe.resolvedBounds.allSatisfy { $0.width > 0 && $0.height > 0 }
                    && probe.sliceCounts.count == 2
                    && probe.sliceCounts.allSatisfy { $0 > 0 }
            }
            let labels = host.views(WinUILabelView.self)
            let canvases = host.views(WinUICanvasView.self)
            XCTAssertEqual(canvases.count, 2, "Selection container must produce one background and one overlay canvas")
            XCTAssertEqual(probe.anchors.count, 2)
            XCTAssertEqual(probe.resolvedBounds.count, 2)
            let paraAnchor = try XCTUnwrap(probe.anchors.last)
            let layout = try XCTUnwrap(paraAnchor.textLayouts.first)
            var glyphCount = 0
            var maxGlyphX = 0.0
            for line in layout {
                for run in line {
                    for slice in run {
                        glyphCount += 1
                        let bounds = slice.typographicBounds.rect
                        XCTAssertTrue(bounds.x.isFinite && bounds.width.isFinite && bounds.x >= 0 && bounds.x + bounds.width < 1000,
                                      "corrupt slice bounds: \(bounds)")
                        maxGlyphX = max(maxGlyphX, bounds.x + bounds.width)
                    }
                }
            }
            let paraLabel = try XCTUnwrap(labels.first(where: { $0.text.contains("感谢您") }))
            XCTAssertEqual(glyphCount, paraLabel.text.count, "layout slices must cover every character")
            XCTAssertGreaterThan(maxGlyphX, 400, "full paragraph line must reach past 400pt, got \(maxGlyphX)")
            XCTAssertLessThan(maxGlyphX, 1000, "full paragraph line must stay within container width, got \(maxGlyphX)")
            XCTAssertGreaterThan(probe.containerSize.width, 600, "containerSize must match full width, got \(probe.containerSize)")
            for canvas in canvases {
                XCTAssertGreaterThan(canvas.laidOutFrame.width, 600, "canvas=\(canvas.laidOutFrame)")
            }
        }
    }

    func testInlineSpansBoldBulletAndCjkGlyphGeometryMatchesNativeRenderedWidth() throws {
        try onUIThread {
            let probe = SelectionProbe()
            let line1 = Text(" • ").bold()
                + Text("包名 ")
                + Text("DocumentKit").font(.system(size: 13.3, design: .monospaced)).background(Color.gray.opacity(0.15))
                + Text("，只支持 macOS 15 起，Swift 6 (tools 6.0 / swiftLanguageModes ")
                + Text(".v6").font(.system(size: 13.3, design: .monospaced)).background(Color.gray.opacity(0.15))
                + Text(")")
            let line2 = Text(" • ").bold() + Text("依赖三个：")
            let line3 = Text(" ◦ ").bold() + Text("tomasf/Zip 2.1.0 —— 读写 zip，docx 本质就是 zip 包")
            let line4 = Text(" ◦ ").bold() + Text("CoreOffice/XMLCoder 0.17.0 —— XML 编解码，处理 OOXML")

            let host = WinUIRenderer.running(room: LayoutSize(width: 1200, height: 600)) {
                VStack(alignment: .leading, spacing: 8) {
                    line1.font(.system(size: 14)).modifier(ProbeSelectableText(id: "l1"))
                    line2.font(.system(size: 14)).modifier(ProbeSelectableText(id: "l2"))
                    line3.font(.system(size: 14)).modifier(ProbeSelectableText(id: "l3"))
                    line4.font(.system(size: 14)).modifier(ProbeSelectableText(id: "l4"))
                }
                .modifier(ProbeSelectableContainer(probe: probe))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            host.settle {
                probe.anchors.count == 4
                    && probe.sliceCounts.count == 4
                    && probe.sliceCounts.allSatisfy { $0 > 0 }
            }
            let labels = host.views(WinUILabelView.self)
            for (idx, id) in ["l1", "l2", "l3", "l4"].enumerated() {
                let anchor = try XCTUnwrap(probe.anchors.first(where: { $0.id == id }))
                let layout = try XCTUnwrap(anchor.textLayouts.first)
                let label = labels[idx]
                var maxX = 0.0
                var count = 0
                for line in layout {
                    for run in line {
                        for slice in run {
                            count += 1
                            maxX = max(maxX, slice.typographicBounds.rect.x + slice.typographicBounds.rect.width)
                        }
                    }
                }
                XCTAssertEqual(count, label.text.count, "id=\(id) slice count mismatch")
                XCTAssertEqual(maxX, label.laidOutFrame.width, accuracy: 2.0,
                               "id=\(id) synthetic glyph width (\(maxX)) fell short of XAML rendered width (\(label.laidOutFrame.width))")
            }
        }
    }

    func testManagementDialogueSidePanelMultiBlockSelectionAndDrag() throws {
        try onUIThread {
            struct MockMarkdownBlocks: View {
                let msgID: String
                let blocks: [String]
                var body: some View {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { idx, text in
                        Text(text)
                            .font(.system(size: 12))
                            .modifier(ProbeSelectableText(id: "\(msgID)-\(idx)"))
                            .compositingGroup()
                            .drawingGroup()
                    }
                }
            }
            struct StatelessManagementDialogueListView: View {
                let messages: [SideTestMsg]
                var body: some View {
                    ForEach(messages) { msg in
                        MockMarkdownBlocks(msgID: msg.id, blocks: msg.blocks)
                            .transition(.blur.combined(with: .offset(x: -48, y: 80)))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            struct SideHostView: View {
                let model: SideTestModel
                let leftProbe: SelectionProbe
                let probe: SelectionProbe
                @State private var sideWidth: Double = 320
                @State private var columns: NavigationSplitViewVisibility = .all
                @State private var scrollPos = ScrollPosition(edge: .bottom)
                var body: some View {
                    NavigationSplitView(columnVisibility: $columns) {
                        Text("Sidebar")
                            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 400)
                    } detail: {
                        NavigationStack {
                            GeometryReader { _ in
                                HStack(spacing: 0) {
                                    VStack {
                                        ScrollView {
                                            LazyVStack(alignment: .leading) {
                                                Text("Main dialogue line")
                                                    .modifier(ProbeSelectableText(id: "main-0"))
                                            }
                                            .modifier(ProbeSelectableContainer(probe: leftProbe))
                                            .padding(.all, 16)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .safeAreaInset(edge: .bottom) {
                                        Text("Composer").frame(height: 40)
                                    }

                                    if model.showSide {
                                        VStack {
                                            if model.selectAgent {
                                                ScrollView {
                                                    LazyVStack(alignment: .leading) {
                                                        StatelessManagementDialogueListView(messages: model.messages)
                                                        Color.clear.frame(height: 48)
                                                    }
                                                    .scrollTargetLayout()
                                                    .padding(.all, 8)
                                                    .modifier(ProbeSelectableContainer(probe: probe))
                                                }
                                                .scrollPosition($scrollPos, anchor: .bottom)
                                                .onChange(of: model.scrollTrigger) {
                                                    withAnimation(.snappy) {
                                                        scrollPos.scrollTo(edge: .bottom)
                                                    }
                                                }
                                                .transition(.identity)
                                                .id("agent-1")
                                            } else {
                                                ScrollView {
                                                    LazyVStack(alignment: .leading) {
                                                        Text("Group chat")
                                                            .modifier(ProbeSelectableText(id: "group-0"))
                                                    }
                                                    .padding(.all, 8)
                                                    .modifier(ProbeSelectableContainer(probe: SelectionProbe()))
                                                }
                                                .transition(.identity)
                                            }
                                        }
                                        .safeAreaInset(edge: .top, spacing: 0) {
                                            ScrollView(.horizontal) {
                                                HStack {
                                                    Button("Tab") {}
                                                }
                                                .padding(.all, 8)
                                            }
                                        }
                                        .hiddenSafeBarBackground(false)
                                        .frame(width: sideWidth)
                                        .overlay(alignment: .leading) {
                                            Color.clear
                                                .frame(width: 16)
                                                .contentShape(Rectangle())
                                                .gesture(DragGesture(minimumDistance: 0).onChanged { _ in })
                                                .offset(x: -8)
                                                .ignoresSafeArea()
                                        }
                                        .background(Color.white)
                                        .transition(.offset(x: sideWidth))
                                    }
                                }
                            }
                            .toolbar {
                                ToolbarItem(placement: .automatic) {
                                    Button("Toggle") {}
                                }
                            }
                        }
                    }
                }
            }

            let model = SideTestModel()
            let leftProbe = SelectionProbe()
            let probe = SelectionProbe()
            let host = WinUIRenderer.running(room: LayoutSize(width: 1200, height: 700)) {
                SideHostView(model: model, leftProbe: leftProbe, probe: probe)
            }
            host.settle { !leftProbe.sliceCounts.isEmpty }

            withAnimation(.snappy) {
                model.showSide = true
            }
            for _ in 0..<50 { host.step() }

            withAnimation(.snappy) {
                model.selectAgent = true
            }
            for _ in 0..<60 { host.step() }

            withAnimation(.snappy) {
                model.messages.append(SideTestMsg(id: "mTail", blocks: [
                    "Canvas 1920x1080 (16:9). Padding 96-120.",
                    "Now reply to the lead. Keep it a short paragraph-ish."
                ]))
                model.scrollTrigger += 1
            }
            for _ in 0..<80 { host.step() }

            let labels = host.views(WinUILabelView.self)
            let canvases = host.views(WinUICanvasView.self)
            let dragViews = host.views(WinUIView.self).filter { $0.hearing.contains(.drags) }
            let overlayCanvas = try XCTUnwrap(canvases.last)
            let sideLabels = labels.filter { $0.origin.x > 600 && ($0.text.hasPrefix("Message ") || $0.text.contains("Now reply") || $0.text.contains("Canvas 1920")) }
            let visibleSideLabels = sideLabels.filter { $0.origin.y >= 48 && $0.origin.y < 680 }
            XCTAssertFalse(visibleSideLabels.isEmpty,
                           "No visible side labels! allLabels=\(labels.map { "\($0.text.prefix(16))@\($0.origin)" }) anchors=\(probe.anchors.map(\.id))")
            let targetLabel = visibleSideLabels.first(where: { $0.text.contains("Now reply") }) ?? visibleSideLabels.last!
            let expectedX = targetLabel.origin.x - overlayCanvas.origin.x
            let expectedY = targetLabel.origin.y - overlayCanvas.origin.y
            let matchingIdx = try XCTUnwrap(
                probe.anchors.indices.first(where: { idx in
                    abs(probe.resolvedBounds[idx].y - expectedY) < 2.5
                }),
                "No anchor matched visible label '\(targetLabel.text.prefix(24))' expected=(\(expectedX),\(expectedY)) anchors=\(probe.anchors.map(\.id)) bounds=\(probe.resolvedBounds) origins=\(probe.textOrigins) canvas=\(overlayCanvas.origin)"
            )
            let matchedBounds = probe.resolvedBounds[matchingIdx]
            let matchedLayout = try XCTUnwrap(probe.anchors[matchingIdx].textLayouts.first)
            let liveOrigin = try XCTUnwrap(probe.lastProxy.map { $0[matchedLayout.origin] })
            let storedOrigin = probe.textOrigins[matchingIdx]

            let selDragTarget = try XCTUnwrap(dragViews.last(where: { $0.laidOutFrame.width > 100 && $0.origin.x > 600 }))
            let localClickX = targetLabel.origin.x - selDragTarget.origin.x + 20
            let localClickY = targetLabel.origin.y - selDragTarget.origin.y + 8
            let winStart = Point(x: targetLabel.origin.x + 20, y: targetLabel.origin.y + 8)
            let winEnd = Point(x: targetLabel.origin.x + 120, y: targetLabel.origin.y + 8)
            XCTAssertTrue(selDragTarget.reaches(localClickX, localClickY),
                          "HitTest blocked! target=\(selDragTarget.number)@\(selDragTarget.origin)/\(selDragTarget.laidOutFrame) label=\(targetLabel.origin) local=(\(localClickX),\(localClickY)) hits=\(selDragTarget.hits(localClickX, localClickY))")
            XCTAssertEqual(matchedBounds.x, expectedX, accuracy: 2.0, "matchedBounds=\(matchedBounds) expected=(\(expectedX),\(expectedY))")
            XCTAssertEqual(matchedBounds.y, expectedY, accuracy: 2.0, "matchedBounds=\(matchedBounds) expected=(\(expectedX),\(expectedY))")
            XCTAssertEqual(storedOrigin.x, expectedX, accuracy: 2.0, "storedOrigin=\(storedOrigin) liveOrigin=\(liveOrigin) expected=(\(expectedX),\(expectedY))")
            XCTAssertEqual(storedOrigin.y, expectedY, accuracy: 2.0, "storedOrigin=\(storedOrigin) liveOrigin=\(liveOrigin) expected=(\(expectedX),\(expectedY))")
            selDragTarget.heardPress(phase: 0, at: winStart)
            selDragTarget.heardPress(phase: 1, at: winEnd)
            selDragTarget.heardPress(phase: 2, at: winEnd)
            for _ in 0..<10 { host.step() }
            XCTAssertFalse(probe.dragEvents.isEmpty, "Drag over model label in side panel must fire DragGesture")
        }
    }

    func testTransitionOffsetSettlesSelectionAnchorAndOriginWithoutContainerResize() throws {
        try onUIThread {
            @MainActor
            struct FixedTransitionView: View {
                let model: SideTestModel
                let probe: SelectionProbe
                var body: some View {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            if model.selectAgent {
                                Text("Animated model output block with transition offset")
                                    .font(.system(size: 12))
                                    .modifier(ProbeSelectableText(id: "anim-0"))
                                    .transition(.blur.combined(with: .offset(x: -48, y: 80)))
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(width: 304, height: 400, alignment: .topLeading)
                        .padding(.all, 8)
                        .modifier(ProbeSelectableContainer(probe: probe))
                    }
                    .frame(width: 320, height: 300)
                }
            }
            let model = SideTestModel()
            let probe = SelectionProbe()
            let host = WinUIRenderer.running(room: LayoutSize(width: 400, height: 400)) {
                FixedTransitionView(model: model, probe: probe)
            }
            host.settle { probe.containerSize.width > 0 }
            withAnimation(.snappy) {
                model.selectAgent = true
            }
            for _ in 0..<80 { host.step() }

            let label = try XCTUnwrap(host.views(WinUILabelView.self).first)
            let overlayCanvas = try XCTUnwrap(host.views(WinUICanvasView.self).last)
            let expectedX = label.origin.x - overlayCanvas.origin.x
            let expectedY = label.origin.y - overlayCanvas.origin.y
            let bounds = try XCTUnwrap(probe.resolvedBounds.first)
            let origin = try XCTUnwrap(probe.textOrigins.first)
            XCTAssertEqual(bounds.x, expectedX, accuracy: 2.0, "Settled bounds X must not retain -48 transition offset: \(bounds)")
            XCTAssertEqual(bounds.y, expectedY, accuracy: 2.0, "Settled bounds Y must not retain +80 transition offset: \(bounds)")
            XCTAssertEqual(origin.x, expectedX, accuracy: 2.0, "Settled origin X must not retain -48 transition offset: \(origin)")
            XCTAssertEqual(origin.y, expectedY, accuracy: 2.0, "Settled origin Y must not retain +80 transition offset: \(origin)")
        }
    }

    func testOversizedScrollSelectionCanvasPaintsBeyondD3DTextureLimit() throws {
        try onUIThread {
            let probe = SelectionProbe()
            let host = WinUIRenderer.running(room: LayoutSize(width: 400, height: 500)) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 19_000)
                        Text("Deep management dialogue model output at 19000 DIPs")
                            .font(.system(size: 12))
                            .modifier(ProbeSelectableText(id: "deep-0"))
                        Color.clear.frame(height: 500)
                    }
                    .frame(width: 304, alignment: .leading)
                    .padding(.all, 8)
                    .modifier(ProbeSelectableContainer(probe: probe))
                }
                .frame(width: 320, height: 480)
            }
            host.settle { !probe.sliceCounts.isEmpty && probe.sliceCounts.allSatisfy { $0 > 0 } }
            let scroll = try XCTUnwrap(host.views(WinUIScrollView.self).first)
            swiftomniui_winui_scroller_move(scroll.scroller.handle, 0, 18_850, false)
            for _ in 0..<25 { host.step() }

            let canvases = host.views(WinUICanvasView.self)
            let overlayCanvas = try XCTUnwrap(canvases.last)
            XCTAssertGreaterThan(overlayCanvas.laidOutFrame.height, 19_000)

            let label = try XCTUnwrap(host.views(WinUILabelView.self).first)
            let dragViews = host.views(WinUIView.self).filter { $0.hearing.contains(.drags) }
            let selDragTarget = try XCTUnwrap(dragViews.first)
            let beforePaints = swiftomniui_winui_canvas_paints(overlayCanvas.handle)
            let winStart = Point(x: label.origin.x + 10, y: label.origin.y + 6)
            let winEnd = Point(x: label.origin.x + 140, y: label.origin.y + 6)
            selDragTarget.heardPress(phase: 0, at: winStart)
            selDragTarget.heardPress(phase: 1, at: winEnd)
            selDragTarget.heardPress(phase: 2, at: winEnd)
            for _ in 0..<20 { host.step() }

            let afterPaints = swiftomniui_winui_canvas_paints(overlayCanvas.handle)
            XCTAssertFalse(probe.dragEvents.isEmpty)
            XCTAssertGreaterThan(afterPaints, beforePaints,
                                 "Oversized selection overlay Canvas (> 16384 px) must successfully paint visible viewport tile")
        }
    }

    func testExplicitNewlineMultiLineShrinkWrappedParagraphDoesNotFalseWrap() throws {
        try onUIThread {
            let probe = SelectionProbe()
            let mplSection = """
            1.1. "Contributor"
            means each individual or legal entity that creates, contributes to
            the creation of, or owns Covered Software.
            """
            let host = WinUIRenderer.running(room: LayoutSize(width: 900, height: 400)) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(mplSection)
                        .font(.system(size: 14))
                        .lineSpacing(4)
                        .modifier(ProbeSelectableText(id: "mpl-1.1"))
                }
                .modifier(ProbeSelectableContainer(probe: probe))
                .padding(.all, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            host.settle {
                !probe.anchors.isEmpty && !probe.sliceCounts.isEmpty && probe.sliceCounts.allSatisfy { $0 > 0 }
            }
            let label = try XCTUnwrap(host.views(WinUILabelView.self).first)
            let layout = try XCTUnwrap(probe.anchors.first?.textLayouts.first)
            XCTAssertEqual(layout.count, 3,
                           "3-line explicit-newline paragraph must stay 3 lines without false soft-wrap creating a phantom 4th line")
            var lineMaxX: [Double] = []
            for line in layout {
                var mx = 0.0
                for run in line {
                    for slice in run {
                        mx = max(mx, slice.typographicBounds.rect.x + slice.typographicBounds.rect.width)
                    }
                }
                lineMaxX.append(mx)
            }
            XCTAssertEqual(lineMaxX[1], label.laidOutFrame.width, accuracy: 4.0,
                           "Longest middle line ('...contributes to') must reach full rendered width without wrapping 'to'")
            XCTAssertGreaterThan(lineMaxX[2], 200,
                                 "Third line ('the creation of, or owns Covered Software.') must stay complete on line 2")
        }
    }
}

private struct SideTestMsg: Identifiable {
    let id: String
    let blocks: [String]
}

@MainActor
@Observable
private final class SideTestModel {
    var showSide = false
    var selectAgent = false
    var scrollTrigger = 0
    var messages: [SideTestMsg] = (0..<25).map { idx in
        SideTestMsg(id: "m\(idx)", blocks: [
            "Message \(idx) first block with enough text to wrap across multiple lines in the 320pt management dialogue panel.",
            "Message \(idx) second block checking blackboard state and tool outputs."
        ])
    }
}
