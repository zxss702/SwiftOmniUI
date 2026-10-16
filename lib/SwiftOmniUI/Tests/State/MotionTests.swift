// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// A VALUE THAT CHANGES TRAVELS. What these pin is the Swift half of that: which
// property changes get a animation written beside them, which get none, and what
// the numbers in one are.
//
// The rule is one sentence - every property of a CONTINUING element whose value
// has a half-way - and everything below is one of the ways out of it: an element
// being described for the first time, a value with no half-way, a place or a
// count, a property the library computes, and a READING a control wrote back,
// which arrives because a value following a finger must not lag behind it.

import XCTest
@_spi(Host) @testable import SwiftOmniUICore

@MainActor final class MotionTests: XCTestCase {
    func testExplicitTransactionReopensIdleLayoutLanesOnAFullDescription() {
        let differ = Differ()
        func stack(_ width: Double) -> Node {
            VStack { Text("Row").frame(width: width) }.node
        }
        let initial = differ.reconcile(nil, with: stack(80))
        XCTAssertEqual(initial.node.lanes, [])
        let law = Animation.eased(200, .linear)
        differ.transaction = Transaction(animation: law)
        let changed = differ.reconcile(initial.node, with: stack(120))
        XCTAssertEqual(changed.patch.layoutTransition?.animation, law)
        XCTAssertEqual(changed.patch.layoutTransition?.lanes, .all,
                       "idle .none is not a permanent prohibition on explicit animation")
        var disabled = Transaction(animation: law)
        disabled.disablesAnimations = true
        differ.transaction = disabled
        let stopped = differ.reconcile(changed.node, with: stack(160))
        XCTAssertEqual(stopped.patch.layoutTransition?.lanes, [])
    }

    func testValueGateReopensIdlePlacementLanesOnlyWhenItsValueChanges() {
        let differ = Differ()
        let law = Animation.eased(200, .linear)
        func stack(_ expanded: Bool, text: String) -> Node {
            VStack { Text(text).frame(height: expanded ? 80 : 40) }
                .animation(law, value: expanded).node
        }
        let initial = differ.reconcile(nil, with: stack(false, text: "one"))
        let changed = differ.reconcile(initial.node, with: stack(true, text: "one"))
        XCTAssertEqual(changed.patch.layoutTransition?.lanes, .all)
        XCTAssertEqual(changed.patch.layoutTransition?.animation, law)
        let ordinary = differ.reconcile(changed.node, with: stack(true, text: "two"))
        XCTAssertNil(ordinary.patch.layoutTransition)
    }

    func testWithAnimationHasPlacementTimingWithoutChangingStandingConfiguration() throws {
        let rows = State(wrappedValue: [0, 1])
        let differ = Differ()
        let page = LazyVStack {
            ForEach(rows.wrappedValue) { Text("Row \($0)").frame(height: 28) }
        }
        let first = differ.reconcile(nil, with: page.node)
        let law = Animation.eased(200, .linear)
        withAnimation(law) { rows.wrappedValue.append(2) }
        differ.transaction = Transaction(animation: law)
        let update = differ.revisit(first.node, changed: Renderer.shared.pendingChanges)
        let lazy = try XCTUnwrap(update.patch.subtree.first { $0.type == .lazyVStack })
        XCTAssertEqual(lazy.layoutTransition?.animation, law)
        XCTAssertEqual(lazy.layoutTransition?.lanes, .all)
        XCTAssertNil(lazy.animation, "a transaction must not replace the standing animation")

        differ.transaction = nil
        rows.wrappedValue.append(3)
        let ordinary = differ.revisit(update.node, changed: Renderer.shared.pendingChanges)
        let next = try XCTUnwrap(ordinary.patch.subtree.first { $0.type == .lazyVStack })
        XCTAssertNil(next.layoutTransition, "later unanimated data must not inherit the earlier transaction")
    }

    func testGeometryFeedbackDoesNotReplaceAnAnimatedWriteBeforeRender() {
        let renderer = Renderer.shared
        let observed = NSObject()
        let id = ObjectIdentifier(observed)
        renderer.clearInvalidation()
        renderer.reading([id])
        defer {
            renderer.unreading([id])
            renderer.clearInvalidation()
        }

        let law = Animation.eased(200, .linear)
        withAnimation(law) { renderer.stateChanged(observed) }
        var feedback = Transaction()
        feedback.isGeometryFeedback = true
        withTransaction(feedback) { renderer.stateChanged(observed) }

        _ = renderer.renderHost(baseline: 0)
        XCTAssertEqual(renderer.differ.transaction?.animation, law)
        XCTAssertFalse(renderer.differ.transaction?.isGeometryFeedback ?? true)

        withTransaction(feedback) { renderer.stateChanged(observed) }
        _ = renderer.renderHost(baseline: 0)
        XCTAssertTrue(renderer.differ.transaction?.isGeometryFeedback == true,
                      "geometry feedback alone must still suppress geometry animation")
    }

    func testOrdinaryHoverColourArrivesWithoutAnImplicitAnimation() {
        let renders = Renders()

        func row(_ hovered: Bool) -> Node {
            ZStack { Text("Row") }
                .background(hovered ? Color("#333333") : Color("#FFFFFF"))
                .id("hover-row")
                .node
        }

        renders.render(row(false), animation: .none)
        let patch = renders.render(row(true), animation: .none)

        XCTAssertEqual(patch.props[.background], Color("#333333").propValue)
        XCTAssertNil(patch.transitions[.background])
    }

    func testValueGatedHoverColourStillAnimatesWhenItsValueChanges() {
        let renders = Renders()
        let law = Animation.eased(120, .linear)

        func row(_ hovered: Bool) -> Node {
            ZStack { Text("Row") }
                .background(hovered ? Color("#333333") : Color("#FFFFFF"))
                .animation(law, value: hovered)
                .id("hover-row")
                .node
        }

        renders.render(row(false), animation: .none)
        let patch = renders.render(row(true), animation: .none)

        XCTAssertEqual(patch.transitions[.background]?.animation, law)
    }

    func testFreshApplicationAndDifferDoNotAnimateOrdinaryChanges() {
        XCTAssertEqual(ApplicationSession().animation, .none)

        let differ = Differ()
        let first = differ.reconcile(nil, with: panel(1))
        let changed = differ.reconcile(first.node, with: panel(0.25)).patch
        XCTAssertEqual(changed.props[.opacity], .number(0.25))
        XCTAssertNil(changed.transitions[.opacity])
    }

    /// A panel of a stated opacity, which is a number with a half-way.
    private func panel(_ opacity: Double, id: String = "panel") -> Node {
        ZStack { Text("x") }.opacity(opacity).id(id).node
    }

    // ---- What travels -------------------------------------------------------

    func testAChangedNumberTravelsAtTheApplicationsMotion() {
        let renders = Renders()

        renders.render(panel(1))
        let patch = renders.render(panel(0.25))

        let animation = patch.transitions[.opacity]
        XCTAssertEqual(patch.props[.opacity], .number(0.25), "the target rides as itself")
        XCTAssertEqual(animation?.animation, .standard)
    }

    func testTheApplicationSaysHowEverythingTravels() {
        let renders = Renders()
        let own = Animation.spring(milliseconds: 260, damping: 0.8)

        renders.render(panel(1), animation: own)
        let patch = renders.render(panel(0.25), animation: own)

        XCTAssertEqual(patch.transitions[.opacity]?.animation, own)
    }

    func testAColourTravels() {
        let renders = Renders()

        renders.render(ZStack { Text("x") }.background(Color("#000000")).id("b").node)
        let patch = renders.render(
            ZStack { Text("x") }.background(Color("#FFFFFF")).id("b").node)

        XCTAssertNotNil(patch.transitions[.background])
    }

    func testEdgesTravel() {
        let renders = Renders()

        renders.render(VStack { Text("x") }.contentPadding(EdgeInsets(4)).id("s").node)
        let patch = renders.render(VStack { Text("x") }.contentPadding(EdgeInsets(16)).id("s").node)

        XCTAssertNotNil(patch.transitions[.contentPadding])
    }

    // ---- What arrives instead ----------------------------------------------

    /// The first thing anyone sees is always the thing itself. An element being
    /// described for the first time has no "before" to travel from, so first
    /// render at target is a fact of the bytes rather than a rule the host has
    /// to work out.
    func testAFirstDescriptionCarriesNoMotion() {
        let renders = Renders()

        let patch = renders.render(panel(0.25))

        XCTAssertEqual(patch.props[.opacity], .number(0.25))
        XCTAssertTrue(patch.transitions.isEmpty)
    }

    /// A resync describes the whole tree to a host that may be holding nothing.
    /// There is no "before" on that side either.
    func testAResyncCarriesNoMotion() {
        let renders = Renders()

        renders.render(panel(1))
        let patch = renders.renderFromScratch(panel(0.25))

        XCTAssertEqual(patch.props[.opacity], .number(0.25))
        XCTAssertTrue(patch.transitions.isEmpty)
    }

    /// A control being built again cannot travel from what the last one showed.
    func testAReplacedElementCarriesNoMotion() {
        let renders = Renders()

        renders.render(panel(1))
        let patch = renders.render(Text("x").opacity(0.25).id("panel").node)

        XCTAssertTrue(patch.replace)
        XCTAssertTrue(patch.transitions.isEmpty)
    }

    func testAViewToldToStayStillDoesNot() {
        let renders = Renders()

        renders.render(ZStack { Text("x") }.opacity(1).animation(nil).id("p").node)
        let patch = renders.render(ZStack { Text("x") }.opacity(0.25).animation(nil).id("p").node)

        XCTAssertEqual(patch.props[.opacity], .number(0.25))
        XCTAssertTrue(patch.transitions.isEmpty)
    }

    /// One element's animation is that element's. Nothing in this library reaches
    /// down a tree.
    func testAMotionIsNotInherited() {
        let renders = Renders()

        func tree(_ opacity: Double) -> Node {
            VStack {
                ZStack { Text("x") }.opacity(opacity).id("inner")
            }
            .animation(nil)
            .id("outer")
            .node
        }

        renders.render(tree(1))
        let patch = renders.render(tree(0.25))

        XCTAssertNotNil(
            patch.child("inner")?.transitions[.opacity],
            "the child travels at the application's animation, not its parent's")
    }

    /// A modifier written ON a composed view is about that view, and a
    /// modifier that compiles, renders nothing and says nothing is the one
    /// failure this library refuses to ship.
    func testAMotionWrittenOnAComposedViewReachesWhatItIsMadeOf() {
        struct Panel: View {
            let fade: Double

            var body: some View {
                ZStack { Text("x") }.opacity(fade)
            }
        }

        let renders = Renders()

        renders.render(Panel(fade: 1).animation(nil).id("p").node)
        let patch = renders.render(Panel(fade: 0.25).animation(nil).id("p").node)

        XCTAssertEqual(patch.props[.opacity], .number(0.25))
        XCTAssertTrue(patch.transitions.isEmpty, "the view was told to stay still")
    }

    /// There is no half of a word.
    func testAValueWithNoHalfWayArrives() {
        let renders = Renders()

        renders.render(Text("one").id("l").node)
        let patch = renders.render(Text("two").id("l").node)

        XCTAssertEqual(patch.props[.text], .string("two"))
        XCTAssertTrue(patch.transitions.isEmpty)
    }

    /// Nothing walks a whole number: which tab, which item, which row.
    func testAPlaceOrACountNeverTravels() {
        let renders = Renders()

        renders.render(Text("x").gridRow(0).id("l").node)
        let patch = renders.render(Text("x").gridRow(3).id("l").node)

        XCTAssertEqual(patch.props[.gridRow], .number(3))
        XCTAssertTrue(patch.transitions.isEmpty)

        // EVERY ONE OF THEM, not just the one above. What this holds is that
        // the DIFFER honours the whole list rather than the one property a
        // test happened to write: taking the check out of the differ fails
        // here naming `maximumLength`, `gridRowSpan` and `position`.
        //
        // WHAT IT CANNOT HOLD is a member that stops saying so, since the
        // members are what it walks. That belongs to whoever changes one, and
        // `ElementProperty.travels` says so where it is declared.
        //
        // A NUMBER is what each is given, because a number is exactly the
        // value that would travel if the property were not on the list.
        for property in LibraryContracts.facts.filter({ !$0.value.travels }).keys.sorted() {
            let alone = Renders()

            alone.render(Text("x").setValue(property, .number(0)).id("l").node)

            let moved = alone.render(Text("x").setValue(property, .number(3)).id("l").node)

            XCTAssertEqual(
                moved.props[property], .number(3),
                "\(property.name) did not change at all, so this proves nothing")
            XCTAssertTrue(
                moved.transitions.isEmpty,
                "\(property.name) travelled, and no member that does not travel may")
        }
    }

    /// WHERE A CHILD SITS IS THE HOST'S, not a property's: a placement arrives
    /// and the LAYOUT carries the child from one place to the next. The values
    /// the author wrote on the same view travel as usual.
    func testAPlacementArrivesWhileTheRestOfTheViewTravels() {
        let renders = Renders()

        func row(_ y: Double, _ opacity: Double) -> Node {
            ZStack { Text("x") }
                .area(.absolute(0, y, 1, 40))
                .opacity(opacity)
                .id("row")
                .node
        }

        renders.render(row(0, 1))
        let patch = renders.render(row(80, 0.5))

        XCTAssertNil(patch.transitions[.area], "the placement arrives")
        XCTAssertNotNil(patch.transitions[.opacity], "what the author wrote travels")
    }

    /// A layout says how its children travel, and one that says nothing
    /// travels the way the application does - which is not in the patch at all.
    func testALayoutSaysHowItsChildrenTravelOnlyWhenItDiffers() {
        let renders = Renders()

        let plain = renders.render(VStack { Text("x") }.id("s").node)
        XCTAssertNil(plain.animation, "a layout that agrees says nothing")

        let told = renders.render(
            VStack { Text("x") }.animation(nil).id("s").node)

        XCTAssertEqual(told.animation?.animation, Animation.none)

        let back = renders.render(VStack { Text("x") }.id("s").node)

        XCTAssertEqual(
            back.animation?.animation, Animation.inherited,
            "and a layout that STOPS saying so has to be heard saying it")
    }

    /// A view that says nothing of its own says nothing in the patch: it
    /// travels the way the application does, and that is one number said once.
    func testAViewWithNoMotionOfItsOwnSaysNothing() {
        let renders = Renders()

        XCTAssertNil(renders.render(Text("x").id("l").node).animation)
    }

    /// A view that ANSWERS for itself says so, whatever it is - because what
    /// the host decides follows that answer: where it puts children, what a
    /// visual state changes, and whether showing and hiding crosses.
    func testAViewThatAnswersForItselfSaysSo() {
        let renders = Renders()

        XCTAssertEqual(
            renders.render(Text("x").animation(nil).id("l").node).animation?.animation,
            Animation.none)
    }

    /// A VISUAL STATE's values cross as the control's own: under the
    /// application's animation, and at once under `.animation(nil)`.
    func testAVisualStatesValuesTravelAsTheControlsOwn() {
        func button(_ enabled: Bool, still: Bool) -> Node {
            let base = Button("Save")
                .disabled(!enabled)
                .visualState(.disabled) { $0.background(Color("#CCCCCC")) }

            return (still ? AnyView(base.animation(nil)) : AnyView(base)).id("b").node
        }

        let travelling = Renders()
        travelling.render(button(true, still: false))
        let entered = travelling.render(button(false, still: false))
        XCTAssertEqual(entered.props["background"], Color("#CCCCCC").propValue)
        XCTAssertNotNil(entered.transitions["background"], "it crosses as the application's values do")

        let still = Renders()
        still.render(button(true, still: true))
        XCTAssertNil(still.render(button(false, still: true)).transitions["background"], "and at once under none")
    }

    // ---- Which values a animation is about --------------------------------------

    /// A animation may name WHICH values it is about, and the rest keep whatever
    /// they had. What a panel whose content changes shape wants: it crosses to
    /// its new place and takes its new size at once.
    func testAMotionMayNameWhichValuesItIsAbout() {
        let renders = Renders()

        func panel(_ width: Double, _ colour: Color) -> Node {
            ZStack { Text("x") }
                .frame(width: width)
                .background(colour)
                .animation(.none, .size)
                .id("p")
                .node
        }

        renders.render(panel(100, Color("#000000")))
        let patch = renders.render(panel(300, Color("#FFFFFF")))

        XCTAssertEqual(patch.props[.width], .number(300))
        XCTAssertNil(patch.transitions[.width], "the size arrives")
        XCTAssertNotNil(patch.transitions[.background], "the colour still travels")
    }

    /// And a rule may say a animation rather than none.
    func testARuleMaySayADifferentMotionRatherThanNone() {
        let renders = Renders()
        let own = Animation.spring(milliseconds: 240)

        func panel(_ fade: Double, _ width: Double) -> Node {
            ZStack { Text("x") }
                .opacity(fade)
                .animation(own, .opacity)
                .frame(width: width)
                .id("p")
                .node
        }

        renders.render(panel(1, 100))
        let patch = renders.render(panel(0.2, 300))

        XCTAssertEqual(patch.children.first?.transitions[.opacity]?.animation, own)
        XCTAssertEqual(patch.transitions[.width]?.animation, .standard,
                       "what no rule names travels the way everything else does")
    }

    /// The LAST rule that names a value is the one that answers for it, which
    /// is what a modifier written later means everywhere else here.
    func testTheLastRuleThatNamesAValueAnswersForIt() {
        let renders = Renders()

        func panel(_ width: Double) -> Node {
            ZStack { Text("x") }
                .frame(width: width)
                .animation(.none, .size)
                .animation(.eased(500), .width)
                .id("p")
                .node
        }

        renders.render(panel(100))
        let patch = renders.render(panel(300))

        XCTAssertEqual(patch.transitions[.width]?.animation, .eased(500))
    }

    /// A LAYOUT says which parts of a child's place travel, since a place is
    /// not a property and cannot carry a animation beside it.
    func testALayoutSaysWhichPartsOfAPlaceTravel() {
        let renders = Renders()

        let patch = renders.render(
            VStack { Text("x") }.animation(.none, .size).id("s").node)

        XCTAssertEqual(patch.lanes, .place, "the corner travels; the sides arrive")
    }

    // ---- A size somebody measures arrives ------------------------------------

    /// A layout whose frame is watched reports how big its room is, and a size
    /// worked out from that report is the LAYOUT's answer: travelling through
    /// it would lay the page out at sizes nobody chose, growing from nothing.
    /// So a child's size arrives there, where the same change travels in a
    /// room nobody measures.
    func testASizeInsideAMeasuredLayoutArrives() {
        let renders = Renders()

        func room(_ width: Double) -> Node {
            VStack { ZStack { Text("x") }.frame(width: width).id("held") }
                .onFrameChanged { _ in }
                .id("room")
                .node
        }

        renders.render(room(0))
        let patch = renders.render(room(300))

        XCTAssertEqual(patch.child("held")?.props[.width], .number(300))
        XCTAssertNil(patch.child("held")?.transitions[.width], "the measured room's child takes its size at once")
    }

    func testASizeInARoomNobodyMeasuresStillTravels() {
        let renders = Renders()

        func room(_ width: Double) -> Node {
            VStack { ZStack { Text("x") }.frame(width: width).id("held") }.id("room").node
        }

        renders.render(room(0))
        let patch = renders.render(room(300))

        XCTAssertEqual(patch.child("held")?.transitions[.width]?.animation, .standard)
    }

    /// A view that reports its own frame takes a new size at once: what it
    /// reports is what it holds, arranged in that size.
    func testAViewWhoseOwnFrameIsWatchedTakesItsSizeAtOnce() {
        let renders = Renders()

        func panel(_ height: Double) -> Node {
            ZStack { Text("x") }.frame(height: height).onFrameChanged { _ in }.id("p").node
        }

        renders.render(panel(40))
        let patch = renders.render(panel(80))

        XCTAssertEqual(patch.props[.height], .number(80))
        XCTAssertNil(patch.transitions[.height])
    }

    /// Where ANY child of a layout is measured, none of that layout's children
    /// is carried through a size: what the measured one reports is what the
    /// views beside it leave it.
    func testAMeasuredChildMakesItsSiblingsSizesArrive() {
        let renders = Renders()

        func room(_ width: Double) -> Node {
            VStack {
                Text("measured").onFrameChanged { _ in }
                ZStack { Text("x") }.frame(width: width).id("beside")
            }
            .id("room")
            .node
        }

        renders.render(room(100))
        let patch = renders.render(room(200))

        XCTAssertNil(patch.child("beside")?.transitions[.width])
    }

    /// And such a layout says so for the places it works out: its children's
    /// corners travel, their sides arrive.
    func testAMeasuredLayoutsChildrenTravelOnlyByTheirPlace() {
        let renders = Renders()

        let patch = renders.render(VStack { Text("x") }.onFrameChanged { _ in }.id("s").node)

        XCTAssertEqual(patch.lanes, .place)
    }

    /// A gradient is the same picture in different colours, so it crosses -
    /// which is what keeps a color scheme change uniform.
    func testAGradientTravels() {
        let renders = Renders()

        func panel(_ from: Color) -> Node {
            VStack { Text("x") }
                .background(.linearGradient([
                    GradientStop(from, 0),
                    GradientStop(Color("#FFFFFF"), 1),
                ]))
                .id("p")
                .node
        }

        renders.render(panel(Color("#000000")))
        let patch = renders.render(panel(Color("#FF0000")))

        XCTAssertNotNil(patch.transitions[.background])
    }

    // ---- A write of its own -------------------------------------------------

    /// A DRAG LANDS, AND AN ASSIGNMENT TRAVELS - the rule a two-way input
    /// keeps now that the host carries what it borrows.
    ///
    /// A drag is the HOST's write onto the journey's value and destination
    /// together, so nothing is left to travel and the state reads the thumb
    /// where the finger put it. An author's own write to the same state moves
    /// the destination alone, and the host walks the thumb there under the
    /// element's law - which is the one difference between a report and an
    /// assignment, and it is a fact of the lanes rather than of a mark.
    func testADraggedSliderWritesItsReportBackWithoutTravelling() {
        let volume = State(wrappedValue: 0.5)
        let renders = Renders()

        renders.render(Slider(volume.projectedValue).id("s").node)

        let board = Renderer.shared.board(of: volume.image)
        board.cycle(now: 0, reducesMotion: false)
        _ = board.dirty()

        dragged(volume.number, to: 0.7)
        board.cycle(now: 16, reducesMotion: false)

        XCTAssertEqual(volume.wrappedValue, 0.7, "the report was written back")
        XCTAssertTrue(board.dirty().isEmpty, "and nothing was left to travel")

        volume.wrappedValue = 1
        board.cycle(now: 32, reducesMotion: false)

        let sent = board.dirty().first { $0.number == volume.number }

        XCTAssertNotNil(sent, "an assignment crosses")
        XCTAssertNotEqual(sent.map { $0.mask & JourneyLanes<Double>.mask(of: .destination) }, 0,
                          "as a destination, for the host to walk the thumb to")
        XCTAssertEqual(sent.map { $0.mask & JourneyLanes<Double>.mask(of: .value) }, 0,
                       "and not as a value put there at once")
    }

    /// A `Stepper` is the other control the host walks for a plain `Double`,
    /// and it answers the same way - so the guard covers both of them rather
    /// than the one that happened to be written first.
    func testASteppedValueIsWrittenBackWithoutTravelling() {
        let servings = State(wrappedValue: 2.0)
        let renders = Renders()

        renders.render(Stepper(servings.projectedValue).id("s").node)

        let board = Renderer.shared.board(of: servings.image)
        board.cycle(now: 0, reducesMotion: false)
        _ = board.dirty()

        dragged(servings.number, to: 3)
        board.cycle(now: 16, reducesMotion: false)

        XCTAssertEqual(servings.wrappedValue, 3, "the report was written back")
        XCTAssertTrue(board.dirty().isEmpty, "and nothing was left to travel")
    }

    // ---- One transform, about the view's own centre -------------------------

    /// ONE TRANSFORM, HAPPENING IN THE ORDER IT IS WRITTEN. Each part is done
    /// to what the parts before it made - so a move written BEFORE a turn is
    /// swung round by it, and one written after is not - and all of the
    /// arithmetic is SwiftOmniUI's, so the chain is the same numbers and the
    /// same picture on every platform. What comes out is five plain
    /// properties: a rotation, two translations and two scales.
    func testATransformHappensInTheOrderItIsWritten() throws {
        let renders = Renders()

        func tree(_ built: ViewTransform) -> Node {
            stack([Text("x").transformEffect(built).id("one").node], id: "root")
        }

        let one = renders.render(tree(.rotate(90).translate(100, 0)))
        let props = try XCTUnwrap(one.child("one")?.props)

        // The move came AFTER the turn, so it is a plain hundred to the right.
        XCTAssertEqual(props[.rotation]?.number ?? 0, 90, accuracy: 0.000001)
        XCTAssertEqual(props[.translationX]?.number ?? 0, 100, accuracy: 0.000001)
        XCTAssertEqual(props[.translationY]?.number ?? 1, 0, accuracy: 0.000001)
        XCTAssertEqual(props[.scaleX]?.number ?? 0, 1, accuracy: 0.000001)
        XCTAssertEqual(props[.scaleY]?.number ?? 0, 1, accuracy: 0.000001)

        // Written first, the same move is swung round by the turn - and grown
        // by a sizing after it, because each part happens to the whole of what
        // came before.
        let other = Renders()
            .render(tree(.translate(100, 0).rotate(90).scale(2)))
        let swung = try XCTUnwrap(other.child("one")?.props)

        XCTAssertEqual(swung[.rotation]?.number ?? 0, 90, accuracy: 0.000001)
        XCTAssertEqual(swung[.translationX]?.number ?? 1, 0, accuracy: 0.000001)
        XCTAssertEqual(swung[.translationY]?.number ?? 0, 200, accuracy: 0.000001)
        XCTAssertEqual(swung[.scaleX]?.number ?? 0, 2, accuracy: 0.000001)
        XCTAssertEqual(swung[.scaleY]?.number ?? 0, 2, accuracy: 0.000001)
    }

    /// A CHANGED TRANSFORM TRAVELS: what it writes is five ordinary
    /// interpolable properties, so the differ gives each changed one a
    /// transitions entry like any other value - lane by lane, at the
    /// application's animation.
    func testAChangedTransformTravels() throws {
        let renders = Renders()

        func tree(_ built: ViewTransform) -> Node {
            stack([Text("x").transformEffect(built).id("one").node], id: "root")
        }

        renders.render(tree(.identity))
        let patch = try XCTUnwrap(renders.render(tree(.rotate(45).scale(2))).child("one"))

        for prop in [Prop.rotation, .scaleX, .scaleY] {
            let travel = patch.transitions[prop]
            XCTAssertEqual(travel?.animation, .standard, "\(prop) travels")
        }

        // The moves did not change, so they are not on the message at all.
        XCTAssertNil(patch.props[.translationX])
        XCTAssertNil(patch.transitions[.translationX])
    }

    /// THE ONE CHAIN THE FIVE PROPERTIES CANNOT CARRY WHOLE is a one-axis
    /// sizing of a view turned EARLIER, which slants it into a parallelogram
    /// no platform here has a property to draw. The turn, the move and both
    /// sizes are kept; the slant alone is left out - and this test is the
    /// statement of that limit.
    func testAOneAxisSizingOfATurnedViewKeepsEverythingButTheSlant() throws {
        let renders = Renders()

        let patch = renders.render(stack([
            Text("x").transformEffect(.rotate(45).scaleX(2)).id("one").node,
        ], id: "root"))

        let props = try XCTUnwrap(patch.child("one")?.props)

        // The across axis of the turned view, doubled: its direction is what
        // the rotation reads back, its length the width.
        XCTAssertEqual(props[.rotation]?.number ?? 0, 26.5650511770780, accuracy: 0.000001)
        XCTAssertEqual(props[.scaleX]?.number ?? 0, 1.5811388300842, accuracy: 0.000001)
        XCTAssertEqual(props[.scaleY]?.number ?? 0, 1.2649110640674, accuracy: 0.000001)
    }

    /// EVERY PART IS ALSO A STARTING POINT, and it has to mean the same thing
    /// as the part written onto a view as it was drawn - seven one-line statics
    /// beside seven instance methods of the same names being exactly where a
    /// `scaleX` delegating to `scaleY` would sit unnoticed.
    func testAPartWrittenFirstIsThePartWrittenOnAViewAsItWasDrawn() {
        let plain = ViewTransform.identity

        XCTAssertEqual(ViewTransform.translate(10, 20), plain.translate(10, 20))
        XCTAssertEqual(ViewTransform.rotate(14), plain.rotate(14))
        XCTAssertEqual(ViewTransform.scale(0.5), plain.scale(0.5))
        XCTAssertEqual(ViewTransform.scaleX(0.5), plain.scaleX(0.5))
        XCTAssertEqual(ViewTransform.scaleY(0.5), plain.scaleY(0.5))
        XCTAssertEqual(ViewTransform.turn(40), plain.turn(40))
        XCTAssertEqual(ViewTransform.tilt(40), plain.tilt(40))

        // And the two sizings are about different sides, which is the mistake
        // the check above exists to catch.
        XCTAssertNotEqual(ViewTransform.scaleX(0.5), ViewTransform.scaleY(0.5))
        XCTAssertNotEqual(ViewTransform.turn(40), ViewTransform.tilt(40))
    }

    /// A TURN IS DRAWN FLAT, and that is what makes it mean the same picture
    /// everywhere: a rectangle turned by an angle is a rectangle cos(angle) as
    /// wide. `.rotationY` is the other reading of a turn, and every platform
    /// projects that one through a camera it chooses for itself.
    func testATurnIsWhatATurnedRectangleLooksLike() {
        let renders = Renders()

        let patch = renders.render(stack([
            Text("x").transformEffect(.turn(60).tilt(60)).id("one").node,
        ], id: "root"))

        let props = patch.child("one")?.props

        XCTAssertEqual(props?[.scaleX]?.number ?? 0, 0.5, accuracy: 0.0005)
        XCTAssertEqual(props?[.scaleY]?.number ?? 0, 0.5, accuracy: 0.0005)

        // Past its own edge a view is showing its back, which is not a picture
        // this can make - so the turn stops there rather than folding through.
        let past = Renders().render(stack([
            Text("x").transformEffect(.turn(200)).id("one").node,
        ], id: "root"))

        XCTAssertEqual(past.child("one")?.props[.scaleX]?.number ?? 1, 0, accuracy: 0.0005)
    }

    // ---- A layout of the author's own ---------------------------------------

    func testAPlacedLayoutSaysHowItsViewsTravel() {
        let renders = Renders()

        let run = State(wrappedValue: PlacedRun())

        func tree(_ still: Bool) -> Node {
            let fan = PlacedLayout([1], id: \.self) { number in
                Text("\(number)")
            }
            .placement(run.projectedValue)

            return (still ? fan.animation(nil) : fan).id("fan").node
        }

        func layout(_ patch: HostPatch) -> HostPatch? {
            if patch.type == .zStack { return patch }

            for child in patch.children {
                if let found = layout(child) { return found }
            }

            return nil
        }

        XCTAssertEqual(layout(renders.render(tree(true)))?.animation?.animation, Animation.none)
    }

    // ---- The patch ----------------------------------------------------------

    /// THE ORDINARY CASE. A value that simply changed is the animation almost
    /// every animation in an application is - nobody started it and nobody waits
    /// for it.
    ///
    /// Two renders, because a animation is what a CONTINUING element does: the
    /// first describes the panel and carries none, the second changes one
    /// number and carries the walk to it - that number, its one transition
    /// at the application's animation, and nothing else.
    func testAValueThatTravelsCarriesItsWalkAndNothingElse() {
        let differ = Differ()
        differ.animation = .standard

        let first = differ.reconcile(nil, with: panel(1))
        XCTAssertEqual(first.patch.props["opacity"], .number(1))
        XCTAssertTrue(first.patch.subtree.allSatisfy(\.transitions.isEmpty), "a new element travels nowhere")

        let moved = differ.reconcile(first.node, with: panel(0.25)).patch
        XCTAssertEqual(moved.props, ["opacity": .number(0.25)])
        XCTAssertEqual(moved.transitions, ["opacity": HostTransition(animation: .standard)])
        XCTAssertTrue(moved.children.isEmpty, "the label under it says nothing")
    }

    // ---- The vocabulary itself ---------------------------------------------

    func testTheLawsCarryTheNumbersTheyNeed() {
        XCTAssertEqual(Animation.eased(400, .cubicIn).millis, 400)
        XCTAssertEqual(Animation.eased(400, .cubicIn).curve, .cubicIn)

        XCTAssertEqual(Animation.spring(milliseconds: 260, damping: 0.7).millis, 260)
        XCTAssertEqual(Animation.spring(milliseconds: 260, damping: 0.7).factor, 0.7)
    }

    func testNoMotionIsNothingAndInheritedResolves() {
        XCTAssertTrue(Animation.none.isNothing)
        XCTAssertFalse(Animation.standard.isNothing)

        XCTAssertEqual(Animation.inherited.resolved(against: .standard), .standard)
        XCTAssertEqual(Animation.eased(50).resolved(against: .standard), .eased(50))
    }

    /// A spring's damping is bought deliberately and never given away: half a
    /// card's worth of wobble is what a user reads as a mistake.
    func testASpringDoesNotOvershootUnlessItIsAskedTo() {
        XCTAssertEqual(Animation.spring().factor, 1)

        // ASKED TO: damping under one is what overshoot IS, and the floor is
        // 0.05 rather than nought - a spring with no damping at all never
        // arrives.
        XCTAssertEqual(Animation.spring(milliseconds: 240, damping: 0.4).factor, 0.4)
        XCTAssertEqual(Animation.spring(milliseconds: 240, damping: 0).factor, 0.05)
    }
}
