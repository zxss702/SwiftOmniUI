// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// A popover hanging off the view itself.
//
// `.popover` writes a child slot carrying the card, drives `isPresented`
// both ways - write `true` to open, the user's dismissal writes `false`
// back - and prefers an edge for its arrow.

import XCTest
@_spi(Host) @testable import SwiftOmniUICore

@MainActor final class PopoverTests: XCTestCase {
    /// Touches the shared renderer, whose init installs the UI thread's
    /// executor before any task of this suite can be made - see UIThread.swift.
    override func setUp() {
        super.setUp()
        Renderer.shared.clearInvalidation()
    }

    @State private var shown = true

    private func popover(_ view: some View) -> Node? {
        view.node.built.children.first { $0.type == "Popover" }
    }

    func testAPopoverTravelsAsASlotWithItsCardInside() throws {
        let card = try XCTUnwrap(popover(Text("anchor")
            .popover(isPresented: $shown, arrowEdge: .bottom) { Text("card") }))

        XCTAssertEqual(card.children.map { $0.type }, ["Text"])
        XCTAssertEqual(card.children.first?.props["text"], .string("card"))
    }

    /// The edge the arrow prefers crosses as the contract's `Edge`, read back
    /// as the type it was written.
    func testTheArrowEdgeCrossesAsTheEdgesOwnValue() throws {
        let card = try XCTUnwrap(popover(Text("anchor")
            .popover(isPresented: $shown, arrowEdge: .trailing) { Text("card") }))

        XCTAssertEqual(card.props[.arrowEdge], Edge.trailing.propValue)

        let adjusted = Popover(isPresented: $shown, arrowEdge: .top) { Text("card") }.arrowEdge(.leading)
        XCTAssertEqual(adjusted.node.props[.arrowEdge], Edge.leading.propValue)

    }

    /// The member modifiers write and drive `isOpen` like the modifier does.
    func testTheMembersWriteAndDriveIsOpen() throws {
        let closed = Popover(isPresented: $shown, arrowEdge: .top) { Text("card") }.isOpen(false)
        XCTAssertEqual(closed.node.props[.isOpen], Bool(false).propValue)

        let driven = Popover(isPresented: $shown, arrowEdge: .top) { Text("card") }.isOpen($shown)
        XCTAssertNotNil(driven.node.driven[.isOpen])
    }

    /// `isPresented` is DRIVEN, not written: the host holds the binding's
    /// number and writes each change through it.
    func testIsPresentedIsDrivenBothWays() throws {
        let card = try XCTUnwrap(popover(Text("anchor")
            .popover(isPresented: $shown) { Text("card") }))

        XCTAssertNotNil(card.driven[.isOpen], "the host drives the popover open and shut")
    }

    /// The user taking the popover away writes `false` into the binding -
    /// the slot's `dismissed` handler, which every host calls as the
    /// platform's popover closes.
    func testADismissalWritesTheBindingFalse() async throws {
        shown = true
        let card = try XCTUnwrap(popover(Text("anchor")
            .popover(isPresented: $shown) { Text("card") }))
        let handler = try XCTUnwrap(card.events[.dismissed])

        try await handler()

        XCTAssertFalse(shown, "a dismissal the user made writes the binding false")
    }

    /// `@Environment(\.dismiss)` inside the card resolves to its own closer -
    /// what a `dismiss()` in popover content runs.
    func testTheCardDismissesItselfThroughTheEnvironment() throws {
        shown = true
        let card = try XCTUnwrap(popover(Text("anchor")
            .popover(isPresented: $shown) { Text("card") }))
        let dismiss = card.environmentValues[keyPath: \.dismiss]

        dismiss()

        XCTAssertFalse(shown, "the card's own `dismiss()` writes the binding false")
    }
}
