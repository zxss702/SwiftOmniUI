// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) @testable import SwiftOmniUICore
@_spi(Host) @testable import SwiftOmniUIHost
@testable import SwiftOmniUIGTK
import CSwiftOmniUIGTK
import SwiftOmniUIConformance
import XCTest

/// A caption whose words a button lengthens, in a stack 300 wide travelling on a 200 ms linear law.
private struct LengtheningPage: View {
    @State private var long = false

    var body: some View {
        VStack {
            Text(long ? "Text & typing" : "Text").horizontalAlignment(.start)
            Button("Longer").onClicked { long = true }
        }
        .animation(.eased(200, .linear))
        .horizontalAlignment(.fill)
        .frame(width: 300)
        .horizontalAlignment(.start)
        .verticalAlignment(.start)
    }
}

/// A stack's children travel to the places a patch gives them; one that joins fades in, one hidden fades out first.
final class GTKLayoutMotionTests: XCTestCase {
    func testBottomInsetEditorGrowsAndShrinksWithItsBottomFixed() throws {
        try onUIThread {
            let clock = TestClock()
            let text = State(wrappedValue: "")
            let host = GTKRenderer.running(clock: clock) {
                ScrollView { Text("History") }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        let height = text.wrappedValue.isEmpty ? 40.0 : 128.0
                        VStack {
                            HStack(alignment: .bottom) {
                                Button("Attach") {}.frame(width: 40, height: 40).id("attach")
                                ZStack(alignment: .bottom) {
                                    TextEditor(text: text.projectedValue.transaction(.init(animation: .linear(duration: 0.2))))
                                        .scrollContentBackground(.hidden)
                                        .safeAreaPadding(.vertical, 12)
                                        .frame(height: height)
                                        .background { Color.white.id("editor-background") }
                                        .id("editor")
                                }.frame(height: height)
                            }
                        }.padding(16)
                    }
                    .hiddenSafeBarBackground()
            }
            for _ in 0..<4 { host.step(); host.frame() }
            let window = try XCTUnwrap(host.window)
            let input = try XCTUnwrap(host.views(GTKTextEditorView.self).first)
            let editor = try XCTUnwrap(host.view(id: .manual("editor")))
            let background = try XCTUnwrap(host.view(id: .manual("editor-background")))
            let attach = try XCTUnwrap(host.view(id: .manual("attach")))

            @MainActor func bounds(_ view: GTKView) -> (top: Double, height: Double) {
                var frame = graphene_rect_t()
                let found = gtk_widget_compute_bounds(view.widget, window.widget, &frame)
                XCTAssertNotEqual(found, 0)
                return (Double(frame.origin.y), Double(frame.size.height))
            }

            let initial = bounds(editor)
            let bottom = initial.top + initial.height
            let attachTop = bounds(attach).top
            for (words, start, end) in [("hello", 40.0, 128.0), ("", 128.0, 40.0)] {
                let began = clock.now
                input.setText(words)
                host.runtime.pump.turn()
                for elapsed in [0.0, 50, 100, 150, 200] {
                    clock.now = began + elapsed
                    host.frame()
                    let editorFrame = bounds(editor)
                    let backgroundFrame = bounds(background)
                    let expectedHeight = start + (end - start) * elapsed / 200
                    XCTAssertEqual(editorFrame.height, expectedHeight, accuracy: 2, "\(words) at \(elapsed) ms")
                    XCTAssertEqual(editorFrame.top + editorFrame.height, bottom, accuracy: 2)
                    XCTAssertEqual(backgroundFrame.top, editorFrame.top, accuracy: 1)
                    XCTAssertEqual(backgroundFrame.height, editorFrame.height, accuracy: 1)
                    XCTAssertEqual(bounds(attach).top, attachTop, accuracy: 1)
                }
                XCTAssertTrue(host.views(GTKTextEditorView.self).first === input)
            }
        }
    }

    func testDepartingWelcomeKeepsItsWindowPositionWhileItsParentReflows() throws {
        try onUIThread {
            let clock = TestClock()
            let expanded = State(wrappedValue: false)
            let host = GTKRenderer.running(clock: clock) {
                HStack(spacing: 0) {
                    if !expanded.wrappedValue {
                        Text("Recent").frame(width: 160, height: 300).transition(.opacity)
                    }
                    VStack(spacing: 12) {
                        if !expanded.wrappedValue {
                            Text("Welcome").frame(height: 100).transition(.opacity).id("welcome")
                        }
                        TextEditor().frame(height: expanded.wrappedValue ? 128 : 44)
                    }
                    .frame(width: expanded.wrappedValue ? 400 : 240)
                    .frame(maxHeight: .infinity)
                }
                .animation(.linear(duration: 0.2), value: expanded.wrappedValue)
            }
            host.frame()
            let view = try XCTUnwrap(host.view(id: .manual("welcome")))
            let window = try XCTUnwrap(host.window)
            var zero = graphene_point_t(x: 0, y: 0)
            var before = graphene_point_t()
            XCTAssertNotEqual(gtk_widget_compute_point(view.widget, window.widget, &zero, &before), 0)
            expanded.wrappedValue = true
            host.step()
            for time in stride(from: 0.0, through: 190.0, by: 10) {
                clock.now = time
                host.frame()
                var position = graphene_point_t()
                XCTAssertNotEqual(gtk_widget_compute_point(view.widget, window.widget, &zero, &position), 0)
                XCTAssertEqual(position.x, before.x, accuracy: 1)
                XCTAssertEqual(position.y, before.y, accuracy: 1)
            }
            clock.now = 200
            host.frame()
            XCTAssertNil(host.view(id: .manual("welcome")))
        }
    }

    func testAValueGatedColumnReversesFromItsPresentedFrame() throws {
        try onUIThread {
            let clock = TestClock()
            let expanded = State(wrappedValue: false)
            let host = GTKRenderer.running(clock: clock) {
                HStack(spacing: 0) {
                    Color.blue.frame(width: expanded.wrappedValue ? 400 : 200, height: 40)
                }
                .animation(.linear(duration: 0.2), value: expanded.wrappedValue)
                .id("column")
                .frame(width: 600, height: 100)
            }
            host.frame()
            let child = try XCTUnwrap(host.runtime.tree.root?.first(id: .manual("column"))?.children.first)
            let column = try XCTUnwrap(host.view(id: child.id))
            let initialX = column.frame.x
            expanded.wrappedValue = true
            host.runtime.pump.turn()
            host.frame()
            clock.now = 100
            host.frame()
            XCTAssertEqual(column.frame.x, initialX - 50, accuracy: 1)

            expanded.wrappedValue = false
            host.runtime.pump.turn()
            host.frame()
            XCTAssertEqual(column.frame.x, initialX - 50, accuracy: 1, "retargeting must not jump to either endpoint")
            clock.now = 200
            host.frame()
            XCTAssertEqual(column.frame.x, initialX - 37.5, accuracy: 1)
            clock.now = 300
            host.frame()
            XCTAssertEqual(column.frame.x, initialX, accuracy: 0.5)
            XCTAssertTrue(host.view(id: child.id) === column)
            XCTAssertFalse(host.runtime.animator.isMoving)
        }
    }

    func testAValueGatedColumnMovesWithinItsOuterFrame() throws {
        try onUIThread {
            let clock = TestClock()
            let expanded = State(wrappedValue: false)
            let host = GTKRenderer.running(clock: clock) {
                HStack(spacing: 0) {
                    Color.blue.frame(width: expanded.wrappedValue ? 400 : 200, height: 40)
                }
                .animation(.linear(duration: 0.2), value: expanded.wrappedValue)
                .id("column")
                .frame(width: 600, height: 100)
            }
            host.frame()
            let child = try XCTUnwrap(host.runtime.tree.root?.first(id: .manual("column"))?.children.first)
            let column = try XCTUnwrap(host.view(id: child.id))
            let before = column.frame
            expanded.wrappedValue = true
            host.runtime.pump.turn()
            host.frame()
            XCTAssertEqual(column.frame.x, before.x, accuracy: 0.5)
            clock.now = 100
            host.frame()
            let halfway = column.frame
            clock.now = 200
            host.frame()
            XCTAssertNotEqual(before.x, column.frame.x)
            XCTAssertEqual(halfway.x, (before.x + column.frame.x) / 2, accuracy: 1)
            XCTAssertTrue(host.view(id: child.id) === column)
        }
    }


    /// A label whose width travels lays its words out at the width it is bound for: they keep the one line they fit
    /// there, never breaking at the widths its place passes through.
    func testALabelsWordsStandAtTheWidthItTravelsTo() throws {
        try onUIThread {
            let clock = TestClock()
            let host = GTKRenderer.running(clock: clock) { LengtheningPage() }
            let label = try XCTUnwrap(host.views(GTKLabelView.self).first)

            try XCTUnwrap(host.views(GTKButtonView.self).first).click()
            host.runtime.pump.turn()
            host.layOut()
            clock.now += 100
            host.frame()

            var natural: Int32 = 0
            gtk_widget_measure(label.widget, GTK_ORIENTATION_HORIZONTAL, -1, nil, &natural, nil, nil)
            XCTAssertLessThan(label.placedFrame.width, Double(natural) - 1, "its place on its way")
            XCTAssertEqual(gtk_widget_get_width(label.widget), natural, "its words at the width it is bound for")
        }
    }

    /// A vertical stack of 100 x 40 labels in `order`, travelling on a 200 ms linear law; `hidden` fade out in 100 ms.
    private static func stack(_ order: [String], hidden: Set<String> = []) -> HostPatch {
        var stack = HostPatch(id: .manual("stack"), type: .vStack)
        stack.properties[.spacing] = .number(0)
        stack.animation = HostLayoutMotion(animation: .eased(200, .linear), lanes: .all)
        stack.children = .arranged(order.map { name in
            var row = HostPatch(id: .manual(name), type: .text)
            row.properties = [.text: .string(name), .width: .number(100), .height: .number(40)]
            row.properties[.isVisible] = .bool(!hidden.contains(name))
            row.animation = HostLayoutMotion(animation: .eased(100, .linear), lanes: .all)
            return row
        })
        return stack
    }

    func testAChildAPatchMovesTravelsToItsNewPlace() throws {
        try onUIThread {
            let clock = TestClock()
            let host = GTKRenderer.bare(clock: clock)
            host.apply(Self.stack(["a", "b"]))
            let moved = try XCTUnwrap(host.view(id: .manual("b")))
            host.layOut()
            let top = try XCTUnwrap(host.view(id: .manual("a"))).frame.y
            XCTAssertEqual(moved.frame.y, top + 40, "the first arrangement is an arrival")

            host.apply(Self.stack(["b", "a"]))
            host.layOut()
            XCTAssertEqual(moved.frame.y, top + 40, "a child starts from where it stood")

            clock.now = 100
            host.frame()
            XCTAssertEqual(moved.frame.y, top + 20, "halfway through a linear 200 ms animation")

            clock.now = 200
            host.frame()
            XCTAssertEqual(moved.frame.y, top, "and it lands exactly")
            XCTAssertFalse(host.runtime.animator.isMoving)
        }
    }

    func testAChildThatJoinsAStandingStackFadesIn() throws {
        try onUIThread {
            let clock = TestClock()
            let host = GTKRenderer.bare(clock: clock)
            host.apply(Self.stack(["a"]))
            host.layOut()

            host.apply(Self.stack(["a", "b"]))
            host.layOut()
            let joined = try XCTUnwrap(host.view(id: .manual("b")))
            XCTAssertEqual(joined.drawnOpacity, 0, accuracy: GTKView.opacityStep)

            clock.now = 100
            host.frame()
            XCTAssertEqual(joined.drawnOpacity, 0.5, accuracy: GTKView.opacityStep)

            clock.now = 200
            host.frame()
            XCTAssertEqual(joined.drawnOpacity, 1, accuracy: GTKView.opacityStep)
        }
    }

    func testWithLessMotionEveryChildArrives() throws {
        try onUIThread {
            let host = GTKRenderer.bare(clock: TestClock(), reducesMotion: true)
            host.apply(Self.stack(["a", "b"]))
            host.layOut()
            let top = try XCTUnwrap(host.view(id: .manual("a"))).frame.y

            host.apply(Self.stack(["b", "a"]))
            host.layOut()

            XCTAssertEqual(try XCTUnwrap(host.view(id: .manual("b"))).frame.y, top)
            XCTAssertFalse(host.runtime.animator.isMoving)
        }
    }

    /// The hidden row fades where it stands, keeping its room; once it has gone, the row below travels up.
    func testAStackClosesOverARowOnceItsFadeLands() throws {
        try onUIThread {
            let clock = TestClock()
            let host = GTKRenderer.bare(clock: clock)
            host.apply(Self.stack(["first", "second"]))
            let first = try XCTUnwrap(host.view(id: .manual("first")))
            let second = try XCTUnwrap(host.view(id: .manual("second")))
            host.layOut()
            let top = first.frame.y
            XCTAssertEqual(second.frame.y, top + 40)

            host.apply(Self.stack(["first", "second"], hidden: ["first"]))
            host.layOut()
            XCTAssertTrue(first.isShown, "still there, on its way out")

            clock.now = 50
            host.frame()
            XCTAssertEqual(first.drawnOpacity, 0.5, accuracy: GTKView.opacityStep)
            XCTAssertEqual(second.frame.y, top + 40)

            clock.now = 100
            host.frame()
            XCTAssertFalse(first.isShown, "gone when the fade landed")
            XCTAssertEqual(first.drawnOpacity, 1, accuracy: GTKView.opacityStep, "at the opacity the tree describes")
            XCTAssertEqual(second.frame.y, top + 40, "the row below starts once it has gone")

            clock.now = 200
            host.frame()
            XCTAssertEqual(second.frame.y, top + 30, "and travels into its place")

            clock.now = 300
            host.frame()
            XCTAssertEqual(second.frame.y, top + 20)
        }
    }

    func testARowShownAgainMidFadeComesBackFromWhereItStands() throws {
        try onUIThread {
            let clock = TestClock()
            let host = GTKRenderer.bare(clock: clock)
            host.apply(Self.stack(["first", "second"]))
            let first = try XCTUnwrap(host.view(id: .manual("first")))
            host.layOut()

            host.apply(Self.stack(["first", "second"], hidden: ["first"]))
            clock.now = 50
            host.frame()
            host.apply(Self.stack(["first", "second"]))
            XCTAssertEqual(first.drawnOpacity, 0.5, accuracy: GTKView.opacityStep, "up again from where the fade reached")

            clock.now = 150
            host.frame()
            XCTAssertEqual(first.drawnOpacity, 1, accuracy: GTKView.opacityStep)
            XCTAssertTrue(first.isShown, "and never gone")
        }
    }

    func testComposedForEachInsideFrameBackgroundAndScrollViewDoesNotCollapse() {
        onUIThread {
            let clock = TestClock()
            let host = GTKRenderer.running(clock: clock) {
                ScrollView {
                    GTKComposedBlocksView(lines: ["First", "Second", "Third"])
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            GeometryReader { _ in
                                Color.gray
                            }
                        )
                        .id("bubble")
                }
                .frame(width: 400, height: 300)
            }
            host.frame()
            let blocks = [0, 1, 2].compactMap { host.view(id: .manual("block-\($0)")) }
            XCTAssertEqual(blocks.count, 3)
            XCTAssertEqual(host.views(GTKLabelView.self).count, 3)
            XCTAssertGreaterThan(blocks[1].frame.y - blocks[0].frame.y, 20, "second block must sit below first")
            XCTAssertGreaterThan(blocks[2].frame.y - blocks[1].frame.y, 20, "third block must sit below second")
        }
    }

    func testSafeAreaInsetAndLazyStackKeepComposedAndLayeredBlocksSeparate() throws {
        try onUIThread {
            let clock = TestClock()
            let host = GTKRenderer.running(clock: clock) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(0..<2, id: \.self) { row in
                            GTKComposedBlocksView(lines: ["Row \(row) A", "Row \(row) B"])
                                .background { Color.gray }
                                .id("row-\(row)")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .safeAreaInset(edge: .bottom) {
                    GTKComposedBlocksView(lines: ["Inset 0", "Inset 1"])
                        .background { Color.blue }
                }
                .frame(width: 400, height: 400)
            }
            host.frame()
            let row0View = try XCTUnwrap(host.view(id: .manual("row-0"))?.placedFrame)
            let row1View = try XCTUnwrap(host.view(id: .manual("row-1"))?.placedFrame)
            XCTAssertGreaterThan(row0View.height, 50, "lazy row composed blocks must stack vertically")
            XCTAssertGreaterThan(row1View.y - row0View.y, 50, "second lazy row must sit below first row")
            let insetBar = try XCTUnwrap(host.views(GTKStackView.self).last)
            XCTAssertGreaterThan(insetBar.placedFrame.height, 50, "safeAreaInset composed blocks must stack vertically rather than collapse")
            let insetBlocks = insetBar.items.map { $0.view.placedFrame }
            XCTAssertEqual(insetBlocks.count, 2)
            XCTAssertGreaterThan(insetBlocks[1].y - insetBlocks[0].y, 20, "safeAreaInset composed blocks must stack vertically rather than collapse")
        }
    }

    func testWelcomeRecentListKeepsConstantWidthOnRemovalAndInsertion() throws {
        try onUIThread {
            let clock = TestClock()
            let prompt = State(wrappedValue: "")
            let host = GTKRenderer.running(clock: clock) {
                HStack(spacing: 0) {
                    if prompt.wrappedValue.isEmpty {
                        VStack(spacing: 0) {
                            ScrollView {
                                LazyVStack(spacing: 8) {
                                    Text("Conv 1").frame(height: 40)
                                    Text("Conv 2").frame(height: 40)
                                }
                            }
                            .id("recentInner")
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.gray)
                        .clipped()
                        .ignoresSafeArea()
                        .transition(.blur.combined(with: .offset(x: -272)))
                        .id("recent")
                    }
                    VStack(spacing: 16) {
                        Text("Header").frame(height: 60)
                        TextEditor(text: Binding(get: { prompt.wrappedValue }, set: { prompt.wrappedValue = $0 }))
                            .background(alignment: .topLeading) {
                                if prompt.wrappedValue.isEmpty {
                                    Text("Placeholder")
                                }
                            }
                            .animation(nil, value: prompt.wrappedValue.isEmpty)
                            .safeAreaPadding(.horizontal, 12)
                            .frame(height: prompt.wrappedValue.isEmpty ? 44 : 128)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 22))
                            .id("editorBox")
                    }
                    .frame(width: prompt.wrappedValue.isEmpty ? 448 : 640)
                    .frame(maxHeight: .infinity)
                    .id("startToday")
                }
                .animation(.snappy, value: prompt.wrappedValue)
                .frame(width: 900, height: 600)
            }
            for _ in 0..<4 { host.step(); host.frame() }
            let recentInitial = try XCTUnwrap(host.view(id: .manual("recent"))).frame.width
            XCTAssertEqual(recentInitial, 452, accuracy: 2)

            prompt.wrappedValue = "h"
            host.runtime.pump.turn()
            host.frame()
            for tick in 1...10 {
                clock.now += 16
                host.frame()
                if let recent = host.view(id: .manual("recent")),
                   let inner = host.view(id: .manual("recentInner")) {
                    XCTAssertEqual(recent.frame.width, recentInitial, accuracy: 2, "removal tick \(tick) recent width shrank")
                    XCTAssertEqual(inner.frame.width, recentInitial, accuracy: 2, "removal tick \(tick) inner width shrank")
                }
            }

            clock.now += 1500
            host.frame()
            XCTAssertNil(host.view(id: .manual("recent")))

            prompt.wrappedValue = ""
            host.runtime.pump.turn()
            host.frame()
            for tick in 1...10 {
                clock.now += 16
                host.frame()
                let recent = try XCTUnwrap(host.view(id: .manual("recent")))
                let inner = try XCTUnwrap(host.view(id: .manual("recentInner")))
                XCTAssertEqual(recent.frame.width, recentInitial, accuracy: 2, "insertion tick \(tick) recent width grew")
                XCTAssertEqual(inner.frame.width, recentInitial, accuracy: 2, "insertion tick \(tick) inner width grew")
            }
        }
    }

    func testWelcomeEditorAndBackgroundDoNotJumpAtEndOfAnimation() throws {
        try onUIThread {
            let clock = TestClock()
            let prompt = State(wrappedValue: "")
            let host = GTKRenderer.running(clock: clock) {
                HStack(spacing: 0) {
                    if prompt.wrappedValue.isEmpty {
                        VStack(spacing: 0) {
                            Text("Recent")
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .transition(.blur.combined(with: .offset(x: -272)))
                        .id("recent")
                    }
                    VStack(spacing: 12) {
                        if prompt.wrappedValue.isEmpty {
                            Color.blue.frame(width: 196, height: 196)
                                .transition(.blur.combined(with: .scale(scale: 0.98)))
                            Text("Where to start").frame(height: 40)
                                .transition(.blur.combined(with: .scale(scale: 0.98)))
                            HStack(spacing: 16) {
                                Text("B1").frame(width: 48, height: 48)
                                Text("B2").frame(width: 48, height: 48)
                            }
                            .transition(.blur.combined(with: .scale(scale: 0.98)))
                        } else {
                            VStack(spacing: 16) {
                                Text("Title A").frame(height: 32)
                                Text("Title B").frame(height: 40)
                            }
                            .padding(.bottom, 32)
                            .transition(.blur.combined(with: .scale(scale: 0.98)))
                        }
                        HStack(alignment: .bottom, spacing: 0) {
                            TextEditor(text: Binding(get: { prompt.wrappedValue }, set: { prompt.wrappedValue = $0 }))
                                .background(alignment: .topLeading) {
                                    if prompt.wrappedValue.isEmpty {
                                        Text("Placeholder")
                                    }
                                }
                                .animation(nil, value: prompt.wrappedValue.isEmpty)
                                .safeAreaPadding(.vertical, 12)
                                .safeAreaPadding(.leading, 12)
                                .frame(height: prompt.wrappedValue.isEmpty ? 44 : 128)
                            Button("Send") {}
                                .frame(width: 44, height: 44)
                        }
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 22))
                        .id("editorBox")
                    }
                    .id("editorVStack")
                    .padding(.horizontal, 48)
                    .frame(width: prompt.wrappedValue.isEmpty ? 448 : 640)
                    .ignoresSafeArea()
                    .id("startTodayInner")
                    .frame(maxHeight: .infinity)
                    .id("startToday")
                }
                .animation(.snappy, value: prompt.wrappedValue)
                .frame(width: 900, height: 600)
            }
            for _ in 0..<4 { host.step(); host.frame() }

            let startTodayChild = try XCTUnwrap(host.runtime.tree.root?.first(id: .manual("startToday"))?.children.first)
            let startTodayInner = try XCTUnwrap(host.view(id: startTodayChild.id))
            let editorVStackNode = try XCTUnwrap(startTodayChild.children.first?.children.first)
            let editorVStack = try XCTUnwrap(host.view(id: editorVStackNode.id))
            let editorBox = try XCTUnwrap(host.view(id: .manual("editorBox")))
            let editorBgNode = try XCTUnwrap(host.runtime.tree.root?.first(id: .manual("editorBox"))?.children.first)
            let editorBg = try XCTUnwrap(host.view(id: editorBgNode.id))
            let textEditor = try XCTUnwrap(host.views(GTKTextEditorView.self).first)

            @MainActor
            func recordFrames() throws -> [(absY: Double, boxH: Double, bgH: Double, teH: Double, moving: Bool)] {
                var samples: [(Double, Double, Double, Double, Bool)] = []
                var settledTicks = 0
                for _ in 0..<250 {
                    let boxH = editorBox.frame.height
                    let bgH = editorBg.frame.height
                    let teH = textEditor.placedFrame.height
                    XCTAssertEqual(bgH, boxH, accuracy: 0.5, "bgH=\(bgH) boxH=\(boxH)")
                    XCTAssertEqual(boxH - teH, 24.0, accuracy: 0.5, "boxH=\(boxH) tePlacedH=\(teH)")
                    samples.append((
                        startTodayInner.frame.y + editorVStack.frame.y + editorBox.frame.y,
                        boxH,
                        bgH,
                        teH,
                        host.runtime.animator.isMoving
                    ))
                    clock.now += 16
                    host.frame()
                    if !host.runtime.animator.isMoving {
                        settledTicks += 1
                        if settledTicks >= 3 {
                            host.step()
                            host.frame()
                            samples.append((
                                startTodayInner.frame.y + editorVStack.frame.y + editorBox.frame.y,
                                editorBox.frame.height,
                                editorBg.frame.height,
                                textEditor.placedFrame.height,
                                host.runtime.animator.isMoving
                            ))
                            break
                        }
                    }
                }
                return samples
            }

            prompt.wrappedValue = "h"
            host.runtime.pump.turn()
            host.frame()
            XCTAssertEqual(editorBox.frame.height, 44.0, accuracy: 0.5)
            XCTAssertEqual(editorBg.frame.height, 44.0, accuracy: 0.5)
            XCTAssertEqual(textEditor.placedFrame.height, 20.0, accuracy: 0.5)
            let typingSamples = try recordFrames()
            let lastType = try XCTUnwrap(typingSamples.last)
            let prevType = typingSamples[max(0, typingSamples.count - 4)]
            XCTAssertFalse(lastType.moving)
            XCTAssertEqual(prevType.absY, lastType.absY, accuracy: 1.0)
            XCTAssertEqual(lastType.boxH, 128.0, accuracy: 1.0)
            XCTAssertEqual(lastType.bgH, 128.0, accuracy: 1.0)
            XCTAssertEqual(lastType.teH, 104.0, accuracy: 1.0)

            prompt.wrappedValue = ""
            host.runtime.pump.turn()
            host.frame()
            XCTAssertEqual(editorBox.frame.height, 128.0, accuracy: 0.5)
            XCTAssertEqual(editorBg.frame.height, 128.0, accuracy: 0.5)
            XCTAssertEqual(textEditor.placedFrame.height, 104.0, accuracy: 0.5)
            let clearSamples = try recordFrames()
            let lastClear = try XCTUnwrap(clearSamples.last)
            let prevClear = clearSamples[max(0, clearSamples.count - 4)]
            XCTAssertFalse(lastClear.moving)
            XCTAssertEqual(prevClear.absY, lastClear.absY, accuracy: 1.0)
            XCTAssertEqual(lastClear.boxH, 44.0, accuracy: 1.0)
            XCTAssertEqual(lastClear.bgH, 44.0, accuracy: 1.0)
            XCTAssertEqual(lastClear.teH, 20.0, accuracy: 1.0)
        }
    }
}

private struct GTKComposedBlocksView: View {
    let lines: [String]
    var body: some View {
        ForEach(lines.indices, id: \.self) { index in
            Text(lines[index]).frame(height: 30).id("block-\(index)")
        }
    }
}
