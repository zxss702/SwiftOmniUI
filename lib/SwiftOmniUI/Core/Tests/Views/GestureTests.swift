// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// What a gesture reports, and how it gets here.
//
// A gesture carries more than one value - a status and a translation, a scale
// and an origin - so a payload is one value per property, in the order its
// update type declares them, each already typed. This is the file that pins
// that format down from the reading end; the writing end is each host's
// gesture adapter.

import XCTest
@_spi(Host) @testable import SwiftOmniUICore

@MainActor final class GestureTests: XCTestCase {
    func testAGestureArrivesAlreadyTyped() {
        let renders = Renders()
        var swipes: [SwipeDirection] = []
        var pans: [PanUpdate] = []
        var pinches: [PinchUpdate] = []
        var points: [Point] = []

        let patch = renders.render(
            ColorPicker(.cornflowerBlue)
                .onSwiped { swipes.append($0) }
                .onPanUpdated { pans.append($0) }
                .onPinchUpdated { pinches.append($0) }
                .onPointerMoved { points.append($0) }
                .node)

        let events = patch.events?.handlers ?? [:]

        renders.fire(events["swiped"] ?? -1, with: [.enumeration(SwipeDirection.left.rawValue)])
        renders.fire(events["panUpdated"] ?? -1, with: [
            .enumeration(GesturePhase.running.rawValue), .number(12.5), .number(-3),
            .numbers([10, 20]), .numbers([22.5, 17]),
        ])
        renders.fire(events["pinchUpdated"] ?? -1, with: [
            .enumeration(GesturePhase.completed.rawValue), .number(1.25), .numbers([0.5, 0.75]),
        ])
        renders.fire(events["pointerMoved"] ?? -1, with: [.numbers([12.5, 30])])

        XCTAssertEqual(swipes, [.left])

        XCTAssertEqual(pans.first?.phase, .running)
        XCTAssertEqual(pans.first?.totalX, 12.5)
        XCTAssertEqual(pans.first?.totalY, -3)
        XCTAssertEqual(pans.first?.startLocation, Point(x: 10, y: 20))
        XCTAssertEqual(pans.first?.location, Point(x: 22.5, y: 17))

        XCTAssertEqual(pinches.first?.phase, .completed)
        XCTAssertEqual(pinches.first?.scale, 1.25)
        XCTAssertEqual(pinches.first?.scaleOrigin, Point(x: 0.5, y: 0.75))

        XCTAssertEqual(points, [Point(x: 12.5, y: 30)])
    }

    /// A payload that cannot be read leaves the handler alone rather than
    /// inventing a value - the same rule a host follows for a property it does
    /// not recognize.
    ///
    /// The three ways one fails: a value short, the status sent as a plain
    /// NUMBER where a member of a closed vocabulary is wanted, and nothing at
    /// all. The middle one is the shape a host that stopped translating would
    /// send, which makes it the one worth having.
    func testAPayloadThatMakesNoSenseIsIgnored() {
        let renders = Renders()
        var pans = 0

        let patch = renders.render(ColorPicker().onPanUpdated { _ in pans += 1 }.node)
        let id = patch.events?["panUpdated"] ?? -1

        renders.fire(id, with: [.enumeration(GesturePhase.running.rawValue), .number(12.5)])
        renders.fire(id, with: [
            .number(Double(GesturePhase.running.rawValue)), .number(1), .number(2),
        ])
        renders.fire(id, with: [])

        XCTAssertEqual(pans, 0)

        renders.fire(id, with: [
            .enumeration(GesturePhase.started.rawValue), .number(0), .number(0),
            .numbers([10, 10]), .numbers([10, 10]),
        ])
        XCTAssertEqual(pans, 1)
    }

    /// The same rule for a swipe, where it matters most: a garbled payload
    /// read as an EMPTY direction set would run the handler with a value no
    /// direction test can tell from a real swipe.
    func testASwipeThatMakesNoSenseIsIgnoredToo() {
        let renders = Renders()
        var swipes = 0

        let patch = renders.render(ColorPicker().onSwiped { _ in swipes += 1 }.node)
        let id = patch.events?["swiped"] ?? -1

        // A direction sent as a plain number, and a payload with nothing in it.
        renders.fire(id, with: [.number(Double(SwipeDirection.left.rawValue))])
        renders.fire(id, with: [])

        XCTAssertEqual(swipes, 0)

        renders.fire(id, with: [.enumeration(SwipeDirection.left.rawValue)])
        XCTAssertEqual(swipes, 1)
    }

    /// The payload a platform really sends, kept as a case of its own because
    /// the refusals above are invented and this one is a measurement.
    ///
    /// A host's swipe recognizer may report the directions it was CONFIGURED
    /// for rather than the one the finger went, so a view listening every way
    /// sends exactly this - a true report of a message that says nothing, and
    /// refusing it is what leaves such a view silent on that host. A host
    /// that attaches one recognizer per direction never assembles a mask in
    /// the first place.
    func testASetOfDirectionsIsNotADirection() {
        let renders = Renders()
        var swipes: [SwipeDirection] = []

        let patch = renders.render(ColorPicker().onSwiped { swipes.append($0) }.node)
        let id = patch.events?["swiped"] ?? -1

        // What the platform sent, and the same thing spelled tidily.
        renders.fire(id, with: [.enumeration(SwipeDirection.all.rawValue)])
        renders.fire(id, with: [.enumeration(SwipeDirection([.left, .right]).rawValue)])

        XCTAssertEqual(swipes, [], "a set of directions does not answer 'which way'")

        renders.fire(id, with: [.enumeration(SwipeDirection.up.rawValue)])
        XCTAssertEqual(swipes, [.up])
    }

    func testAGestureSaysWhatItListensForBesideWhatItDoes() {
        let renders = Renders()

        let patch = renders.render(
            ColorPicker()
                .onSwiped(direction: [.up, .down], threshold: 40) { _ in }
                .onPanUpdated(touchCount: 2) { _ in }
                .onTapGesture(count: 2) {}
                .node)

        // The bits this library numbers them with - up 4, down 8 - as the one
        // number a bit set travels as.
        XCTAssertEqual(patch.props["swipeDirection"], .enumeration(12))
        XCTAssertEqual(patch.props["swipeThreshold"], .number(40))
        XCTAssertEqual(patch.props["panTouchCount"], .number(2))
        XCTAssertEqual(patch.props["tapCount"], .number(2))
    }

    /// A swipe that listens for nothing recognizes nothing, so the default is
    /// every direction rather than none.
    func testAViewListensForEveryDirectionUnlessItSaysOtherwise() {
        let renders = Renders()
        let patch = renders.render(ColorPicker().onSwiped { _ in }.node)

        XCTAssertEqual(patch.props["swipeDirection"], .enumeration(15), "every bit there is")
        XCTAssertNil(patch.props["swipeThreshold"], "a threshold nobody set is not sent")
    }

    /// A report of another shape than the view's contract declares reaches
    /// no handler - the typed modifier's, nor one heard through the member
    /// itself beside it. Both read what the contract declares, and a report
    /// that is not that is refused whole and said once, naming what arrived.
    func testAReportOfAnotherShapeReachesNoHandler() {
        let renders = Renders()
        var typed = 0
        var heard: [String] = []

        let patch = renders.render(
            ColorPicker()
                .onPinchUpdated { _ in typed += 1 }
                .onEvent(ViewContract.pinchUpdated) { phase, scale, origin in
                    heard.append("\(phase) \(scale) \(origin.x),\(origin.y)")
                }
                .node)

        let id = patch.events?["pinchUpdated"] ?? -1

        // The second is the first with its phase sent as a plain number, which
        // is the whole difference between a report and a refusal.
        let readable: [PropValue] = [
            .enumeration(GesturePhase.running.rawValue), .number(1.25), .numbers([0.5, 0.5]),
        ]
        let garbled: [PropValue] = [
            .number(Double(GesturePhase.running.rawValue)), .number(1.25), .numbers([0.5, 0.5]),
        ]

        renders.fire(id, with: readable)
        renders.fire(id, with: garbled)

        XCTAssertEqual(typed, 1, "the typed modifier read the one it could")
        XCTAssertEqual(heard, ["running 1.25 0.5,0.5"],
                       "and so did the member's handler beside it, and nothing else")
    }

    /// Every typed gesture modifier composes, so two of the same kind both run.
    func testTwoHandlersForOneGestureBothRun() {
        let renders = Renders()
        var first = 0
        var second = 0

        let patch = renders.render(
            ColorPicker()
                .onTapGesture { first += 1 }
                .onTapGesture { second += 1 }
                .node)

        renders.fire(patch.events?["tapGesture"] ?? -1)

        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 1, "the second handler ran too, rather than replacing the first")
    }

    /// A `DragGesture` attached with `.gesture` hears the same pan reports the
    /// platform sends: `onChanged` from the drag's first move until its last,
    /// `onEnded` as it lets go, each handed where the press began, where it is
    /// and how far it has come.
    func testADragGestureReportsItsValue() {
        let renders = Renders()
        var changed: [DragGesture.Value] = []
        var ended: [DragGesture.Value] = []

        let patch = renders.render(
            ColorPicker()
                .gesture(
                    DragGesture(minimumDistance: 5)
                        .onChanged { changed.append($0) }
                        .onEnded { ended.append($0) })
                .node)
        let id = patch.events?["panUpdated"] ?? -1

        func pan(_ phase: GesturePhase, _ x: Double, _ y: Double) {
            renders.fire(id, with: [
                .enumeration(phase.rawValue), .number(x), .number(y),
                .numbers([100, 100]), .numbers([100 + x, 100 + y]),
            ])
        }

        pan(.started, 0, 0)
        pan(.running, 2, 0)          // below the distance: not yet a drag
        XCTAssertTrue(changed.isEmpty)

        pan(.running, 6, 0)          // past it: the drag's first move
        pan(.running, 8, 2)
        pan(.completed, 8, 2)

        XCTAssertEqual(changed.count, 2)
        XCTAssertEqual(changed.last?.startLocation, Point(x: 100, y: 100))
        XCTAssertEqual(changed.last?.location, Point(x: 108, y: 102))
        XCTAssertEqual(changed.last?.translation, Size(width: 8, height: 2))

        XCTAssertEqual(ended.count, 1)
        XCTAssertEqual(ended.first?.translation, Size(width: 8, height: 2))
    }

    /// A press that never becomes a drag - let go below the distance - ends
    /// without a word: nothing began, so nothing ends.
    func testADragBelowTheDistanceEndsSilently() {
        let renders = Renders()
        var ran = 0

        let patch = renders.render(
            ColorPicker()
                .gesture(DragGesture(minimumDistance: 10)
                    .onChanged { _ in ran += 1 }
                    .onEnded { _ in ran += 1 })
                .node)
        let id = patch.events?["panUpdated"] ?? -1

        renders.fire(id, with: [
            .enumeration(GesturePhase.completed.rawValue), .number(3), .number(0),
            .numbers([50, 50]), .numbers([53, 50]),
        ])

        XCTAssertEqual(ran, 0)
    }

    func testWhatADragCarriesIsDecidedBeforeItStarts() {
        let renders = Renders()
        var dropped: [String] = []

        let patch = renders.render(
            VStack {
                Text("Alpha")
                    .draggable(text: "Alpha")
                    .id("source")

                ZStack {
                    Text("Drop here")
                }
                .onDrop { dropped.append($0) }
                .id("target")
            }
            .node)

        let source = patch.child("source")
        XCTAssertEqual(source?.props["dragText"], .string("Alpha"))
        XCTAssertEqual(source?.props["canDrag"], .bool(true))

        let target = patch.child("target")
        XCTAssertEqual(target?.props["allowDrop"], .bool(true),
                       "a view that handles a drop is a view that allows one")

        renders.fire(target?.events?["drop"] ?? -1, with: [.string("Alpha")])
        XCTAssertEqual(dropped, ["Alpha"])
    }

    /// The SwiftUI spelling: `dropPaths` decodes as the paths and the point,
    /// and `isTargeted` hears a drag come in, land and leave.
    func testAFileDropHandsThePathsAndThePoint() {
        let renders = Renders()
        var dropped: [String] = []
        var landed = Point.zero
        var targeted: [Bool] = []

        let patch = renders.render(
            Text("Drop here")
                .dropDestination { paths, point in
                    dropped = paths
                    landed = point
                } isTargeted: { targeted.append($0) }
                .node)

        renders.fire(patch.events?["dragOver"] ?? -1)
        renders.fire(patch.events?["dropPaths"] ?? -1, with: [.strings(["/tmp/a.txt", "/tmp/b.txt"]), .numbers([4, 6])])
        stateUIRunJobs()

        XCTAssertEqual(dropped, ["/tmp/a.txt", "/tmp/b.txt"])
        XCTAssertEqual(landed, Point(4, 6))
        XCTAssertEqual(targeted, [true, false])
    }
}
