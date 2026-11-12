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
    func testLazyStackKeepsFlattenedBodyRowsInSeparateVerticalSlots() throws {
        try onUIThread {
            let host = WinUIRenderer.running(room: WinUITestHost.wideRoom) {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(0..<3) { index in
                            Text("message \(index)").id("message-\(index)")
                                .padding(16)
                                .background { GeometryReader { _ in Color.white } }
                                .padding(.leading, 32)
                                .overlay(alignment: .bottomLeading) { Color.blue.frame(width: 32, height: 32) }
                                .padding(.trailing, 24)
                        }
                    }
                }
            }
            host.frame()
            let labels = try (0..<3).map { try XCTUnwrap(host.view(id: .manual("message-\($0)"))) }
            for index in 0..<2 {
                XCTAssertLessThan(labels[index].origin.y + labels[index].laidOutFrame.height,
                                  labels[index + 1].origin.y,
                                  "frames \(labels.map { ($0.origin.y, $0.laidOutFrame.height) })")
            }
        }
    }

    func testLazyStackKeepsDirectLayeredBodyMessagesInSeparateSlots() throws {
        try onUIThread {
            let host = WinUIRenderer.running(room: WinUITestHost.wideRoom) {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        Text("one").padding(16).background { GeometryReader { _ in Color.white } }
                        Text("two").padding(16).background { GeometryReader { _ in Color.white } }
                        Text("three").padding(16).background { GeometryReader { _ in Color.white } }
                    }
                }
            }
            host.frame()
            let texts = host.views(WinUITextView.self)
            XCTAssertGreaterThanOrEqual(texts.count, 3)
            for index in 0..<2 {
                XCTAssertLessThan(texts[index].origin.y + texts[index].laidOutFrame.height,
                                  texts[index + 1].origin.y,
                                  "frames \(texts.map { ($0.origin.y, $0.laidOutFrame.height) })")
            }
        }
    }

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
                            Text("Actions").frame(height: 48)
                                .transition(.blur.combined(with: .scale(scale: 0.98)))
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
            let before = input.origin
            words.wrappedValue = "a"
            host.step()
            host.frame()
            XCTAssertTrue(host.view(id: .manual("input")) === input)
            XCTAssertEqual(input.origin.x, before.x, accuracy: 1)
            XCTAssertEqual(input.origin.y, before.y, accuracy: 1)
            XCTAssertEqual(recent.placedFrame, departingFrame)
            for time in stride(from: 10.0, through: 90.0, by: 10) {
                clock.now = time
                host.frame()
                XCTAssertEqual(welcome.origin.x, welcomeOrigin.x, accuracy: 1)
                XCTAssertEqual(welcome.origin.y, welcomeOrigin.y, accuracy: 1)
            }
            clock.now = 100
            host.frame()
            let middle = input.origin
            XCTAssertEqual(recent.placedFrame, departingFrame)
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
