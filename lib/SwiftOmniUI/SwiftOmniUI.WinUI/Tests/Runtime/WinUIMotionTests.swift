// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) @testable import SwiftOmniUICore
@_spi(Host) @testable import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import SwiftOmniUIConformance
import WinSDK
import XCTest

final class WinUIMotionTests: XCTestCase {
    func testBothConversationPanesPaintTextAfterADelayedTransitionFrame() throws {
        try onUIThread {
            let clock = TestClock()
            let record = State(wrappedValue: 0)
            let messages = State(wrappedValue: false)
            let host = WinUIRenderer.running(clock: clock, room: WinUITestHost.wideRoom) {
                NavigationSplitView(Binding(get: { true }, set: { _ in })) {
                    Text("Workspace.swift").id("workspace")
                } detail: {
                    HStack(spacing: 0) {
                        Self.conversationPane("center", record: record.wrappedValue, loaded: messages.wrappedValue)
                        Self.conversationPane("group", record: record.wrappedValue, loaded: messages.wrappedValue)
                            .frame(width: 260)
                            .safeAreaInset(edge: .top, spacing: 0) {
                                Text("Group chat").frame(height: 36)
                            }
                    }
                }
            }
            let window = try XCTUnwrap(host.window)
            let title = "SOUI conversation paint regression"
            window.setTitle(title)
            let nativeTitle = Array(title.utf16) + [0]
            let hwnd = try XCTUnwrap(nativeTitle.withUnsafeBufferPointer { FindWindowW(nil, $0.baseAddress) })
            let positionFlags = UINT(SWP_NOACTIVATE | SWP_NOSIZE)
            XCTAssertTrue(SetWindowPos(hwnd, HWND(bitPattern: -1), 32, 32, 0, 0, positionFlags))
            defer { _ = SetWindowPos(hwnd, HWND(bitPattern: -2), 32, 32, 0, 0, positionFlags) }
            var presentedLabels = 0
            for selection in 1...4 {
                withAnimation(.snappy) {
                    record.wrappedValue = selection
                    messages.wrappedValue = false
                }
                host.step()
                host.frame()
                clock.now += 32
                withAnimation(.snappy) { messages.wrappedValue = true }
                host.settle {
                    ["center", "group"].allSatisfy {
                        host.view(id: .manual("\($0)-\(selection)-bubble")) != nil
                    }
                }
                host.frame()
                for pane in ["center", "group"] {
                    let bubble = try XCTUnwrap(host.view(id: .manual("\(pane)-\(selection)-bubble")))
                    XCTAssertGreaterThan(bubble.blur, 0, "\(pane) starts with a live blur transition")
                }

                // Resume the display clock after a gap long enough to finish both transitions.
                clock.now += 1_200
                host.frame()
                for _ in 0..<5 { host.step() }

                for pane in ["center", "group"] {
                    let bubble = try XCTUnwrap(host.view(id: .manual("\(pane)-\(selection)-bubble")))
                    let label = try XCTUnwrap(
                        bubble.sourceElement?.first(type: .text)?.winUI.view as? WinUILabelView,
                        "\(pane) conversation \(selection) must mount its message"
                    )
                    XCTAssertEqual(bubble.blur, 0, accuracy: 0.01)
                    XCTAssertEqual(bubble.drawnOpacity, 1, accuracy: 0.01)
                    XCTAssertTrue(WinUIView.words(of: label.handle).contains("Imported conversation \(selection)"))
                    let points = stride(from: 2.5, to: min(34, label.frame.height), by: 4).flatMap { y in
                        stride(from: 2.5, to: min(148, label.frame.width), by: 4).map { x in (x, y) }
                    }
                    let presented = label.presentedPixels(at: points, in: window)
                    if !presented.isEmpty {
                        XCTAssertTrue(presented.contains(where: Self.isDarkInk), "\(pane) presented text")
                        presentedLabels += 1
                    }
                    XCTAssertTrue(label.pixels(at: points).contains(where: Self.isDarkInk), "\(pane) XAML text")
                }
            }
            print("Conversation text sampled on the desktop for \(presentedLabels) of 8 labels")
        }
    }

    private static func isDarkInk(_ pixel: UInt32) -> Bool {
        pixel >> 24 > 127 && (pixel & 0xff) < 100 && ((pixel >> 8) & 0xff) < 100
            && ((pixel >> 16) & 0xff) < 100
    }

    @MainActor private static func conversationPane(_ name: String, record: Int, loaded: Bool) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading) {
                if loaded {
                    VStack(alignment: .leading) {
                        (Text("Imported conversation \(record)").bold()
                         + Text("\nSeveral lines of selectable message text.\nAdditional content for native layout."))
                            .foregroundStyle(.black)
                            .backgroundPreferenceValue(Text.LayoutKey.self) { _ in Color.clear }
                    }
                    .padding(16)
                    .background { RoundedRectangle(cornerRadius: 12).fill(Color("#E1EEF8")) }
                    .id("\(name)-\(record)-bubble")
                    .transition(.blur.combined(with: .offset(x: 48, y: 80)))
                }
                Color.clear.frame(height: 520)
            }
            .padding(16)
        }
        .id("\(name)-\(record)")
        .transition(.blur.combined(with: .scale(y: 1.02, anchor: .top)))
    }

    func testTextEditorBackgroundKeepsTheEditorsAnimatedFrame() throws {
        try onUIThread {
            let clock = TestClock()
            let expanded = State(wrappedValue: false)
            let host = WinUIRenderer.running(clock: clock) {
                VStack {
                    TextEditor()
                        .frame(width: 320, height: expanded.wrappedValue ? 128 : 44)
                        .background(Color.black, in: RoundedRectangle(cornerRadius: 12))
                        .animation(.eased(200, .linear), value: expanded.wrappedValue)
                        .id("editor")
                }
            }
            let editor = try XCTUnwrap(host.view(id: .manual("editor")))
            let background = try XCTUnwrap(host.views(WinUIPathView.self).first)
            XCTAssertEqual(editor.placedFrame.height, 44, accuracy: 0.5)
            XCTAssertEqual(background.placedFrame.height, 44, accuracy: 0.5)

            expanded.wrappedValue = true
            host.runtime.pump.turn()
            host.frame()
            clock.now = 100
            host.frame()

            XCTAssertEqual(editor.placedFrame.height, 86, accuracy: 1)
            XCTAssertEqual(background.placedFrame.height, editor.placedFrame.height, accuracy: 1)
            XCTAssertTrue(host.view(id: .manual("editor")) === editor)
        }
    }

    func testScaledTranslatedBlurredTabCaptionsDoNotAlternateEllipsis() throws {
        try onUIThread {
            let clock = TestClock()
            let selection = State(wrappedValue: 0)
            let captions = ["负责人", "工程师"]
            let host = WinUIRenderer.running(clock: clock) {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(0..<2) { index in
                            let selected = selection.wrappedValue == index
                            Button {
                                withAnimation(.snappy) { selection.wrappedValue = index }
                            } label: {
                                HStack(spacing: 0) {
                                    Color.blue
                                        .frame(width: selected ? 24 : 32, height: selected ? 24 : 32)
                                        .frame(width: 32, height: 32)
                                        .padding(.leading, selected ? 4 : 0)
                                    if selected {
                                        Text(captions[index])
                                            .font(.system(size: 14.1))
                                            .tracking(0.13)
                                            .lineLimit(1)
                                            .padding(.trailing, 12)
                                            .transition(.blur.combined(with: .scale(anchor: .leading))
                                                .combined(with: .offset(x: -32)))
                                    }
                                }.frame(height: 32)
                            }.id("caption-tab-\(index)")
                        }
                    }.padding(8).buttonStyle(.plain)
                }.frame(width: 320, height: 64)
            }

            for index in [1, 0, 1] {
                let start = clock.now
                let button = try XCTUnwrap(host.view(id: .manual("caption-tab-\(index)")) as? WinUIButtonView)
                button.invoke()
                host.step()
                let label = try XCTUnwrap(host.views(WinUILabelView.self).first { $0.text == captions[index] })
                let identity = label.handle
                // Include the first presentation and spring overshoot; an
                // assertion at rest alone misses the reported full/ellipsis flicker.
                for elapsed in [0.0, 16, 48, 96, 160, 240, 400, 700, 1200] {
                    clock.now = start + elapsed
                    host.frame()
                    let current = try XCTUnwrap(host.views(WinUILabelView.self).first {
                        $0.text == captions[index] && $0.isAttached
                    })
                    XCTAssertEqual(current.handle, identity, "drawing must preserve the native paragraph")
                    var result = [CChar](repeating: 0, count: 8)
                    let count = swiftomniui_winui_read(current.handle, "isTextTrimmed", &result, Int32(result.count))
                    XCTAssertEqual(count, 1)
                    XCTAssertEqual(result[0], 48,
                                   "caption \(captions[index]) must fit during transition at \(elapsed)ms")
                }
            }
        }
    }

    func testOrdinaryHoverUpdatesTheBackgroundWithoutWaitingForAnimationTime() throws {
        try onUIThread {
            let hovered = State(wrappedValue: false)
            let host = WinUIRenderer.running(clock: TestClock()) {
                ZStack { Text("Row") }
                    .frame(width: 200, height: 40)
                    .background(hovered.wrappedValue ? Color.black : Color.clear)
                    .onHover { hovered.wrappedValue = $0 }
                    .id("hover-row")
            }
            let element = try XCTUnwrap(host.runtime.tree.root?.first(id: .manual("hover-row")))
            let row = try XCTUnwrap(host.view(id: element.id) as? WinUILayoutView)
            let revision = row.measurementRevision
            XCTAssertNil(row.boxView, "a clear background needs no native shape")
            row.heard(.pointer(.pointerEntered, .zero))
            XCTAssertEqual(element.value(.background), Color.black.propValue)
            XCTAssertFalse(host.runtime.animator.isMoving)
            XCTAssertEqual(row.measurementRevision, revision)
            let box = try XCTUnwrap(row.boxView)
            row.heard(.pointer(.pointerEntered, .zero))
            XCTAssertTrue(row.boxView === box, "an unchanged brush preserves its native shape")
            row.heard(.pointer(.pointerExited, .zero))
            XCTAssertEqual(element.value(.background), Color.clear.propValue)
            XCTAssertFalse(host.runtime.animator.isMoving)
        }
    }

    /// A colour box whose colour and width change under a animation stands halfway at half its time, and lands - the
    /// Gallery's Animation sample: what travels is the host layer's list.
    func testAColourAndAWidthTravelHalfwayAndLand() throws {
        try onUIThread {
            let clock = TestClock()
            let wide = State(wrappedValue: false)
            let host = WinUIRenderer.running(clock: clock) {
                VStack {
                    Color.clear
                        .frame(width: wide.wrappedValue ? 300 : 100, height: 60)
                        .background(wide.wrappedValue ? Color("#FF0000") : Color("#0000FF"))
                        .horizontalAlignment(.start)
                        .animation(.eased(1000, .linear))
                        .id("box")
                }
            }
            let box = try XCTUnwrap(host.view(id: .manual("box")))
            XCTAssertEqual(box.laidOutFrame.width, 100, accuracy: 0.5)

            wide.wrappedValue = true
            host.runtime.pump.turn()
            clock.now = 500
            host.frame()
            XCTAssertEqual(box.placedFrame.width, 200, accuracy: 1, "halfway across")
            let halfway = box.pixels(at: [(20, 30)])[0]
            XCTAssertEqual(Double((halfway >> 16) & 0xFF), 127.5, accuracy: 8, "halfway to red")
            XCTAssertEqual(Double(halfway & 0xFF), 127.5, accuracy: 8, "halfway from blue")

            clock.now = 1000
            host.frame()
            XCTAssertEqual(box.laidOutFrame.width, 300, accuracy: 0.5, "landed")
            XCTAssertEqual((box.pixels(at: [(20, 30)])[0] >> 16) & 0xFF, 255)
        }
    }

    func testAPropertyTransitionBeginsWhereItStandsAndLandsExactly() throws {
        try onUIThread {
            let clock = TestClock()
            let host = WinUIRenderer.bare(clock: clock)
            var initial = HostPatch(id: .manual("label"), type: .text)
            initial.properties[.opacity] = .number(0.25)
            host.apply(initial)

            var changed = HostPatch(id: .manual("label"), type: .text)
            changed.properties[.opacity] = .number(0.75)
            changed.transitions[.opacity] = HostTransition(animation: .eased(200, .linear))
            host.apply(changed)

            let label = try XCTUnwrap(host.view(id: .manual("label")))
            XCTAssertEqual(label.drawnOpacity, 0.25, accuracy: 1e-6)

            clock.now = 100
            host.frame()
            XCTAssertEqual(label.drawnOpacity, 0.5, accuracy: 1e-6)

            clock.now = 200
            host.frame()
            XCTAssertEqual(label.drawnOpacity, 0.75, accuracy: 1e-6)
            XCTAssertFalse(host.runtime.describedMotion.isActive)
        }
    }

    func testLessMotionPutsThePropertyAtItsValueAtOnce() throws {
        try onUIThread {
            let host = WinUIRenderer.bare(clock: TestClock(), reducesMotion: true)
            var initial = HostPatch(id: .manual("label"), type: .text)
            initial.properties[.opacity] = .number(0.25)
            host.apply(initial)

            var changed = HostPatch(id: .manual("label"), type: .text)
            changed.properties[.opacity] = .number(0.75)
            changed.transitions[.opacity] = HostTransition(animation: .eased(200, .linear))
            host.apply(changed)

            XCTAssertEqual(try XCTUnwrap(host.view(id: .manual("label"))).drawnOpacity, 0.75, accuracy: 1e-6)
            XCTAssertFalse(host.runtime.animator.isMoving)
        }
    }

    /// A still page holds no frames: WinUI's frames are subscribed to only while something moves, and let go once it
    /// stands again.
    func testAStillPageHoldsNoFramesTillSomethingMoves() throws {
        try onUIThread {
            let level = State(wrappedValue: 0.0)
            let arrived = State(wrappedValue: false)
            let host = WinUIRenderer.running {
                VStack {
                    Slider(level.projectedValue)
                    Button("Go").onClicked {
                        try await level.projectedValue.journey.move(to: 1, .eased(100, .linear))
                        arrived.wrappedValue = true
                    }
                }
            }
            for _ in 0..<10 { host.step() }
            XCTAssertFalse(host.frameClock.held, "a still page")
            XCTAssertFalse(swiftomniui_winui_holds_frames(), "no frame of WinUI's heard")

            try XCTUnwrap(host.views(WinUIButtonView.self).first).invoke()
            host.step()
            XCTAssertTrue(swiftomniui_winui_holds_frames(), "frames while it moves")
            host.settle(until: { arrived.wrappedValue })
            for _ in 0..<10 { host.step() }
            XCTAssertFalse(host.frameClock.held)
            XCTAssertFalse(swiftomniui_winui_holds_frames(), "and none once it stands again")
        }
    }

    /// One state, one channel: both sliders stand at the same value on every frame, and the waiter hears the arrival.
    func testAJourneyMovesEveryBoundControlOnTheSameFrames() throws {
        try onUIThread {
            let clock = TestClock()
            let level = State(wrappedValue: 0.0)
            let arrived = State(wrappedValue: false)
            let host = WinUIRenderer.running(clock: clock) {
                VStack {
                    Text(arrived.wrappedValue ? "arrived" : "away")
                    Slider(level.projectedValue)
                    Slider(level.projectedValue)
                    Button("Go").onClicked {
                        try await level.projectedValue.journey.move(to: 1, .eased(200, .linear))
                        arrived.wrappedValue = true
                    }
                }
            }
            let sliders = host.views(WinUISliderView.self)
            XCTAssertEqual(sliders.count, 2)

            try XCTUnwrap(host.views(WinUIButtonView.self).first).invoke()
            clock.now = 100
            host.frame()
            XCTAssertEqual(sliders.map(\.value), [0.5, 0.5])

            clock.now = 200
            host.frame()
            XCTAssertEqual(sliders.map(\.value), [1, 1])

            host.settle { arrived.wrappedValue }
            XCTAssertEqual(host.views(WinUILabelView.self).map(\.text), ["arrived"])
        }
    }

    /// The transform stands on the element where its layout put it, turning and scaling about its pivot.
    func testTheViewIsMovedTurnedAndScaledWhereItsLayoutPutIt() throws {
        try onUIThread {
            let host = WinUIRenderer.running {
                VStack {
                    Text("turned")
                        .frame(width: 100)
                        .frame(height: 40)
                        .offset(x: 10)
                        .rotationEffect(30)
                        .scaleEffect(2)
                        .scaleEffect(x: 1.5)
                        .pivotX(0)
                        .id("transformed-frame")
                }
            }
            let surface = try XCTUnwrap(host.view(id: .manual("transformed-frame")))
            let drawn = surface.drawnTransform

            XCTAssertEqual(drawn.translationX, 10)
            XCTAssertEqual(drawn.rotation, 30)
            XCTAssertEqual(drawn.scaleX, 3)
            XCTAssertEqual(drawn.scaleY, 2)
            XCTAssertEqual(drawn.centerX, 0, "the pivot's left edge")
            XCTAssertEqual(drawn.centerY, 20, "halfway down the 40 DIPs it was placed at")
            XCTAssertEqual(drawn.translationY, 0, "rotation and scale do not add a vertical offset")
        }
    }

    func testAMoveCarriedByAJourneyTravelsOnTheDisplaysFrames() throws {
        try onUIThread {
            let clock = TestClock()
            let offset = State(wrappedValue: 0.0)
            let host = WinUIRenderer.running(clock: clock) {
                VStack {
                    Text("moving").offset(x: offset.projectedValue)
                    Button("Go").onClicked {
                        try await offset.projectedValue.journey.move(to: 100, .eased(200, .linear))
                    }
                }
            }
            let label = try XCTUnwrap(host.views(WinUILabelView.self).first)

            try XCTUnwrap(host.views(WinUIButtonView.self).first).invoke()
            clock.now = 100
            host.frame()
            XCTAssertEqual(label.drawnTransform.translationX, 50, accuracy: 0.01)

            clock.now = 200
            host.frame()
            XCTAssertEqual(label.drawnTransform.translationX, 100, accuracy: 0.01)
        }
    }

    /// A layout cut to its outline is still moved, turned and scaled: the cut takes the element's own visual, and
    /// what moves it must be what WinUI still lets move it.
    func testALayoutCutToItsOutlineIsStillMoved() throws {
        try onUIThread {
            let moved = State(wrappedValue: false)
            let host = WinUIRenderer.running {
                VStack {
                    VStack { Text("cut") }
                        .frame(width: 40, height: 40)
                        .background(Color("#FF0000"))
                        .clipsContent(true)
                        .horizontalAlignment(.start)
                        .offset(x: moved.wrappedValue ? 50 : 0)
                    Button("Move") { moved.wrappedValue = true }
                }
                .frame(width: 100)
                .horizontalAlignment(.start)
                .verticalAlignment(.start)
                .id("cut-page")
            }
            let page = try XCTUnwrap(host.view(id: .manual("cut-page")))
            host.settle { page.pixels(at: [(20, 20)]) == [0xFFFF_0000] }

            try XCTUnwrap(host.views(WinUIButtonView.self).first).invoke()
            host.settle { page.pixels(at: [(70, 35)]) == [0xFFFF_0000] }
            XCTAssertEqual(page.pixels(at: [(20, 35), (70, 35)]), [0, 0xFFFF_0000])
        }
    }
}
