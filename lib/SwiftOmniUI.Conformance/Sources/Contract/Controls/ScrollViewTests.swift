// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// `ScrollViewContract` on a host: its content takes its width down and its own width across; an offset the tree
/// writes moves it within reach, heard by nobody; the user's scroll lands on the state on the display's frame, heard
/// each way it goes, and rests once; its bars show as the tree says.
@_spi(Host) public enum ScrollViewTests: ConformanceFamily {
    public static let name = "ScrollView"

    public static var cases: [ConformanceCase] {
        [
            Aspects.standsAlone("ScrollView"),
            Aspects.holds(ScrollViewContract.defaultScrollAnchor, on: "ScrollView", .top, then: .bottom),
            Aspects.holds(ScrollViewContract.isScrollDisabled, on: "ScrollView", false, then: true),
            Aspects.holds(ScrollViewContract.scrollBounceAxes, on: "ScrollView", [.vertical], then: [.horizontal]),
            Aspects.holds(ScrollViewContract.scrollBounceBehavior, on: "ScrollView", .automatic, then: .always),
            Aspects.holds(
                ScrollViewContract.scrollTargetBehavior, on: "ScrollView", .viewAligned(), then: .paging),
            ConformanceCase("scrollingDownItsContentTakesItsWidth", proves: [
                Covered(ScrollViewContract.orientation),
            ]) { s in
                let frames = Received<[Double]>()
                s.start {
                    VStack {
                        ScrollView {
                            ColorPicker(.red).frame(height: 2000).onEvent(ViewContract.frameChanged) { frames.values.append($0) }
                        }
                        .orientation(.vertical)
                        .frame(width: 200).frame(height: 100)
                    }
                    .horizontalAlignment(.start)
                    .verticalAlignment(.start)
                }

                s.settle { frames.values.last.map(FrameReport.size) == [200, 2000] }
                s.expect(frames.values.last.map(FrameReport.size), [200, 2000], "the scroller's width, its own height")
            },
            ConformanceCase("scrollingAcrossItsContentKeepsItsOwnWidth", proves: [
                Covered(ScrollViewContract.orientation),
            ]) { s in
                let frames = Received<[Double]>()
                s.start {
                    VStack {
                        ScrollView {
                            ColorPicker(.red).frame(width: 3000).frame(height: 40)
                                .onEvent(ViewContract.frameChanged) { frames.values.append($0) }
                        }
                        .orientation(.horizontal)
                        .frame(width: 200).frame(height: 100)
                    }
                    .horizontalAlignment(.start)
                    .verticalAlignment(.start)
                }

                s.settle { frames.values.last.map(FrameReport.size)?.first == 3000 }
                s.expect(frames.values.last.map(FrameReport.size)?.first, 3000, "its own width across")
            },
            ConformanceCase("anOffsetTheTreeWritesMovesItWithinReachUnheard", proves: [
                Covered(ScrollViewContract.scrollOffset), Covered(ScrollViewContract.scrollYChanged),
            ], needs: [Covered(ButtonContract.clicked)]) { s in
                let offset = State(wrappedValue: Point(0, 0))
                let heard = Received<Double>()
                s.start(reducesMotion: true) {
                    VStack {
                        Button("Down").onClicked { offset.wrappedValue = Point(0, 300) }.id("down")
                        Button("Past").onClicked { offset.wrappedValue = Point(0, 5000) }.id("past")
                        ScrollView { ColorPicker(.red).frame(height: 2000) }
                            .scrollOffset(offset.projectedValue)
                            .onEvent(ScrollViewContract.scrollYChanged) { heard.values.append($0) }
                            .frame(width: 200).frame(height: 500).id("scroller")
                    }
                    .horizontalAlignment(.start)
                    .verticalAlignment(.start)
                }
                let scroller = try s.element("scroller")

                try s.perform(.activate, on: s.element("down"))
                try s.settle { try s.held(ScrollViewContract.scrollOffset, on: scroller) == Point(0, 300) }
                s.expect(try s.held(ScrollViewContract.scrollOffset, on: scroller), Point(0, 300))

                try s.perform(.activate, on: s.element("past"))
                try s.settle { try s.held(ScrollViewContract.scrollOffset, on: scroller) == Point(0, 1500) }
                s.expect(try s.held(ScrollViewContract.scrollOffset, on: scroller), Point(0, 1500), "no further than its end")
                s.expect(heard.values, [], "the program's move heard by nobody")
            },
            ConformanceCase("theUsersScrollLandsOnTheFrameAndRestsOnce", proves: [
                Covered(ScrollViewContract.scrollOffset), Covered(ScrollViewContract.scrollYChanged),
                Covered(ScrollViewContract.scrollStopped),
            ]) { s in
                let clock = TestClock()
                let offset = State(wrappedValue: Point(0, 0))
                let heard = Received<Double>()
                let rests = Received<Int>()
                s.start(clock: clock) {
                    VStack {
                        ScrollView { ColorPicker(.red).frame(height: 2000) }
                            .scrollOffset(offset.projectedValue)
                            .onEvent(ScrollViewContract.scrollYChanged) { heard.values.append($0) }
                            .onScrollStopped { rests.values.append(1) }
                            .frame(width: 200).frame(height: 500).id("scroller")
                    }
                    .horizontalAlignment(.start)
                    .verticalAlignment(.start)
                }
                let scroller = try s.element("scroller")

                try s.perform(.scroll(to: Point(0, 200)), on: scroller)
                s.turn()
                for time in stride(from: 16.0, through: 400, by: 16) {
                    clock.now = time
                    s.frame()
                }

                s.expect(heard.values, [200], "heard once, where it went")
                s.expect(offset.wrappedValue, Point(0, 200), "and on the state")
                s.expect(rests.values, [1], "at rest once")
            },
            ConformanceCase("anAimScrollsUntilTheNamedChildStandsInView", proves: [
                Covered(ScrollViewContract.scrollToDescendant),
            ], needs: [Covered(ButtonContract.clicked)]) { s in
                let frames = Received<[Double]>()
                s.start {
                    ScrollViewReader { proxy in
                        VStack {
                            ScrollView {
                                VStack {
                                    ColorPicker(.red).frame(height: 400)
                                    ColorPicker(.green).frame(height: 400)
                                        .id("far")
                                        .onEvent(ViewContract.frameChanged) { frames.values.append($0) }
                                }
                            }
                            .frame(width: 200).frame(height: 300).id("scroller")
                            Button("Go").onClicked { proxy.scrollTo("far") }.id("go")
                        }
                    }
                    .horizontalAlignment(.start)
                    .verticalAlignment(.start)
                }

                try s.perform(.activate, on: s.element("go"))
                s.settle { frames.values.count > 1 && frames.values.last![1] < frames.values.first![1] }
                s.expect(frames.values.last![1] < frames.values.first![1], true, "the far child moved into view")
            },
            ConformanceCase("theUsersScrollAcrossIsHeard", proves: [
                Covered(ScrollViewContract.scrollXChanged), Covered(ScrollViewContract.orientation),
            ]) { s in
                let clock = TestClock()
                let heard = Received<Double>()
                s.start(clock: clock) {
                    VStack {
                        ScrollView { ColorPicker(.red).frame(width: 3000).frame(height: 40) }
                            .orientation(.horizontal)
                            .onEvent(ScrollViewContract.scrollXChanged) { heard.values.append($0) }
                            .frame(width: 200).frame(height: 100).id("scroller")
                    }
                    .horizontalAlignment(.start)
                    .verticalAlignment(.start)
                }
                let scroller = try s.element("scroller")

                try s.perform(.scroll(to: Point(300, 0)), on: scroller)
                s.turn()
                for time in stride(from: 16.0, through: 400, by: 16) {
                    clock.now = time
                    s.frame()
                }

                s.expect(heard.values, [300])
            },
            Aspects.holds(ScrollViewContract.verticalScrollIndicators, on: "ScrollView", .visible, then: .hidden),
            Aspects.holds(ScrollViewContract.horizontalScrollIndicators, on: "ScrollView", .visible, then: .hidden,
                          with: [Write(ScrollViewContract.orientation, Axis.horizontal)]),
        ]
    }
}
