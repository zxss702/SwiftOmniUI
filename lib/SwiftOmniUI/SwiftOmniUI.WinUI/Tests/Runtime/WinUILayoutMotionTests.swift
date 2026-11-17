// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) @testable import SwiftOmniUICore
@_spi(Host) @testable import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import SwiftOmniUIConformance
import CSwiftOmniUIWinUI
import XCTest

/// A stack's children travel to the places a patch gives them; one that joins fades in, one hidden fades out first.
final class WinUILayoutMotionTests: XCTestCase {
    func testAStackSiblingFollowsTheAnimatedInsertionBeforeItsFinalPosition() throws {
        try onUIThread {
            let clock = TestClock()
            let shown = State(wrappedValue: false)
            let host = WinUIRenderer.running(clock: clock) {
                HStack(spacing: 0) {
                    if shown.wrappedValue { Text("Recent").frame(width: 160, height: 80).transition(.offset(x: -160)) }
                    Text("Editor").frame(width: 400, height: 80).id("editor")
                }.animation(.eased(200, .linear), value: shown.wrappedValue)
            }
            host.frame()
            let editor = try XCTUnwrap(host.view(id: .manual("editor")))
            let before = editor.origin.x
            shown.wrappedValue = true
            host.step(); host.frame()
            XCTAssertEqual(editor.origin.x, before, accuracy: 1)
            clock.now = 100
            host.frame()
            XCTAssertEqual(editor.origin.x, before + 40, accuracy: 2)
            clock.now = 200
            host.frame()
            XCTAssertEqual(editor.origin.x, before + 80, accuracy: 2)
        }
    }

    func testWelcomeEditorSpringSettlesWithoutAnotherLayoutJump() throws {
        try onUIThread {
            let clock = TestClock()
            let words = State(wrappedValue: "")
            let host = WinUIRenderer.running(clock: clock, room: WinUITestHost.wideRoom) {
                HStack(spacing: 0) {
                    if words.wrappedValue.isEmpty {
                        Text("Recent").frame(maxWidth: .infinity, maxHeight: .infinity)
                            .transition(.blur.combined(with: .offset(x: -272)))
                    }
                    VStack(spacing: 12) {
                        if words.wrappedValue.isEmpty {
                            Color.blue.frame(width: 196, height: 196)
                                .transition(.blur.combined(with: .scale(scale: 0.98)))
                            Text("今天从哪里开始？").font(.system(size: 32))
                                .transition(.blur.combined(with: .scale(scale: 0.98)))
                            HStack(spacing: 16) {
                                Button("Folder") {}.frame(width: 48, height: 48)
                                Button("Clone") {}.frame(width: 48, height: 48)
                                Button("New") {}.frame(width: 48, height: 48)
                                Button("Settings") {}.frame(width: 48, height: 48)
                            }.transition(.blur.combined(with: .scale(scale: 0.98)))
                        } else {
                            VStack(spacing: 16) {
                                Text("神衍·智能").font(.system(size: 24))
                                Text("今天干什么？").font(.system(size: 32))
                            }.padding(.bottom, 32)
                                .transition(.blur.combined(with: .scale(scale: 0.98)))
                        }
                        HStack(alignment: .bottom, spacing: 0) {
                            TextEditor(text: words.projectedValue)
                                .scrollContentBackground(.hidden)
                                .background(alignment: .topLeading) {
                                    if words.wrappedValue.isEmpty {
                                        Text("Start a conversation").padding(.top, 1).padding(.leading, 4)
                                    }
                                }
                                .safeAreaPadding(.vertical, 12)
                                .safeAreaPadding(.leading, 12)
                                .frame(height: words.wrappedValue.isEmpty ? 44 : 128)
                            Button("Send") {}.frame(width: 44, height: 44)
                        }
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 22)).id("input")
                    }
                    .padding(.horizontal, 48)
                    .frame(width: words.wrappedValue.isEmpty ? 448 : 640)
                    .ignoresSafeArea()
                    .frame(maxHeight: .infinity)
                }.animation(.snappy, value: words.wrappedValue.isEmpty)
            }
            host.frame()
            let input = try XCTUnwrap(host.view(id: .manual("input")))
            let editor = try XCTUnwrap(host.views(WinUITextEditorView.self).first)
            for _ in 0..<4 { host.step(); host.frame() }
            XCTAssertTrue(swiftomniui_winui_focus(editor.handle, true))
            for (turn, text) in ["hello", "", "again"].enumerated() {
                editor.type(text)
                XCTAssertTrue(swiftomniui_winui_focused(editor.handle), "after text input \(text.debugDescription)")
                host.step()
                XCTAssertTrue(swiftomniui_winui_focused(editor.handle), "after render \(text.debugDescription)")
                var previous = input.origin
                var previousEditor = editor.origin
                var firstUnfocusedSample: Int?
                for sample in 0...90 {
                    clock.now = Double(turn * 1600) + Double(sample) * 1000 / 60
                    host.frame()
                    if sample >= 60 {
                        XCTAssertEqual(input.origin.x, previous.x, accuracy: 0.5)
                        XCTAssertEqual(input.origin.y, previous.y, accuracy: 0.5)
                        XCTAssertEqual(editor.origin.y, previousEditor.y, accuracy: 0.5)
                    }
                    previous = input.origin
                    previousEditor = editor.origin
                    host.step()
                    host.layOut()
                    if firstUnfocusedSample == nil, !swiftomniui_winui_focused(editor.handle) {
                        firstUnfocusedSample = sample
                    }
                    XCTAssertTrue(host.views(WinUITextEditorView.self).first === editor)
                    let settledInput = input.origin
                    let settledEditor = editor.origin
                    host.layOut()
                    XCTAssertEqual(input.origin.x, settledInput.x, accuracy: 0.5)
                    XCTAssertEqual(input.origin.y, settledInput.y, accuracy: 0.5)
                    XCTAssertEqual(editor.origin.x, settledEditor.x, accuracy: 0.5)
                    XCTAssertEqual(editor.origin.y, settledEditor.y, accuracy: 0.5,
                                   "native allocation repeated at sample \(sample), text \(text.debugDescription)")
                }
                XCTAssertEqual(editor.text, text)
                XCTAssertNil(firstUnfocusedSample, "focus survives the structural transition for \(text.debugDescription)")
            }
        }
    }

    func testWelcomeInputKeepsItsPositionAtTheStartOfTheLayoutChange() throws {
        try onUIThread {
            let clock = TestClock()
            let words = State(wrappedValue: "")
            let host = WinUIRenderer.running(clock: clock, room: WinUITestHost.wideRoom) {
                HStack(spacing: 0) {
                    if words.wrappedValue.isEmpty {
                        Text("Recent").frame(maxWidth: .infinity, maxHeight: .infinity)
                            .transition(.opacity.combined(with: .offset(x: -272)))
                            .id("recent")
                    }
                    VStack(spacing: 12) {
                        if words.wrappedValue.isEmpty {
                            Text("Welcome").frame(height: 196).transition(.opacity).id("welcome")
                        } else {
                            Text("Start typing").frame(height: 80).transition(.opacity)
                        }
                        HStack(alignment: .bottom, spacing: 0) {
                            TextEditor(words.projectedValue)
                                .frame(height: words.wrappedValue.isEmpty ? 44 : 128)
                            Button("Send") {}.frame(width: 44, height: 44)
                        }
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 22))
                        .id("input")
                    }
                    .padding(.horizontal, 48)
                    .frame(width: words.wrappedValue.isEmpty ? 448 : 640)
                    .frame(maxHeight: .infinity)
                }
                .animation(.linear(duration: 0.2), value: words.wrappedValue.isEmpty)
            }
            host.frame()
            let input = try XCTUnwrap(host.view(id: .manual("input")))
            let recent = try XCTUnwrap(host.view(id: .manual("recent")))
            let welcome = try XCTUnwrap(host.view(id: .manual("welcome")))
            let welcomeOrigin = welcome.origin
            let departingFrame = recent.placedFrame
            let departingWidth = departingFrame.width
            let before = input.origin
            words.wrappedValue = "a"
            host.step()
            host.frame()
            XCTAssertTrue(host.view(id: .manual("input")) === input)
            XCTAssertEqual(input.origin.x, before.x, accuracy: 1)
            XCTAssertEqual(input.origin.y, before.y, accuracy: 1)
            XCTAssertEqual(recent.placedFrame, departingFrame)
            XCTAssertEqual(recent.placedFrame.width, departingWidth, accuracy: 0.5)
            for time in stride(from: 10.0, through: 90.0, by: 10) {
                clock.now = time
                host.frame()
                XCTAssertEqual(welcome.origin.x, welcomeOrigin.x, accuracy: 1)
                XCTAssertEqual(welcome.origin.y, welcomeOrigin.y, accuracy: 1)
                XCTAssertEqual(recent.placedFrame.width, departingWidth, accuracy: 0.5)
            }
            clock.now = 100
            host.frame()
            let middle = input.origin
            XCTAssertEqual(recent.placedFrame, departingFrame)
            XCTAssertEqual(recent.placedFrame.width, departingWidth, accuracy: 0.5)
            clock.now = 200
            host.frame()
            XCTAssertNotEqual(input.origin, before)
            XCTAssertEqual(middle.x, (before.x + input.origin.x) / 2, accuracy: 2)
            XCTAssertEqual(middle.y, (before.y + input.origin.y) / 2, accuracy: 2)
            let settled = input.origin
            for time in stride(from: 210.0, through: 300.0, by: 10) {
                clock.now = time
                host.step()
                host.frame()
                XCTAssertEqual(input.origin.x, settled.x, accuracy: 1)
                XCTAssertEqual(input.origin.y, settled.y, accuracy: 1)
            }
            words.wrappedValue = ""
            let expandedOrigin = input.origin
            host.step()
            host.frame()
            XCTAssertEqual(input.origin.x, expandedOrigin.x, accuracy: 1)
            XCTAssertEqual(input.origin.y, expandedOrigin.y, accuracy: 1)
            clock.now = 500
            host.frame()
            XCTAssertEqual(input.origin.x, before.x, accuracy: 1)
            XCTAssertEqual(input.origin.y, before.y, accuracy: 1)
            XCTAssertTrue(host.view(id: .manual("input")) === input)
        }
    }

    func testDepartingNestedRecentListKeepsItsLayoutWidth() throws {
        try onUIThread {
            let clock = TestClock()
            let shown = State(wrappedValue: true)
            let host = WinUIRenderer.running(clock: clock, room: WinUITestHost.wideRoom) {
                HStack(spacing: 0) {
                    if shown.wrappedValue {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(0..<3) { index in
                                    Text("Recent \(index)").frame(height: 40)
                                }
                            }
                        }
                        .id("recent")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.blur.combined(with: .offset(x: -272)))
                    }
                    TextEditor("text")
                        .frame(width: 448, height: 128)
                        .id("editor")
                }
                .animation(.linear(duration: 0.2), value: shown.wrappedValue)
            }
            host.frame()
            let recent = try XCTUnwrap(host.view(id: .manual("recent")))
            let before = recent.placedFrame
            shown.wrappedValue = false
            host.step()
            host.frame()
            XCTAssertEqual(recent.placedFrame, before)
            for time in stride(from: 10.0, through: 200.0, by: 10) {
                clock.now = time
                host.frame()
                XCTAssertEqual(recent.placedFrame.width, before.width, accuracy: 0.5)
                XCTAssertEqual(recent.placedFrame.height, before.height, accuracy: 0.5)
            }
        }
    }

    func testAValueGatedColumnReversesFromItsPresentedFrame() throws {
        try onUIThread {
            let clock = TestClock()
            let expanded = State(wrappedValue: false)
            let host = WinUIRenderer.running(clock: clock) {
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
            XCTAssertEqual(column.frame.x, 200, accuracy: 0.5)
            expanded.wrappedValue = true
            host.runtime.pump.turn()
            host.frame()
            clock.now = 100
            host.frame()
            XCTAssertEqual(column.frame.x, 150, accuracy: 1)

            expanded.wrappedValue = false
            host.runtime.pump.turn()
            host.frame()
            XCTAssertEqual(column.frame.x, 150, accuracy: 1, "retargeting must not jump to either endpoint")
            clock.now = 200
            host.frame()
            // Hermite continuation keeps the incoming -0.5 points/ms velocity.
            XCTAssertEqual(column.frame.x, 162.5, accuracy: 1)
            clock.now = 300
            host.frame()
            XCTAssertEqual(column.frame.x, 200, accuracy: 0.5)
            XCTAssertTrue(host.view(id: child.id) === column)
            XCTAssertFalse(host.runtime.animator.isMoving)
        }
    }

    func testAValueGatedColumnMovesWithinItsOuterFrame() throws {
        try onUIThread {
            let clock = TestClock()
            let expanded = State(wrappedValue: false)
            let host = WinUIRenderer.running(clock: clock) {
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

    func testLazyFirstPlacementArrivesAndExplicitReorderTravels() throws {
        try onUIThread {
            let clock = TestClock()
            let order = State(wrappedValue: [0, 1])
            let host = WinUIRenderer.running(clock: clock) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(order.wrappedValue) { number in
                            Text("Row \(number)").frame(height: 40).id("row-\(number)")
                        }
                    }
                }
                .frame(width: 200, height: 120)
            }
            for _ in 0..<12 { host.step(); host.frame() }
            let row = try XCTUnwrap(host.view(id: .manual("row-1")))
            XCTAssertEqual(row.frame.y, 40, accuracy: 0.5)
            XCTAssertFalse(host.runtime.animator.isMoving)

            withAnimation(.eased(200, .linear)) { order.wrappedValue = [1, 0] }
            host.runtime.pump.turn()
            for _ in 0..<12 { host.step(); host.frame() }
            XCTAssertEqual(row.frame.y, 40, accuracy: 0.5, "explicit motion starts from the existing place")
            clock.now = 100
            host.frame()
            XCTAssertEqual(row.frame.y, 20, accuracy: 1)
            clock.now = 200
            host.frame()
            XCTAssertEqual(row.frame.y, 0, accuracy: 0.5)
            XCTAssertTrue(host.view(id: .manual("row-1")) === row)

            order.wrappedValue = [0, 1]
            host.runtime.pump.turn()
            for _ in 0..<12 { host.step(); host.frame() }
            XCTAssertEqual(row.frame.y, 40, accuracy: 0.5)
            XCTAssertFalse(host.runtime.animator.isMoving, "the prior withAnimation must not leak into later writes")
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
            let host = WinUIRenderer.bare(clock: clock)
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
            let host = WinUIRenderer.bare(clock: clock)
            host.apply(Self.stack(["a"]))
            host.layOut()

            host.apply(Self.stack(["a", "b"]))
            host.layOut()
            let joined = try XCTUnwrap(host.view(id: .manual("b")))
            XCTAssertEqual(joined.drawnOpacity, 0, accuracy: 1e-6)

            clock.now = 100
            host.frame()
            XCTAssertEqual(joined.drawnOpacity, 0.5, accuracy: 1e-6)

            clock.now = 200
            host.frame()
            XCTAssertEqual(joined.drawnOpacity, 1, accuracy: 1e-6)
        }
    }

    func testWithLessMotionEveryChildArrives() throws {
        try onUIThread {
            let host = WinUIRenderer.bare(clock: TestClock(), reducesMotion: true)
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
            let host = WinUIRenderer.bare(clock: clock)
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
            XCTAssertEqual(first.drawnOpacity, 0.5, accuracy: 1e-6)
            XCTAssertEqual(second.frame.y, top + 40)

            clock.now = 100
            host.frame()
            XCTAssertFalse(first.isShown, "gone when the fade landed")
            XCTAssertEqual(first.drawnOpacity, 1, accuracy: 1e-6, "at the opacity the tree describes")
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
            let host = WinUIRenderer.bare(clock: clock)
            host.apply(Self.stack(["first", "second"]))
            let first = try XCTUnwrap(host.view(id: .manual("first")))
            host.layOut()

            host.apply(Self.stack(["first", "second"], hidden: ["first"]))
            clock.now = 50
            host.frame()
            host.apply(Self.stack(["first", "second"]))
            XCTAssertEqual(first.drawnOpacity, 0.5, accuracy: 1e-6, "up again from where the fade reached")

            clock.now = 150
            host.frame()
            XCTAssertEqual(first.drawnOpacity, 1, accuracy: 1e-6)
            XCTAssertTrue(first.isShown, "and never gone")
        }
    }

    /// A label whose width travels lays its words out at the width it is bound for: they keep the one line they fit
    /// there, never breaking at the widths its place passes through, and show whole.
    func testALabelsWordsStandAtTheWidthItTravelsTo() throws {
        try onUIThread {
            let clock = TestClock()
            let host = WinUIRenderer.running(clock: clock) { LengtheningPage() }
            let label = try XCTUnwrap(host.views(WinUILabelView.self).first)

            try XCTUnwrap(host.views(WinUIButtonView.self).first).invoke()
            host.runtime.pump.turn()
            host.layOut()
            clock.now += 100
            host.frame()
            let (place, words) = (label.placedFrame, label.laidOutFrame)
            let stack = try XCTUnwrap(host.views(WinUIStackView.self).first)
            let end = stack.pixels(at: [(place.x + words.width - 1, place.y + 1)])

            clock.now += 200
            host.frame()
            let bound = label.laidOutFrame
            XCTAssertLessThan(place.width, bound.width - 1, "its place on its way")
            XCTAssertEqual(words.width, bound.width, accuracy: 0.5, "its words at the width it is bound for")
            XCTAssertEqual(words.height, bound.height, accuracy: 0.5, "on the one line they fit there")
            XCTAssertEqual(end, [0xFFFF_0000], "shown whole, to the end of its box")
        }
    }

    func testComposedForEachInsideFrameBackgroundAndScrollViewDoesNotCollapse() throws {
        onUIThread {
            let clock = TestClock()
            let host = WinUIRenderer.running(clock: clock) {
                ScrollView {
                    ComposedBlocksView(lines: ["First", "Second", "Third"])
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
            XCTAssertEqual(host.views(WinUILabelView.self).count, 3)
            XCTAssertGreaterThan(blocks[1].frame.y - blocks[0].frame.y, 20, "second block must sit below first")
            XCTAssertGreaterThan(blocks[2].frame.y - blocks[1].frame.y, 20, "third block must sit below second")
        }
    }

    func testSafeAreaInsetAndLazyStackKeepComposedAndLayeredBlocksSeparate() throws {
        try onUIThread {
            let clock = TestClock()
            let host = WinUIRenderer.running(clock: clock) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(0..<2, id: \.self) { row in
                            ComposedBlocksView(lines: ["Row \(row) A", "Row \(row) B"])
                                .background { Color.gray }
                                .id("row-\(row)")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .safeAreaInset(edge: .bottom) {
                    ComposedBlocksView(lines: ["Inset 0", "Inset 1"])
                        .background { Color.blue }
                }
                .frame(width: 400, height: 400)
            }
            host.frame()
            let row0View = try XCTUnwrap(host.view(id: .manual("row-0"))?.placedFrame)
            let row1View = try XCTUnwrap(host.view(id: .manual("row-1"))?.placedFrame)
            XCTAssertGreaterThan(row0View.height, 50, "lazy row composed blocks must stack vertically")
            XCTAssertGreaterThan(row1View.y - row0View.y, 50, "second lazy row must sit below first row")
            let insetBar = try XCTUnwrap(host.views(WinUIStackView.self).last)
            XCTAssertGreaterThan(insetBar.placedFrame.height, 50, "safeAreaInset composed blocks must stack vertically rather than collapse")
            let insetBlocks = (insetBar.sourceElement?.children ?? []).compactMap { $0.winUI.view?.placedFrame }
            XCTAssertEqual(insetBlocks.count, 2)
            XCTAssertGreaterThan(insetBlocks[1].y - insetBlocks[0].y, 20, "safeAreaInset composed blocks must stack vertically rather than collapse")
        }
    }

    /// A chat bubble drawn as `DialogueBackgroundView` does - padded content, a GeometryReader background - must
    /// cover the text it holds, wrapped lines included, once the row is realized in a lazy stack.
    func testBubbleBackgroundCoversWrappedTextInLazyRows() throws {
        try onUIThread {
            struct BubbleShape: Shape {
                var size: Size
                func path(in rect: Rect) -> Path {
                    let s = size == .zero ? Size(width: rect.width, height: rect.height) : size
                    let w = s.width
                    let h = s.height
                    var path = Path()
                    path.move(to: Point(x: 16, y: 0))
                    path.addLine(to: Point(x: w - 16, y: 0))
                    path.addCurve(to: Point(x: w, y: 16), control1: Point(x: w - 8, y: 0), control2: Point(x: w, y: 8))
                    path.addLine(to: Point(x: w, y: h - 16))
                    path.addCurve(to: Point(x: w - 16, y: h), control1: Point(x: w, y: h - 8), control2: Point(x: w - 8, y: h))
                    path.addLine(to: Point(x: 16, y: h))
                    path.addCurve(to: Point(x: 0, y: h - 16), control1: Point(x: 8, y: h), control2: Point(x: 0, y: h - 8))
                    path.addLine(to: Point(x: 0, y: 16))
                    path.addCurve(to: Point(x: 16, y: 0), control1: Point(x: 0, y: 8), control2: Point(x: 8, y: 0))
                    path.closeSubpath()
                    return path
                }
            }
            struct BubbleBlock: Equatable {
                let id: Int
                let bounds: Anchor<Rect>
                let layouts: [Text.Layout]
            }
            struct BubbleBlocksKey: PreferenceKey {
                static let defaultValue: [BubbleBlock] = []
                static func reduce(value: inout [BubbleBlock], nextValue: () -> [BubbleBlock]) {
                    value.append(contentsOf: nextValue())
                }
            }
            struct SelectableTextStub: ViewModifier {
                let id: Int
                func body(content: Content) -> some View {
                    content
                        .backgroundPreferenceValue(Text.LayoutKey.self) { layouts in
                            Color.clear.anchorPreference(key: BubbleBlocksKey.self, value: .bounds) { bounds in
                                [BubbleBlock(id: id, bounds: bounds, layouts: layouts)]
                            }
                        }
                }
            }
            struct DialogueBubble<Content: View>: View {
                @ViewBuilder var content: () -> Content
                var body: some View {
                    content()
                        .padding(EdgeInsets(top: 10, leading: 16, bottom: 15, trailing: 16))
                        .background {
                            GeometryReader { geo in
                                BubbleShape(size: geo.size)
                                    .fill(Color.gray)
                            }
                        }
                }
            }
            struct CodeBlockStub: View {
                let id: Int
                let code: String
                var body: some View {
                    Text().spans {
                        TextSpan(code).foregroundStyle(Color.black)
                    }
                        .font(.system(size: 13, design: .monospaced))
                        .lineSpacing(6)
                        .padding(.all, 16)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16))
                        .modifier(SelectableTextStub(id: id))
                        .compositingGroup()
                        .drawingGroup()
                }
            }
            struct MarkdownStub: View {
                let msgId: Int
                let blocks: [(isCode: Bool, text: String)]
                var body: some View {
                    ForEach(blocks.indices, id: \.self) { idx in
                        if blocks[idx].isCode {
                            CodeBlockStub(id: msgId * 10 + idx, code: blocks[idx].text)
                        } else {
                            Text(blocks[idx].text)
                                .modifier(SelectableTextStub(id: msgId * 10 + idx))
                                .compositingGroup()
                                .drawingGroup()
                        }
                    }
                }
            }
            let clock = TestClock()
            let messages: [[(Bool, String)]] = [
                [(false, "欢迎。用户要 3 页，介绍太阳系，中文，就 3 页。")],
                [(false, "我先摆个大纲，你砍：")],
                [(true,
                    "P1 全景 太阳系是什么 + 一张太阳系示意图（太阳→海王星）\nP2 家族 八大行星分三类：类地4 / 巨行星2(木土) / 冰巨星2(天海)，一张表或一行示意图\nP3 边界 柯伊伯带·日球层·奥尔特云 + 人类已飞到哪(旅行者1号)"
                )],
                [(false, "分工：文案+数据我定稿，配图我用 generate_image 出（你告诉我每页要什么图、几比几、放哪）；版式、代码、导出 pptx 归你。")],
            ]
            let shownCount = State(wrappedValue: messages.count)
            let widthState = State(wrappedValue: 500.0)
            let host = WinUIRenderer.running(clock: clock, room: LayoutSize(width: 1024, height: 700)) {
                HStack(spacing: 0) {
                    Text("Left").frame(maxWidth: .infinity, maxHeight: .infinity)
                    ScrollView {
                        LazyVStack(alignment: .leading) {
                            ForEach(0..<shownCount.wrappedValue, id: \.self) { index in
                                DialogueBubble {
                                    MarkdownStub(msgId: index, blocks: messages[index])
                                        .lineLimit(nil)
                                }
                                .padding(.leading, 32)
                                .overlay(alignment: .bottomLeading) {
                                    Circle().fill(Color.pink).frame(width: 32, height: 32)
                                }
                                .padding(.trailing, 24)
                                .transition(.blur.combined(with: .offset(x: -48, y: 80)))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .coordinateSpace(name: "ChatSel")
                        .backgroundPreferenceValue(BubbleBlocksKey.self) { _ in Color.clear }
                        .padding(8)
                    }
                    .animation(.snappy, value: shownCount.wrappedValue)
                    .animation(.snappy, value: widthState.wrappedValue)
                    .frame(width: widthState.wrappedValue)
                }
            }
            for _ in 0..<25 { clock.now += 16; host.step(); host.frame() }
            widthState.wrappedValue = 280.0
            for _ in 0..<45 { clock.now += 16; host.step(); host.frame() }
            host.settle {
                let ps = host.views(WinUIPathView.self).filter { $0.drawsInk }
                return ps.count == messages.count && ps.allSatisfy { $0.laidOutFrame.height > 10 }
            }
            let labels = host.views(WinUILabelView.self).filter { $0.text != "Left" }
            let paths = host.views(WinUIPathView.self).filter { $0.drawsInk }
            XCTAssertEqual(labels.count, messages.count)
            for index in messages.indices {
                let text = try XCTUnwrap(labels.first { $0.text == messages[index][0].1 }, "text \(index)")
                let (t, textSize) = (text.origin, text.laidOutFrame)
                let extraPad = messages[index][0].0 ? 16.0 : 0.0
                let bubble = try XCTUnwrap(paths.first { abs($0.origin.y - (t.y - 10 - extraPad)) < 20 && $0.laidOutFrame.width > 40 && $0.laidOutFrame.width > textSize.width + 20 }, "bubble \(index)")
                let (b, backgroundSize) = (bubble.origin, bubble.laidOutFrame)
                let message = "row \(index): text at \(t) \(textSize.width)x\(textSize.height), background at \(b) \(backgroundSize.width)x\(backgroundSize.height)"
                XCTAssertEqual(b.y, t.y - 10 - extraPad, accuracy: 2, message)
                XCTAssertEqual(b.y + backgroundSize.height, t.y + textSize.height + 15 + extraPad, accuracy: 2, message)
                XCTAssertEqual(b.x, t.x - 16 - extraPad, accuracy: 2, message)
                XCTAssertEqual(b.x + backgroundSize.width, t.x + textSize.width + 16 + extraPad, accuracy: 2, message)
                let bottomSample = bubble.pixels(at: [(backgroundSize.width / 2, max(2, backgroundSize.height - 6))])
                XCTAssertNotEqual(bottomSample[0] >> 24, 0, "rendered path must cover bottom of bubble for \(message), sample=\(bottomSample)")
            }
        }
    }

    func testWelcomeRecentListKeepsConstantWidthOnRemovalAndInsertion() throws {
        try onUIThread {
            let clock = TestClock()
            let prompt = State(wrappedValue: "")
            let host = WinUIRenderer.running(clock: clock) {
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
            let recentBefore = try XCTUnwrap(host.view(id: .manual("recent")))
            let recentInnerBefore = try XCTUnwrap(host.view(id: .manual("recentInner")))
            let startToday = try XCTUnwrap(host.view(id: .manual("startToday")))
            XCTAssertEqual(recentBefore.frame.width, 452, accuracy: 0.5)
            XCTAssertEqual(recentInnerBefore.frame.width, 452, accuracy: 0.5)

            // Type first character -> removal of recentList
            prompt.wrappedValue = "h"
            host.runtime.pump.turn()
            host.frame()
            var removalTrace: [String] = []
            for tick in 1...40 {
                clock.now += 16
                host.frame()
                removalTrace.append("t\(tick):w=\(recentBefore.frame.width)/in=\(recentInnerBefore.frame.width)/st=\(startToday.frame.x),\(startToday.frame.width)")
                if recentBefore.isShown {
                    XCTAssertEqual(recentBefore.frame.width, 452, accuracy: 0.5, "removal tick \(tick): \(removalTrace)")
                    XCTAssertEqual(recentInnerBefore.frame.width, 452, accuracy: 0.5, "removal inner tick \(tick): \(removalTrace)")
                }
                if !host.runtime.animator.isMoving { break }
            }
            for _ in 0..<3 { clock.now += 16; host.frame() }

            // Clear prompt -> insertion of recentList
            prompt.wrappedValue = ""
            host.runtime.pump.turn()
            host.frame()
            let recentIn = try XCTUnwrap(host.view(id: .manual("recent")))
            let recentInnerIn = try XCTUnwrap(host.view(id: .manual("recentInner")))
            var insertionTrace: [String] = []
            for tick in 0...40 {
                insertionTrace.append("t\(tick):w=\(recentIn.frame.width)/in=\(recentInnerIn.frame.width)/st=\(startToday.frame.x),\(startToday.frame.width)")
                XCTAssertEqual(recentIn.frame.width, 452, accuracy: 0.5, "insertion tick \(tick): \(insertionTrace)")
                XCTAssertEqual(recentInnerIn.frame.width, 452, accuracy: 0.5, "insertion inner tick \(tick): \(insertionTrace)")
                if !host.runtime.animator.isMoving { break }
                clock.now += 16
                host.frame()
            }
            XCTAssertEqual(startToday.frame.width, 448, accuracy: 0.5)
        }
    }

    func testWelcomeEditorAndBackgroundDoNotJumpAtEndOfAnimation() throws {
        try onUIThread {
            let clock = TestClock()
            let prompt = State(wrappedValue: "")
            let onDrop = State(wrappedValue: false)
            let host = WinUIRenderer.running(clock: clock) {
                HStack(spacing: 0) {
                    if prompt.wrappedValue.isEmpty, !onDrop.wrappedValue {
                        VStack(spacing: 0) {
                            Text("Recent")
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .transition(.blur.combined(with: .offset(x: -272)))
                        .id("recent")
                    }
                    VStack(spacing: 12) {
                        if prompt.wrappedValue.isEmpty, !onDrop.wrappedValue {
                            Color.blue.frame(width: 196, height: 196)
                                .transition(.blur.combined(with: .scale(scale: 0.98)))
                            Text("今天从哪里开始？").font(.system(size: 32))
                                .transition(.blur.combined(with: .scale(scale: 0.98)))
                            HStack(spacing: 16) {
                                Text("B1").frame(width: 48, height: 48)
                                Text("B2").frame(width: 48, height: 48)
                            }
                            .transition(.blur.combined(with: .scale(scale: 0.98)))
                        } else {
                            VStack(spacing: 16) {
                                Text("Title A").font(.system(size: 24))
                                Text("Title B").font(.system(size: 32))
                            }
                            .padding(.bottom, 32)
                            .transition(.blur.combined(with: .scale(scale: 0.98)))
                        }
                        HStack(alignment: .bottom, spacing: 0) {
                            if onDrop.wrappedValue {
                                Text("Drop").frame(height: 128).frame(maxWidth: .infinity)
                            } else {
                                TextEditor(text: Binding(get: { prompt.wrappedValue }, set: { prompt.wrappedValue = $0 }))
                                    .scrollContentBackground(.hidden)
                                    .background(alignment: .topLeading) {
                                        if prompt.wrappedValue.isEmpty {
                                            Text("Placeholder").padding(.top, 1).padding(.leading, 4)
                                        }
                                    }
                                    .animation(nil, value: prompt.wrappedValue.isEmpty)
                                    .safeAreaPadding(.vertical, 12)
                                    .safeAreaPadding(.leading, 12)
                                    .frame(height: !prompt.wrappedValue.isEmpty ? 128 : 44)
                                Button("Send") {}
                                    .frame(width: 44, height: 44)
                            }
                        }
                        .animation(nil, value: onDrop.wrappedValue)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 22))
                        .id("editorBox")
                    }
                    .id("editorVStack")
                    .padding(.horizontal, 48)
                    .frame(width: prompt.wrappedValue.isEmpty && !onDrop.wrappedValue ? 448 : 640)
                    .ignoresSafeArea()
                    .id("startTodayInner")
                    .frame(maxHeight: .infinity)
                    .id("startToday")
                }
                .animation(.snappy, value: prompt.wrappedValue)
                .animation(.snappy, value: onDrop.wrappedValue)
                .frame(width: 720, height: 416)
            }
            for _ in 0..<4 { host.step(); host.layOut(); host.frame() }

            let startTodayChild = try XCTUnwrap(host.runtime.tree.root?.first(id: .manual("startToday"))?.children.first)
            let startTodayInner = try XCTUnwrap(host.view(id: startTodayChild.id))
            let editorVStackNode = try XCTUnwrap(startTodayChild.children.first?.children.first)
            let editorVStack = try XCTUnwrap(host.view(id: editorVStackNode.id))
            let editorBox = try XCTUnwrap(host.view(id: .manual("editorBox")))
            let editorBg = try XCTUnwrap(host.views(WinUIPathView.self).last)
            let textEditor = try XCTUnwrap(host.views(WinUITextEditorView.self).first)

            struct Sample: CustomStringConvertible {
                let tick: Int
                let absY: Double
                let boxOriginY: Double
                let bgOriginY: Double
                let teOriginY: Double
                let ctrlY: Double
                let boxH: Double
                let bgH: Double
                let teH: Double
                let moving: Bool
                var description: String {
                    "t=\(tick)(m=\(moving),box=\(Int(boxOriginY)),bg=\(Int(bgOriginY)),te=\(Int(teOriginY)),ctrlY=\(Int(ctrlY)),boxH=\(Int(boxH)),bgH=\(Int(bgH)),teH=\(Int(teH)))"
                }
            }

            @MainActor
            func recordFrames() -> [Sample] {
                var samples: [Sample] = []
                var settledTicks = 0
                for tick in 0..<250 {
                    samples.append(Sample(
                        tick: tick,
                        absY: startTodayInner.frame.y + editorVStack.frame.y + editorBox.frame.y,
                        boxOriginY: editorBox.origin.y,
                        bgOriginY: editorBg.origin.y,
                        teOriginY: textEditor.origin.y,
                        ctrlY: textEditor.controlFrame.y,
                        boxH: editorBox.frame.height,
                        bgH: editorBg.frame.height,
                        teH: textEditor.frame.height,
                        moving: host.runtime.animator.isMoving
                    ))
                    clock.now += 16
                    host.frame()
                    host.layOut()
                    WinUITestHost.pump(0.002)
                    if !host.runtime.animator.isMoving {
                        settledTicks += 1
                        if settledTicks >= 5 {
                            host.step()
                            host.frame()
                            host.layOut()
                            WinUITestHost.pump(0.01)
                            samples.append(Sample(
                                tick: tick + 1,
                                absY: startTodayInner.frame.y + editorVStack.frame.y + editorBox.frame.y,
                                boxOriginY: editorBox.origin.y,
                                bgOriginY: editorBg.origin.y,
                                teOriginY: textEditor.origin.y,
                                ctrlY: textEditor.controlFrame.y,
                                boxH: editorBox.frame.height,
                                bgH: editorBg.frame.height,
                                teH: textEditor.frame.height,
                                moving: host.runtime.animator.isMoving
                            ))
                            break
                        }
                    }
                }
                return samples
            }

            func assertNoEndJump(_ samples: [Sample], label: String) throws {
                let last = try XCTUnwrap(samples.last)
                XCTAssertFalse(last.moving, "\(label) must settle")
                let tail = Array(samples.suffix(15))
                for (a, b) in zip(tail, tail.dropFirst()) {
                    XCTAssertLessThanOrEqual(abs(b.boxOriginY - a.boxOriginY), 2.0, "\(label) boxOriginY step jump \(a) -> \(b)")
                    XCTAssertLessThanOrEqual(abs(b.bgOriginY - a.bgOriginY), 2.0, "\(label) bgOriginY step jump \(a) -> \(b)")
                    XCTAssertLessThanOrEqual(abs(b.teOriginY - a.teOriginY), 2.0, "\(label) teOriginY step jump \(a) -> \(b)")
                    XCTAssertLessThanOrEqual(abs(b.ctrlY - a.ctrlY), 2.0, "\(label) ctrlY step jump \(a) -> \(b)")
                    XCTAssertLessThanOrEqual(abs(b.teH - a.teH), 2.0, "\(label) teH step jump \(a) -> \(b)")
                }
                XCTAssertEqual(last.boxH, last.bgH, accuracy: 0.5)
            }

            // Typing via native editor control: "" -> "h"
            textEditor.type("h")
            host.step()
            host.frame()
            try assertNoEndJump(recordFrames(), label: "type h")

            // Clearing via native editor control: "h" -> ""
            textEditor.type("")
            host.step()
            host.frame()
            try assertNoEndJump(recordFrames(), label: "clear")
        }
    }

    func testChatTextEditorViewTransactionExpansionDoesNotJump() throws {
        try onUIThread {
            let clock = TestClock()
            let text = State(wrappedValue: "")
            let host = WinUIRenderer.running(clock: clock, room: LayoutSize(width: 480, height: 600)) {
                VStack(spacing: 0) {
                    Color.blue.frame(maxWidth: .infinity, maxHeight: .infinity)
                    ZStack(alignment: .bottom) {
                        HStack(alignment: .bottom, spacing: 8) {
                            TextEditor(text: text.projectedValue.transaction(.init(animation: .snappy)))
                                .scrollContentBackground(.hidden)
                                .background(alignment: .topLeading) {
                                    if text.wrappedValue.isEmpty {
                                        Text("输入消息")
                                            .allowsHitTesting(false)
                                            .padding(.leading, 4)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .animation(nil, value: text.wrappedValue.isEmpty)
                                .safeAreaPadding(.vertical, 12)
                                .safeAreaPadding(.leading, 12)
                                .frame(height: text.wrappedValue.isEmpty ? 40 : 128)
                                .background(Color.black, in: RoundedRectangle(cornerRadius: 20))
                                .id("chat-editor-bg")
                            Button {} label: { Circle().frame(width: 40, height: 40) }.id("send-btn")
                        }
                    }
                    .padding(12)
                }
            }
            host.layOut()
            WinUITestHost.pump(0.002)
            let editor = try XCTUnwrap(host.views(WinUITextEditorView.self).first)
            let bg = try XCTUnwrap(host.view(id: .manual("chat-editor-bg")))
            let bgShapeNode = try XCTUnwrap(host.runtime.tree.root?.first(id: .manual("chat-editor-bg"))?.children.first)
            let bgShape = try XCTUnwrap(host.view(id: bgShapeNode.id))
            XCTAssertTrue(swiftomniui_winui_focus(editor.handle, true))

            struct Step {
                let tick: Int
                let bgY: Double
                let bgH: Double
                let shapeH: Double
                let edY: Double
                let edH: Double
                let ctrlY: Double
                let ctrlH: Double
            }
            @MainActor func capture(_ label: String, expectedBgH: Double, expectedEdH: Double) throws {
                var rows: [Step] = []
                var settled = 0
                for tick in 0..<120 {
                    clock.now += 16
                    host.frame()
                    host.layOut()
                    WinUITestHost.pump(0.002)
                    let row = Step(
                        tick: tick,
                        bgY: bg.origin.y, bgH: bg.frame.height,
                        shapeH: bgShape.frame.height,
                        edY: editor.origin.y, edH: editor.frame.height,
                        ctrlY: editor.controlFrame.y, ctrlH: editor.controlFrame.height)
                    rows.append(row)
                    if !host.frameClock.held { settled += 1 } else { settled = 0 }
                    if settled >= 10 { break }
                }
                XCTAssertFalse(host.frameClock.held, "\(label) chat animation did not settle")
                for row in rows {
                    XCTAssertEqual(row.edY - row.bgY, 12.0, accuracy: 0.5, "\(label) edY lost top padding: \(row)")
                    XCTAssertEqual(row.bgH - row.edH, 24.0, accuracy: 1.5, "\(label) edH decoupled from bgH: \(row)")
                    XCTAssertEqual(row.shapeH, row.bgH, accuracy: 1.0, "\(label) background shape snapped out of sync with bgH: \(row)")
                    XCTAssertEqual(row.ctrlH, row.edH, accuracy: 2.0, "\(label) controlHeight decoupled from edH: \(row)")
                    XCTAssertLessThanOrEqual(abs(row.ctrlY), 0.5, "\(label) ctrlY jumped: \(row)")
                }
                for (a, b) in zip(rows, rows.dropFirst()) {
                    XCTAssertLessThanOrEqual(abs(b.bgY - a.bgY), 10.0, "\(label) chat bgY stepped too far: \(a) -> \(b)")
                    XCTAssertLessThanOrEqual(abs(b.edY - a.edY), 10.0, "\(label) chat edY stepped too far: \(a) -> \(b)")
                    XCTAssertLessThanOrEqual(abs(b.edH - a.edH), 10.0, "\(label) chat edH stepped too far: \(a) -> \(b)")
                    XCTAssertLessThanOrEqual(abs(b.ctrlH - a.ctrlH), 10.0, "\(label) chat ctrlH stepped too far: \(a) -> \(b)")
                }
                let last = try XCTUnwrap(rows.last)
                XCTAssertEqual(last.bgH, expectedBgH, accuracy: 0.5, "\(label) chat bgH did not settle at \(expectedBgH)")
                XCTAssertEqual(last.shapeH, expectedBgH, accuracy: 0.5, "\(label) chat shapeH did not settle at \(expectedBgH)")
                XCTAssertEqual(last.edH, expectedEdH, accuracy: 0.5, "\(label) chat edH did not settle at \(expectedEdH)")
                XCTAssertEqual(last.ctrlH, expectedEdH, accuracy: 0.5, "\(label) chat ctrlH did not settle at \(expectedEdH)")
                for (a, b) in zip(rows.suffix(10), rows.suffix(10).dropFirst()) {
                    XCTAssertLessThanOrEqual(abs(b.bgY - a.bgY), 0.5, "\(label) chat bgY jumped after settle: \(a) -> \(b)")
                    XCTAssertLessThanOrEqual(abs(b.edY - a.edY), 0.5, "\(label) chat edY jumped after settle: \(a) -> \(b)")
                }
            }

            let initialBgY = bg.origin.y
            let initialEdY = editor.origin.y
            editor.type("h")
            host.step()
            host.frame()
            host.layOut()
            WinUITestHost.pump(0.002)
            XCTAssertEqual(bg.origin.y, initialBgY, accuracy: 0.5, "type h frame-0 bgY snapped")
            XCTAssertEqual(bg.frame.height, 40.0, accuracy: 0.5, "type h frame-0 bgH snapped")
            XCTAssertEqual(bgShape.frame.height, 40.0, accuracy: 0.5, "type h frame-0 shapeH snapped")
            XCTAssertEqual(editor.origin.y, initialEdY, accuracy: 0.5, "type h frame-0 edY snapped")
            XCTAssertEqual(editor.frame.height, 16.0, accuracy: 0.5, "type h frame-0 edH snapped")
            XCTAssertEqual(editor.controlFrame.height, 16.0, accuracy: 0.5, "type h frame-0 ctrlH snapped")
            try capture("type h", expectedBgH: 128, expectedEdH: 104)

            editor.type("he")
            host.step()
            host.frame()
            try capture("type he", expectedBgH: 128, expectedEdH: 104)

            let expandedBgY = bg.origin.y
            let expandedEdY = editor.origin.y
            editor.type("")
            host.step()
            host.frame()
            host.layOut()
            WinUITestHost.pump(0.002)
            XCTAssertEqual(bg.origin.y, expandedBgY, accuracy: 0.5, "clear frame-0 bgY snapped")
            XCTAssertEqual(bg.frame.height, 128.0, accuracy: 0.5, "clear frame-0 bgH snapped")
            XCTAssertEqual(bgShape.frame.height, 128.0, accuracy: 0.5, "clear frame-0 shapeH snapped")
            XCTAssertEqual(editor.origin.y, expandedEdY, accuracy: 0.5, "clear frame-0 edY snapped")
            XCTAssertEqual(editor.frame.height, 104.0, accuracy: 0.5, "clear frame-0 edH snapped")
            XCTAssertEqual(editor.controlFrame.height, 104.0, accuracy: 0.5, "clear frame-0 ctrlH snapped")
            try capture("clear", expectedBgH: 40, expectedEdH: 16)
        }
    }

    func testWelcomeWindowFocusedTypingDoesNotJump() throws {
        try onUIThread {
            let clock = TestClock()
            let host = WinUIRenderer.running(clock: clock, application: {
                WelcomeWindowTestApp()
            })
            host.layOut()
            WinUITestHost.pump(0.02)

            let textEditor = try XCTUnwrap(host.views(WinUITextEditorView.self).first)
            let editorBox = try XCTUnwrap(host.view(id: .manual("win-editor-box")))
            let boxBgNode = try XCTUnwrap(host.runtime.tree.root?.first(id: .manual("win-editor-box"))?.children.first)
            let boxBg = try XCTUnwrap(host.view(id: boxBgNode.id))
            let sendBtn = try XCTUnwrap(host.view(id: .manual("win-send-btn")))
            XCTAssertTrue(swiftomniui_winui_focus(textEditor.handle, true))

            struct Frame {
                let tick: Int
                let active: Bool
                let boxY: Double
                let boxH: Double
                let bgH: Double
                let teY: Double
                let teH: Double
                let ctrlY: Double
                let ctrlH: Double
                let btnY: Double
            }
            @MainActor func capture(_ label: String, expectedBoxH: Double, expectedTeH: Double) throws -> [Frame] {
                var frames: [Frame] = []
                var settled = 0
                for tick in 0..<120 {
                    clock.now += 16
                    host.frame()
                    host.layOut()
                    WinUITestHost.pump(0.002)
                    frames.append(Frame(
                        tick: tick, active: host.frameClock.held,
                        boxY: editorBox.origin.y, boxH: editorBox.frame.height,
                        bgH: boxBg.frame.height,
                        teY: textEditor.origin.y, teH: textEditor.frame.height,
                        ctrlY: textEditor.controlFrame.y, ctrlH: textEditor.controlFrame.height,
                        btnY: sendBtn.origin.y))
                    if !host.frameClock.held { settled += 1 } else { settled = 0 }
                    if settled >= 10 { break }
                }
                XCTAssertFalse(host.frameClock.held, "\(label) animation did not settle")
                for f in frames {
                    XCTAssertEqual(f.teY - f.boxY, 12.0, accuracy: 0.5, "\(label) teY lost top padding: \(f)")
                    XCTAssertEqual(f.boxH - f.teH, 24.0, accuracy: 1.5, "\(label) teH decoupled from boxH: \(f)")
                    XCTAssertEqual(f.bgH, f.boxH, accuracy: 1.0, "\(label) background shape snapped out of sync with boxH: \(f)")
                    XCTAssertEqual(f.ctrlH, f.teH, accuracy: 2.0, "\(label) ctrlH decoupled from teH: \(f)")
                    XCTAssertLessThanOrEqual(abs(f.ctrlY), 0.5, "\(label) ctrlY jumped: \(f)")
                }
                for (a, b) in zip(frames, frames.dropFirst()) {
                    XCTAssertLessThanOrEqual(abs(b.boxH - a.boxH), 10.0, "\(label) boxH stepped too far: \(a) -> \(b)")
                    XCTAssertLessThanOrEqual(abs(b.teH - a.teH), 10.0, "\(label) teH stepped too far: \(a) -> \(b)")
                    XCTAssertLessThanOrEqual(abs(b.ctrlH - a.ctrlH), 10.0, "\(label) ctrlH stepped too far: \(a) -> \(b)")
                    XCTAssertLessThanOrEqual(abs(b.btnY - a.btnY), 5.0, "\(label) btnY stepped too far: \(a) -> \(b)")
                }
                let last = try XCTUnwrap(frames.last)
                XCTAssertEqual(last.boxH, expectedBoxH, accuracy: 0.5, "\(label) boxH did not settle at \(expectedBoxH)")
                XCTAssertEqual(last.bgH, expectedBoxH, accuracy: 0.5, "\(label) bgH did not settle at \(expectedBoxH)")
                XCTAssertEqual(last.teH, expectedTeH, accuracy: 0.5, "\(label) teH did not settle at \(expectedTeH)")
                XCTAssertEqual(last.ctrlH, expectedTeH, accuracy: 0.5, "\(label) ctrlH did not settle at \(expectedTeH)")
                for (a, b) in zip(frames.suffix(10), frames.suffix(10).dropFirst()) {
                    XCTAssertLessThanOrEqual(abs(b.boxY - a.boxY), 0.5, "\(label) boxY settle jump \(a) -> \(b)")
                    XCTAssertLessThanOrEqual(abs(b.teY - a.teY), 0.5, "\(label) teY settle jump \(a) -> \(b)")
                    XCTAssertLessThanOrEqual(abs(b.ctrlY - a.ctrlY), 0.5, "\(label) ctrlY settle jump \(a) -> \(b)")
                    XCTAssertLessThanOrEqual(abs(b.btnY - a.btnY), 0.5, "\(label) btnY settle jump \(a) -> \(b)")
                }
                return frames
            }

            let initialBoxY = editorBox.origin.y
            let initialTeY = textEditor.origin.y
            let initialBtnY = sendBtn.origin.y
            textEditor.type("h")
            host.step()
            host.frame()
            host.layOut()
            WinUITestHost.pump(0.002)
            XCTAssertEqual(editorBox.origin.y, initialBoxY, accuracy: 0.5, "type h frame-0 boxY snapped")
            XCTAssertEqual(editorBox.frame.height, 44.0, accuracy: 0.5, "type h frame-0 boxH snapped")
            XCTAssertEqual(boxBg.frame.height, 44.0, accuracy: 0.5, "type h frame-0 bgH snapped")
            XCTAssertEqual(textEditor.origin.y, initialTeY, accuracy: 0.5, "type h frame-0 teY snapped")
            XCTAssertEqual(textEditor.frame.height, 20.0, accuracy: 0.5, "type h frame-0 teH snapped")
            XCTAssertEqual(textEditor.controlFrame.height, 20.0, accuracy: 0.5, "type h frame-0 ctrlH snapped")
            XCTAssertEqual(sendBtn.origin.y, initialBtnY, accuracy: 0.5, "type h frame-0 btnY snapped")
            _ = try capture("type h", expectedBoxH: 128, expectedTeH: 104)

            textEditor.type("he")
            host.step()
            host.frame()
            _ = try capture("type he", expectedBoxH: 128, expectedTeH: 104)

            let expandedBoxY = editorBox.origin.y
            let expandedTeY = textEditor.origin.y
            let expandedBtnY = sendBtn.origin.y
            textEditor.type("")
            host.step()
            host.frame()
            host.layOut()
            WinUITestHost.pump(0.002)
            XCTAssertEqual(editorBox.origin.y, expandedBoxY, accuracy: 0.5, "clear frame-0 boxY snapped")
            XCTAssertEqual(editorBox.frame.height, 128.0, accuracy: 0.5, "clear frame-0 boxH snapped")
            XCTAssertEqual(boxBg.frame.height, 128.0, accuracy: 0.5, "clear frame-0 bgH snapped")
            XCTAssertEqual(textEditor.origin.y, expandedTeY, accuracy: 0.5, "clear frame-0 teY snapped")
            XCTAssertEqual(textEditor.frame.height, 104.0, accuracy: 0.5, "clear frame-0 teH snapped")
            XCTAssertEqual(textEditor.controlFrame.height, 104.0, accuracy: 0.5, "clear frame-0 ctrlH snapped")
            XCTAssertEqual(sendBtn.origin.y, expandedBtnY, accuracy: 0.5, "clear frame-0 btnY snapped")
            _ = try capture("clear", expectedBoxH: 44, expectedTeH: 20)
        }
    }
}

private struct WelcomeWindowTestApp: App {
    init() {}
    var body: some Scene {
        Window("欢迎页", id: "welcome.test") {
            WelcomeWindowContentView()
                .frame(width: 720, height: 416)
        }
        .windowResizability(.contentSize)
    }
}

private struct WelcomeWindowContentView: View {
    @State private var prompt = ""
    @State private var onDrop = false
    var body: some View {
        HStack(spacing: 0) {
            if prompt.isEmpty, !onDrop {
                VStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { i in
                        VStack(alignment: .leading) {
                            Text("Title \(i)")
                            Text("/path/\(i)")
                        }.frame(maxWidth: .infinity).frame(height: 48)
                    }
                }
                .frame(width: 272)
                .frame(maxHeight: .infinity)
                .transition(.blur.combined(with: .offset(x: -272)))
            }
            VStack(spacing: 12) {
                if prompt.isEmpty, !onDrop {
                    Color.blue.frame(width: 96, height: 96)
                    Text("今天从哪里开始？")
                    HStack(spacing: 8) {
                        ForEach(0..<4, id: \.self) { _ in
                            Button {} label: { Circle().frame(width: 48, height: 48) }
                        }
                    }
                } else {
                    VStack(spacing: 16) {
                        Color.blue.frame(width: 48, height: 48)
                        Text("新对话")
                    }.padding(.bottom, 32)
                }
                HStack(alignment: .bottom, spacing: 0) {
                    TextEditor(text: $prompt)
                        .scrollContentBackground(.hidden)
                        .background(alignment: .topLeading) {
                            if prompt.isEmpty, !onDrop {
                                Text("不指定文件夹开始对话")
                                    .allowsHitTesting(false)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .animation(nil, value: prompt.isEmpty)
                        .safeAreaPadding(.vertical, 12)
                        .safeAreaPadding(.leading, 12)
                        .frame(height: !prompt.isEmpty ? 128 : 44)
                    Button {} label: {
                        Circle().frame(width: 28, height: 28).padding(8)
                    }.buttonStyle(.plain).id("win-send-btn")
                }
                .animation(nil, value: onDrop)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 22))
                .id("win-editor-box")
            }
            .padding(.horizontal, 48)
            .frame(width: prompt.isEmpty && !onDrop ? 448 : 640)
            .buttonStyle(.plain)
            .ignoresSafeArea()
            .frame(maxHeight: .infinity)
        }
        .animation(.snappy, value: prompt)
        .animation(.snappy, value: onDrop)
        .frame(maxHeight: .infinity)
        .toolbarVisibility(.hidden, for: .windowToolbar)
        .toolbarBackground(.hidden, for: .windowToolbar)
    }
}

private struct ComposedBlocksView: View {
    let lines: [String]
    var body: some View {
        ForEach(lines.indices, id: \.self) { index in
            Text(lines[index]).frame(height: 30).id("block-\(index)")
        }
    }
}

/// A label on red lengthened by a button, in a stack whose children travel for 200 ms.
private struct LengtheningPage: View {
    @State private var long = false

    var body: some View {
        VStack {
            Text(long ? "Text & typing" : "Text").background(Color("#FF0000")).horizontalAlignment(.start)
            Button("Longer").onClicked { long = true }
        }
        .animation(.eased(200, .linear))
        .horizontalAlignment(.fill)
        .frame(width: 300)
        .horizontalAlignment(.start)
        .verticalAlignment(.start)
    }
}
