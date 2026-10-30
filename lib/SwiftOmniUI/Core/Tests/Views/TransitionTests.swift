// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// How a view arrives and goes: `.transition` writes the `AnyTransition` the
// element was described with, and the type crosses as the contract's value.

import XCTest
@_spi(Host) @testable import SwiftOmniUICore

@MainActor final class TransitionTests: XCTestCase {
    private func transition(_ view: some View) -> AnyTransition? {
        view.node.built.props["transition"].flatMap(AnyTransition.init(propValue:))
    }

    func testATransitionTravelsAsTheContractValue() throws {
        let crossed = try XCTUnwrap(transition(Text("x").transition(.blur)))
        XCTAssertEqual(crossed, .blur)
    }

    /// The SCE spellings: a blur over an offset, and the identity.
    func testTheSpellingsTheEditorUses() throws {
        XCTAssertEqual(
            transition(Text("x").transition(.blur.combined(with: .offset(x: -48, y: 80)))),
            AnyTransition.blur.combined(with: .offset(x: -48, y: 80)))
        XCTAssertEqual(transition(Text("x").transition(.identity)), .identity)
    }

    /// Every spelling the host may meet comes back from the wire as itself.
    func testEverySpellingComesBackAsItself() {
        let spellings: [AnyTransition] = [
            .identity, .opacity, .blur, .slide,
            .offset(x: -48, y: 80), .offset(Point(3, 4)),
            .scale(scale: 0.8), .scale(scale: 0.8, anchor: .top),
            .scale(x: 0.5, y: 2, anchor: .bottomLeading), .scale(anchor: .trailing),
            .move(edge: .leading), .move(edge: .trailing), .move(edge: .top), .move(edge: .bottom),
            .blur.combined(with: .scale(scale: 0.8)),
            .asymmetric(insertion: .offset(y: -48), removal: .opacity),
            .blur.animation(.bouncy),
        ]

        for spelling in spellings {
            XCTAssertEqual(
                AnyTransition(propValue: spelling.propValue), spelling, "\(spelling) does not come back")
        }
    }

    /// A combined transition's phases hold the parts both halves name.
    func testCombinedHoldsBothHalves() {
        let transition = AnyTransition.opacity.combined(with: .offset(y: 12))
        XCTAssertEqual(transition.insertion.opacity, 0)
        XCTAssertEqual(transition.insertion.offset, Point(0, 12))
        XCTAssertEqual(transition.removal.offset, Point(0, 12))
    }

    /// `.animation(_:)` names the crossing's law over the layout's.
    func testAnimationNamesTheLaw() throws {
        let transition = try XCTUnwrap(transition(Text("x").transition(.blur.animation(.bouncy))))
        XCTAssertEqual(transition.animation, .bouncy)
        XCTAssertEqual(transition.insertion.blur, 8)
    }

    /// `.modifier(active:identity:)` reads the properties the two modifiers
    /// write differently and crosses those - the SCE spellings: a blur pair
    /// and an uneven scale.
    func testAModifierCrossesWhatThePairWritesDifferently() throws {
        struct BlurPair: ViewModifier {
            var on: Bool
            func body(content: Content) -> some View {
                content.blur(radius: on ? 12 : 0)
            }
        }
        struct ScalePair: ViewModifier {
            var x: Double
            var y: Double
            func body(content: Content) -> some View {
                content.scaleEffect(x: x, y: y, anchor: .bottomLeading)
            }
        }

        let blurred = AnyTransition.modifier(active: BlurPair(on: true), identity: BlurPair(on: false))
        XCTAssertEqual(blurred.insertion.blur, 12)

        // What the pair writes alike - the x it keeps, the pivot it shares -
        // is no delta at all.
        let scaled = AnyTransition.modifier(
            active: ScalePair(x: 1, y: 0.6), identity: ScalePair(x: 1, y: 1))
        XCTAssertNil(scaled.insertion.scaleX)
        XCTAssertEqual(scaled.insertion.scaleY, 0.6)
        XCTAssertNil(scaled.insertion.pivot)
        XCTAssertEqual(scaled.removal.scaleY, 0.6)

        let crossed = try XCTUnwrap(transition(Text("x").transition(blurred)))
        XCTAssertEqual(crossed.insertion.blur, 12)
    }

    /// A property no phase can cross - padding's room, say - stays; the pair
    /// differing only there reads as the identity.
    func testAComposingModifierDescribesNoDelta() {
        struct Spaced: ViewModifier {
            var room: Double
            func body(content: Content) -> some View {
                content.padding(room)
            }
        }

        XCTAssertEqual(
            AnyTransition.modifier(active: Spaced(room: 20), identity: Spaced(room: 4)), .identity)
    }
}
