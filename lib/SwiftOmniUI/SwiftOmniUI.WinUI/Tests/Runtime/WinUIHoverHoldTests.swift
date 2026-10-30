// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) @testable import SwiftOmniUICore
@_spi(Host) @testable import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import SwiftOmniUIConformance
import XCTest

/// A row that turns dark under the pointer and offers a menu, as a list's row does.
private struct HoverRowPage: View {
    @State private var hovered = false

    var body: some View {
        VStack {
            ZStack { Text("Row") }
                .frame(width: 200, height: 40)
                .background(hovered ? Color.black : Color.clear)
                .onHover { hovered = $0 }
                .contextMenu { MenuItem("Open") }
                .id("hover-row")
        }
        .frame(width: 300)
        .horizontalAlignment(.start)
        .verticalAlignment(.start)
    }
}

/// A page whose anchor presents a popover, its card holding a row of its own with a menu on it: what stands in a
/// popup, and what a popup opened from inside it stands over.
private struct HoverCardPage: View {
    @State private var showing = true
    @State private var cardRowHovered = false

    var body: some View {
        VStack {
            ZStack { Text("Anchor") }
                .frame(width: 200, height: 40)
                .popover(isPresented: $showing) {
                    ZStack { Text("Card Row") }
                        .frame(width: 200, height: 40)
                        .background(cardRowHovered ? Color.black : Color.clear)
                        .onHover { cardRowHovered = $0 }
                        .contextMenu { MenuItem("Open") }
                        .id("card-row")
                }
                .id("anchor")
        }
        .frame(width: 300)
        .horizontalAlignment(.start)
        .verticalAlignment(.start)
    }
}

/// A card that offers a menu, with a row of its own inside it that hears the pointer: what a menu over the card does
/// to a view inside the view it hangs off, rather than to that view itself.
private struct HoverMenuOverTheCardPage: View {
    @State private var hovered = false

    var body: some View {
        VStack {
            VStack {
                ZStack { Text("Row") }
                    .frame(width: 200, height: 40)
                    .background(hovered ? Color.black : Color.clear)
                    .onHover { hovered = $0 }
                    .id("inner-row")
            }
            .contextMenu { MenuItem("Open") }
            .id("outer")
        }
        .frame(width: 300)
        .horizontalAlignment(.start)
        .verticalAlignment(.start)
    }
}

/// What a popup standing over the pointer does to the hover of the layer it opens above: the exit WinUI tells is held
/// while a popup stands over the view, and a popup going takes the truth again from where the pointer is. What stands
/// in a popup is what the pointer is on, so it hears the pointer's own exits, and a popup opened from inside a card
/// stands over the card's own views as well. What a popup holds is what its own content stands in, so a menu holds
/// every view inside the view it hangs off, and not only that view itself.
/// Design: docs/design/platforms/winui/input.md#a-popup-over-the-pointer
final class WinUIHoverHoldTests: XCTestCase {
    /// A place of the test window's content that is on the row, and one that is past it.
    private static let onTheRow = Point(x: 5, y: 5)
    private static let pastTheRow = Point(x: 5, y: 400)

    /// Runs `body` over the page's row under the pointer with a popup standing over it - entered, the popup open, the
    /// exit WinUI told it - with the pointer's own place answered as `place` while it stands.
    @MainActor
    private static func withARowUnderAPopup(
        pointerAt place: Point, _ body: @MainActor (MountedElement, WinUIView) throws -> Void
    ) throws {
        defer { WinUIHoverHold.pointerPlace = WinUIHoverHold.livePointerPlace }
        let host = WinUIRenderer.running(clock: TestClock()) { HoverRowPage() }
        let element = try XCTUnwrap(host.runtime.tree.root?.first(id: .manual("hover-row")))
        let row = try XCTUnwrap(host.view(id: element.id))
        // The places below are the window content's, and the page stands at its top left.
        XCTAssertTrue(
            swiftomniui_winui_content_reaches(row.handle, Self.onTheRow.x, Self.onTheRow.y),
            "the row stands at the content's top left")
        XCTAssertFalse(
            swiftomniui_winui_content_reaches(row.handle, Self.pastTheRow.x, Self.pastTheRow.y),
            "the content past the row is not the row")
        WinUIHoverHold.pointerPlace = { _ in place }

        row.heard(.pointer(.pointerEntered, .zero))
        XCTAssertEqual(element.value(.background), Color.black.propValue)
        WinUIHoverHold.began(row)
        XCTAssertTrue(WinUIHoverHold.standsOver(row), "the menu the row presents stands over the row")
        row.heard(.pointer(.pointerExited, .zero))
        XCTAssertEqual(WinUIHoverHold.holding, 1, "an exit under a popup is held, not delivered")
        XCTAssertEqual(element.value(.background), Color.black.propValue, "a popup took the pointer, not the row")

        try body(element, row)
    }

    /// The popup going with the pointer still on the row leaves its hover alone: the core was never told the pointer
    /// left, so the view keeps what it has.
    func testTheHoverStaysWhenThePopupGoesWithThePointerStillOnTheRow() throws {
        try onUIThread {
            try Self.withARowUnderAPopup(pointerAt: Self.onTheRow) { element, row in
                WinUIHoverHold.ended(row)
                XCTAssertEqual(element.value(.background), Color.black.propValue)
                XCTAssertEqual(WinUIHoverHold.holding, 0)
            }
        }
    }

    /// The popup going with the pointer away from the row hands it the exit it was owed.
    func testTheHoverGoesWhenThePopupGoesWithThePointerAway() throws {
        try onUIThread {
            try Self.withARowUnderAPopup(pointerAt: Self.pastTheRow) { element, row in
                WinUIHoverHold.ended(row)
                XCTAssertEqual(element.value(.background), Color.clear.propValue)
                XCTAssertEqual(WinUIHoverHold.holding, 0)
            }
        }
    }

    /// A row that left the tree while its popup stood is let go of: it is owed nothing, and nothing is called into it
    /// when the popup goes.
    func testARowThatLeftTheTreeWhileItsPopupStoodIsLetGoOf() throws {
        try onUIThread {
            try Self.withARowUnderAPopup(pointerAt: Self.pastTheRow) { _, row in
                row.detach()
                XCTAssertEqual(WinUIHoverHold.holding, 0, "a view that left is owed nothing")
                WinUIHoverHold.ended(row)
                XCTAssertEqual(WinUIHoverHold.holding, 0)
            }
        }
    }

    /// A pointer coming back on the row while the popup stands drops what was withheld: the view's hover never left
    /// either, so nothing is owed it when the popup goes.
    func testThePointerComingBackDropsWhatWasWithheld() throws {
        try onUIThread {
            try Self.withARowUnderAPopup(pointerAt: Self.pastTheRow) { element, row in
                row.heard(.pointer(.pointerEntered, .zero))
                XCTAssertEqual(WinUIHoverHold.holding, 0)
                XCTAssertEqual(element.value(.background), Color.black.propValue)
                WinUIHoverHold.ended(row)
                XCTAssertEqual(element.value(.background), Color.black.propValue, "the pointer is on the row")
            }
        }
    }

    /// What stands in a popup is on the popup, not under it: the exits WinUI tells a card's own row while the card
    /// stands are the pointer's own, and are delivered.
    func testARowInsideTheCardHearsThePointersOwnExits() throws {
        try onUIThread {
            let host = WinUIRenderer.running(clock: TestClock()) { HoverCardPage() }
            let popover = try XCTUnwrap(host.views(WinUIPopoverView.self).first, "the card is a view of the tree")
            let element = try XCTUnwrap(host.runtime.tree.root?.first(id: .manual("card-row")))
            let cardRow = try XCTUnwrap(host.view(id: element.id), "the card's row is a view of the tree")

            WinUIHoverHold.began(popover)
            XCTAssertFalse(
                WinUIHoverHold.standsOver(cardRow), "the card stands over the page, not over its own row")
            cardRow.heard(.pointer(.pointerEntered, .zero))
            XCTAssertEqual(element.value(.background), Color.black.propValue)
            cardRow.heard(.pointer(.pointerExited, .zero))
            XCTAssertEqual(WinUIHoverHold.holding, 0, "the card's own row is what the pointer is on")
            XCTAssertEqual(element.value(.background), Color.clear.propValue)
            WinUIHoverHold.ended(popover)
        }
    }

    /// A popup opened from inside a card stands over the card's own rows: the exit it caused is held while it stands,
    /// and its going settles them there and then, with the card still standing.
    func testAPopupInsideTheCardHoldsTheCardsRows() throws {
        try onUIThread {
            defer { WinUIHoverHold.pointerPlace = WinUIHoverHold.livePointerPlace }
            let host = WinUIRenderer.running(clock: TestClock()) { HoverCardPage() }
            let popover = try XCTUnwrap(host.views(WinUIPopoverView.self).first, "the card is a view of the tree")
            let element = try XCTUnwrap(host.runtime.tree.root?.first(id: .manual("card-row")))
            let cardRow = try XCTUnwrap(host.view(id: element.id), "the card's row is a view of the tree")
            WinUIHoverHold.pointerPlace = { _ in Self.pastTheRow }

            WinUIHoverHold.began(popover)
            XCTAssertFalse(WinUIHoverHold.standsOver(cardRow), "the card holds its own row")
            cardRow.heard(.pointer(.pointerEntered, .zero))
            XCTAssertEqual(element.value(.background), Color.black.propValue)

            WinUIHoverHold.began(cardRow)
            XCTAssertTrue(WinUIHoverHold.standsOver(cardRow), "the menu the row presents stands over the row")
            cardRow.heard(.pointer(.pointerExited, .zero))
            XCTAssertEqual(WinUIHoverHold.holding, 1, "the menu over the card's row holds it")
            XCTAssertEqual(element.value(.background), Color.black.propValue)

            WinUIHoverHold.ended(cardRow)
            XCTAssertFalse(WinUIHoverHold.standsOver(cardRow), "the menu went, and the card does not hold the row")
            XCTAssertEqual(WinUIHoverHold.holding, 0, "the menu going settles the row while the card stands")
            XCTAssertEqual(element.value(.background), Color.clear.propValue, "the pointer is past the row")
            WinUIHoverHold.ended(popover)
        }
    }

    /// A menu holds the views inside the view it hangs off, not only that view: the row inside the card is no view of
    /// the menu's own, and its exit is held all the same.
    func testAMenuHoldsTheRowsInsideTheViewItHangsOff() throws {
        try onUIThread {
            defer { WinUIHoverHold.pointerPlace = WinUIHoverHold.livePointerPlace }
            let host = WinUIRenderer.running(clock: TestClock()) { HoverMenuOverTheCardPage() }
            let element = try XCTUnwrap(host.runtime.tree.root?.first(id: .manual("inner-row")))
            let row = try XCTUnwrap(host.view(id: element.id), "the row inside the card is a view of the tree")
            let outer = try XCTUnwrap(
                host.runtime.tree.root?.first(id: .manual("outer")).flatMap { host.view(id: $0.id) },
                "the view the menu hangs off is a view of the tree")
            WinUIHoverHold.pointerPlace = { _ in Self.pastTheRow }

            row.heard(.pointer(.pointerEntered, .zero))
            XCTAssertEqual(element.value(.background), Color.black.propValue)

            WinUIHoverHold.began(outer)
            XCTAssertTrue(WinUIHoverHold.standsOver(row), "the menu over the card holds the card's own row")
            row.heard(.pointer(.pointerExited, .zero))
            XCTAssertEqual(
                WinUIHoverHold.holding, 1, "the row under the menu is owed its exit, though it is no view of the menu")
            XCTAssertEqual(element.value(.background), Color.black.propValue)

            WinUIHoverHold.ended(outer)
            XCTAssertEqual(WinUIHoverHold.holding, 0)
            XCTAssertEqual(element.value(.background), Color.clear.propValue, "the pointer is past the row")
        }
    }
}
