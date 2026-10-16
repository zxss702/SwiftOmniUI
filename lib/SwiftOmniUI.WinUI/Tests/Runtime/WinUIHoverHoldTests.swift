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
                .background(hovered.wrappedValue ? Color.black : Color.clear)
                .onHover { hovered.wrappedValue = $0 }
                .contextMenu { MenuItem("Open") }
                .id("hover-row")
        }
        .frame(width: 300)
        .horizontalAlignment(.start)
        .verticalAlignment(.start)
    }
}

/// What a popup standing over the pointer does to the hover of what it covers: the exit WinUI tells is held while it
/// stands, and when the last one goes the truth is taken again from where the pointer is.
/// Design: docs/design/platforms/winui/input.md#a-popup-over-the-pointer
final class WinUIHoverHoldTests: XCTestCase {
    /// A place of the test window's content that is on the row, and one that is past it.
    private static let onTheRow = Point(x: 5, y: 5)
    private static let pastTheRow = Point(x: 5, y: 400)

    /// Runs `body` over the page's row under the pointer with a popup standing over it - entered, the popup open, the
    /// exit WinUI told it - with the pointer's own place answered as `place` while it stands.
    @MainActor
    private func withARowUnderAPopup(
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
        WinUIHoverHold.began()
        row.heard(.pointer(.pointerExited, .zero))
        XCTAssertEqual(WinUIHoverHold.holding, 1, "an exit under a popup is held, not delivered")
        XCTAssertEqual(element.value(.background), Color.black.propValue, "a popup took the pointer, not the row")

        try body(element, row)
    }

    /// The popup going with the pointer still on the row leaves its hover alone: the core was never told the pointer
    /// left, so the view keeps what it has.
    func testTheHoverStaysWhenThePopupGoesWithThePointerStillOnTheRow() throws {
        try onUIThread {
            try withARowUnderAPopup(pointerAt: Self.onTheRow) { element, _ in
                WinUIHoverHold.ended()
                XCTAssertEqual(element.value(.background), Color.black.propValue)
                XCTAssertEqual(WinUIHoverHold.holding, 0)
            }
        }
    }

    /// The popup going with the pointer away from the row hands it the exit it was owed.
    func testTheHoverGoesWhenThePopupGoesWithThePointerAway() throws {
        try onUIThread {
            try withARowUnderAPopup(pointerAt: Self.pastTheRow) { element, _ in
                WinUIHoverHold.ended()
                XCTAssertEqual(element.value(.background), Color.clear.propValue)
                XCTAssertEqual(WinUIHoverHold.holding, 0)
            }
        }
    }

    /// A row that left the tree while its popup stood is let go of: it is owed nothing, and nothing is called into it
    /// when the popup goes.
    func testARowThatLeftTheTreeWhileItsPopupStoodIsLetGoOf() throws {
        try onUIThread {
            try withARowUnderAPopup(pointerAt: Self.pastTheRow) { _, row in
                row.detach()
                XCTAssertEqual(WinUIHoverHold.holding, 0, "a view that left is owed nothing")
                WinUIHoverHold.ended()
                XCTAssertEqual(WinUIHoverHold.holding, 0)
            }
        }
    }

    /// A pointer coming back on the row while the popup stands drops what was withheld: the view's hover never left
    /// either, so nothing is owed it when the popup goes.
    func testThePointerComingBackDropsWhatWasWithheld() throws {
        try onUIThread {
            try withARowUnderAPopup(pointerAt: Self.pastTheRow) { element, row in
                row.heard(.pointer(.pointerEntered, .zero))
                XCTAssertEqual(WinUIHoverHold.holding, 0)
                XCTAssertEqual(element.value(.background), Color.black.propValue)
                WinUIHoverHold.ended()
                XCTAssertEqual(element.value(.background), Color.black.propValue, "the pointer is on the row")
            }
        }
    }
}
