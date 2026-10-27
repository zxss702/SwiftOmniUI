// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) @testable import SwiftOmniUICore
@_spi(Host) @testable import SwiftOmniUIHost
import XCTest

/// An element's transition: arriving at a phase's standing and riding back, and
/// leaving kept mounted while its removal plays, reversed where a patch
/// describes it again.
@MainActor
final class DepartureTests: XCTestCase {
    /// A child a patch drops and that was described with a transition keeps its
    /// seat, its components riding to the removal phase; as the last lands it
    /// leaves and the parent drops it.
    func testADropRidesItsRemovalTransitionThenLeaves() throws {
        let (runtime, clock) = Self.stack(transition: .opacity)
        let parent = runtime.tree.root!
        let child = parent.children[0]

        Self.apply(children: [], to: parent.id, in: runtime)
        XCTAssertEqual(parent.children.map(\.id), [.manual("a")], "kept while it goes")
        XCTAssertTrue(child.isDeparting)

        clock.time = 100
        runtime.displayCycle.frame(now: 100)
        XCTAssertEqual(
            runtime.tree.presentedPropertyValue(mount: child.mount, property: .opacity), .number(0.5))

        clock.time = 200
        runtime.displayCycle.frame(now: 200)
        XCTAssertFalse(child.isDeparting)
        XCTAssertEqual(parent.children.map(\.id), [], "gone once it lands")
    }

    func testAnotherWindowArrangementDoesNotDiscardADepartingChild() {
        let (runtime, clock) = Self.stack(transition: .opacity)
        let parent = runtime.tree.root!
        let child = parent.children[0]
        Self.apply(children: [], to: parent.id, in: runtime)
        clock.time = 50
        runtime.displayCycle.frame(now: 50)
        Self.apply(children: [], to: parent.id, in: runtime)
        XCTAssertTrue(parent.children.first === child)
        clock.time = 100
        runtime.displayCycle.frame(now: 100)
        XCTAssertEqual(runtime.tree.presentedPropertyValue(mount: child.mount, property: .opacity), .number(0.5))
        clock.time = 200
        runtime.displayCycle.frame(now: 200)
        XCTAssertTrue(parent.children.isEmpty)
    }

    /// A child without a transition still leaves at once.
    func testADropWithoutATransitionLeavesAtOnce() {
        let (runtime, _) = Self.stack(transition: nil)
        let parent = runtime.tree.root!

        Self.apply(children: [], to: parent.id, in: runtime)
        XCTAssertEqual(parent.children.map(\.id), [])
    }

    /// A patch describing a departing child again reverses its removal: the
    /// running components ride back to where they stand.
    func testADescribedAgainDepartureRidesBack() throws {
        let (runtime, clock) = Self.stack(transition: .opacity)
        let parent = runtime.tree.root!
        let child = parent.children[0]

        Self.apply(children: [], to: parent.id, in: runtime)
        clock.time = 100
        runtime.displayCycle.frame(now: 100)
        XCTAssertEqual(
            runtime.tree.presentedPropertyValue(mount: child.mount, property: .opacity), .number(0.5))

        Self.apply(children: [.manual("a")], to: parent.id, in: runtime)
        XCTAssertFalse(child.isDeparting)
        XCTAssertTrue(parent.children[0] === child, "the same child comes back")

        clock.time = 200
        runtime.displayCycle.frame(now: 200)
        XCTAssertEqual(
            runtime.tree.presentedPropertyValue(mount: child.mount, property: .opacity), .number(0.625),
            "half its ride back, the removal's speed carried")
        XCTAssertEqual(parent.children.map(\.id), [.manual("a")])

        clock.time = 400
        runtime.displayCycle.frame(now: 400)
        XCTAssertNil(runtime.tree.presentedPropertyValue(mount: child.mount, property: .opacity))
    }

    /// The transition's own `.animation(_:)` names the law its removal rides.
    func testATransitionsOwnAnimationNamesTheLaw() throws {
        let (runtime, clock) = Self.stack(transition: .opacity.animation(.eased(400, .linear)))
        let child = runtime.tree.root!.children[0]

        Self.apply(children: [], to: runtime.tree.root!.id, in: runtime)
        clock.time = 100
        runtime.displayCycle.frame(now: 100)
        XCTAssertEqual(
            runtime.tree.presentedPropertyValue(mount: child.mount, property: .opacity), .number(0.75),
            "a quarter through its own 400 ms")
    }

    /// A `move` slides by the room the departing view stood in.
    func testAMoveSlidesByTheDepartingRoom() throws {
        let (runtime, clock) = Self.stack(transition: .move(edge: .trailing), room: 120)
        let child = runtime.tree.root!.children[0]

        Self.apply(children: [], to: runtime.tree.root!.id, in: runtime)
        clock.time = 100
        runtime.displayCycle.frame(now: 100)
        XCTAssertEqual(
            runtime.tree.presentedPropertyValue(mount: child.mount, property: .translationX),
            .number(60), "half its 200 ms slide by its room across")
    }

    /// An element described with a transition fades in by its insertion phase,
    /// not by the plain opacity crossing.
    func testAnInsertionRidesItsPhaseValuesIn() throws {
        let (runtime, clock) = Self.stack(transition: .blur.combined(with: .scale(scale: 0.8)))
        let child = runtime.tree.root!.children[0]
        let view = FadingViewSpy()

        child.fadeIn(view, room: Rect(x: 0, y: 0, width: 50, height: 30), under: .eased(200, .linear))
        XCTAssertEqual(
            runtime.tree.presentedPropertyValue(mount: child.mount, property: .opacity), .number(0))
        XCTAssertEqual(
            runtime.tree.presentedPropertyValue(mount: child.mount, property: .scaleX), .number(0.8))
        XCTAssertEqual(
            runtime.tree.presentedPropertyValue(mount: child.mount, property: .blur), .number(8))

        clock.time = 100
        runtime.displayCycle.frame(now: 100)
        XCTAssertEqual(
            runtime.tree.presentedPropertyValue(mount: child.mount, property: .opacity), .number(0.5))
        XCTAssertEqual(
            runtime.tree.presentedPropertyValue(mount: child.mount, property: .scaleX), .number(0.9))
        XCTAssertEqual(
            runtime.tree.presentedPropertyValue(mount: child.mount, property: .blur), .number(4))

        clock.time = 200
        runtime.displayCycle.frame(now: 200)
        XCTAssertNil(runtime.tree.presentedPropertyValue(mount: child.mount, property: .opacity))
    }

    /// A described transition is reason enough to fade in.
    func testATransitionedElementFadesIn() {
        let (runtime, _) = Self.stack(transition: .blur)
        let child = runtime.tree.root!.children[0]

        XCTAssertTrue(child.fadesIn(presentsOpacity: false), "the transition carries it")
    }

    /// A stack of one child described with `transition`, on a wound clock whose
    /// animation runs a linear 200 ms; `room` is the room its view stood in.
    private static func stack(
        transition: AnyTransition?, room: Double? = nil
    ) -> (HostRuntime, WoundClock) {
        let clock = WoundClock()
        let natives = Natives()
        let runtime = HostRuntime(
            clock: clock, reducesMotion: { false }, makeNative: { _ in natives.make() }, log: { _ in })
        runtime.layoutMotion.applicationMotion = .eased(200, .linear)

        var child = HostPatch(id: .manual("a"), type: .text)
        if let transition { child.properties[.transition] = transition.propValue }
        var stack = HostPatch(id: .manual("stack"), type: .vStack)
        stack.children = .arranged([child])
        runtime.tree.apply(stack, complete: true)

        if let room { natives.last?.room = Rect(x: 0, y: 0, width: room, height: 20) }
        return (runtime, clock)
    }

    /// The children `stack` next says it has, by id alone.
    private static func apply(children: [ElementId], to stack: ElementId, in runtime: HostRuntime) {
        var patch = HostPatch(id: stack, type: .vStack)
        patch.children = .arranged(children.map { HostPatch(id: $0, type: .text) })
        runtime.tree.apply(patch, complete: false)
    }
}

/// The native halves a runtime hands out, the last one findable.
@MainActor
private final class Natives {
    private(set) var last: TransitionNative?
    func make() -> any NativeElement {
        let view = TransitionNative()
        last = view
        return view
    }
}

/// Unlike the ordinary no-view fixture, this native half advertises the
/// transition properties whose presentation these tests actually exercise.
@MainActor
private final class TransitionNative: NativeElement {
    let presentsView = true
    var room: Rect?
    var departingRoom: Rect? { room }
    func standingValue(_ property: Prop) -> HostValue? { nil }
    func animates(_ property: Prop) -> Bool {
        property == .blur || TransitionSurface.presentsDrawing(property)
    }
    func applied(changed: Set<Prop>, wasDescribed: Bool) {}
    func presentFrame(_ changed: Set<Prop>) {}
    func arrangeChildren() {}
    func leave() {}
}

/// A view that only stands somewhere.
@MainActor
private final class FadingViewSpy: FadingView {
    var isShown = true
    var opacity = 1.0
    func setShown(_ shown: Bool) { isShown = shown }
    func setOpacity(_ opacity: Double) { self.opacity = opacity }
}

/// A clock whose time the test sets.
@MainActor
private final class WoundClock: FrameClock {
    var time = 0.0
    lazy var now: () -> Double = { [unowned self] in self.time }
    var held = false
    var onFrame: ((Double) -> Void)?
}
