// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIGTK
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIGTK
import XCTest

/// A row that turns on under the pointer, with a menu beside it, as a list's row with a menu does.
private struct HoverRowPage: View {
    /// The row's own hover, which the page writes and the test reads.
    let hovered: State<Bool>

    var body: some View {
        VStack {
            ZStack { Text("Row") }
                .frame(width: 200, height: 40)
                .onHover { hovered.wrappedValue = $0 }
                .id("hover-row")
            Menu { MenuItem("Open") } label: { Text("Menu") }
        }
        .frame(width: 300)
        .horizontalAlignment(.start)
        .verticalAlignment(.start)
    }
}

/// What a popup standing over the pointer does to the hover of what it covers: the exit GTK tells is held while it
/// stands, and when the last one goes the truth is taken again from where the pointer is.
/// Design: docs/design/platforms/gtk/input.md#a-popup-over-the-pointer
final class GTKHoverHoldTests: XCTestCase {
    /// The page under a menu the test opened - the row's own hover to read, and the menu to close.
    @MainActor
    private struct RowUnderAMenu {
        let hovered: State<Bool>
        let row: GTKView
        let host: GTKRenderer
        let menu: GTKMenuButtonView

        /// The menu closed as the user closes one, then what the rule made of it.
        func closeTheMenu() {
            gtk_menu_button_popdown(menu.widget.opaque)
            host.settle { !GTKHoverHold.isStanding }
        }
    }

    /// Runs `body` over a page whose row a menu of the page's own stands over: the pointer entered the row, the menu
    /// opened as the user opens one, and the exit GTK told the row held - with the pointer's own place answered as one
    /// that is still on the row, or one that is past it.
    @MainActor
    private func withARowUnderAMenu(
        pointerStillOnTheRow: Bool, _ body: @MainActor (RowUnderAMenu) throws -> Void
    ) throws {
        defer { GTKHoverHold.pointerPlace = GTKHoverHold.livePointerPlace }
        let hovered = State(wrappedValue: false)
        let host = GTKRenderer.running { HoverRowPage(hovered: hovered) }
        let row = try XCTUnwrap(host.view(id: .manual("hover-row")))
        // The places are the row's own, so where the window holds the page does not matter.
        let box = try XCTUnwrap(row.windowRect(), "the row stands in the window")
        let onTheRow = Point(x: box.x + 5, y: box.y + 5)
        let pastTheRow = Point(x: box.x + 5, y: box.y + box.height + 40)
        XCTAssertTrue(GTKHoverHold.reaches(row, onTheRow), "the row's own box reaches the row")
        XCTAssertFalse(GTKHoverHold.reaches(row, pastTheRow), "the window past the row is not the row")
        GTKHoverHold.pointerPlace = { _ in pointerStillOnTheRow ? onTheRow : pastTheRow }

        let menu = try XCTUnwrap(host.views(GTKMenuButtonView.self).first)
        gtk_menu_button_popup(menu.widget.opaque)
        host.settle { GTKHoverHold.isStanding }
        XCTAssertTrue(GTKHoverHold.isStanding, "the menu the test opened stands over the pointer")

        row.heard(.pointer(.pointerEntered, .zero))
        XCTAssertTrue(hovered.wrappedValue, "the pointer on the row turns it on")
        row.heard(.pointer(.pointerExited, .zero))
        XCTAssertEqual(GTKHoverHold.holding, 1, "an exit under a popup is held, not delivered")
        XCTAssertTrue(hovered.wrappedValue, "a popup took the pointer, not the row")

        try body(RowUnderAMenu(hovered: hovered, row: row, host: host, menu: menu))
    }

    /// The menu going with the pointer still on the row leaves its hover alone: the core was never told the pointer
    /// left, so the view keeps what it has.
    func testTheHoverStaysWhenTheMenuGoesWithThePointerStillOnTheRow() throws {
        try onUIThread {
            try withARowUnderAMenu(pointerStillOnTheRow: true) { page in
                page.closeTheMenu()
                page.host.step()
                XCTAssertTrue(page.hovered.wrappedValue, "the pointer is still on the row")
                XCTAssertEqual(GTKHoverHold.holding, 0)
            }
        }
    }

    /// The menu going with the pointer away from the row hands it the exit it was owed.
    func testTheHoverGoesWhenTheMenuGoesWithThePointerAway() throws {
        try onUIThread {
            try withARowUnderAMenu(pointerStillOnTheRow: false) { page in
                page.closeTheMenu()
                page.host.step()
                XCTAssertFalse(page.hovered.wrappedValue, "the pointer is past the row")
                XCTAssertEqual(GTKHoverHold.holding, 0)
            }
        }
    }

    /// A row that left the tree while the menu stood is let go of: it is owed nothing, and nothing is called into it
    /// when the menu goes.
    func testARowThatLeftTheTreeWhileTheMenuStoodIsLetGoOf() throws {
        try onUIThread {
            try withARowUnderAMenu(pointerStillOnTheRow: false) { page in
                page.row.detach()
                XCTAssertEqual(GTKHoverHold.holding, 0, "a view that left is owed nothing")
                page.closeTheMenu()
                XCTAssertEqual(GTKHoverHold.holding, 0)
            }
        }
    }

    /// A pointer coming back on the row while the menu stands drops what was withheld: the view's hover never left
    /// either, so nothing is owed it when the menu goes.
    func testThePointerComingBackDropsWhatWasWithheld() throws {
        try onUIThread {
            try withARowUnderAMenu(pointerStillOnTheRow: false) { page in
                page.row.heard(.pointer(.pointerEntered, .zero))
                XCTAssertEqual(GTKHoverHold.holding, 0, "the pointer is on the view again")
                XCTAssertTrue(page.hovered.wrappedValue)
                page.closeTheMenu()
                page.host.step()
                XCTAssertTrue(page.hovered.wrappedValue, "the pointer is on the row")
            }
        }
    }

    /// A popover whose widget left the screen without being told to hide - the button it hangs on left the tree, its
    /// window closed - is uncounted as it goes, so no count outlives what it counted.
    func testAPopoverWhoseWidgetWentIsNotCounted() throws {
        try onUIThread {
            let host = GTKRenderer.running {
                VStack { Text("Page") }
                    .frame(width: 300)
                    .horizontalAlignment(.start)
                    .verticalAlignment(.start)
                    .id("page")
            }
            let page = try XCTUnwrap(host.view(id: .manual("page"))).widget
            let popover = gtk_popover_new()!
            g_object_ref_sink(UnsafeMutableRawPointer(popover))
            defer { g_object_unref(UnsafeMutableRawPointer(popover)) }
            gtk_widget_set_parent(popover, page)
            GTKHoverHold.watch(popover)

            gtk_popover_popup(popover.of(GtkPopover.self))
            host.layOut()
            XCTAssertTrue(GTKHoverHold.isStanding, "a popover the user sees is counted")
            host.settle { gtk_widget_get_mapped(popover) != 0 }
            XCTAssertTrue(gtk_widget_get_mapped(popover) != 0, "the popover made it to the screen")

            gtk_widget_unparent(popover)
            host.step()
            XCTAssertFalse(GTKHoverHold.isStanding, "a popover whose widget went counts for nothing")
        }
    }
}
