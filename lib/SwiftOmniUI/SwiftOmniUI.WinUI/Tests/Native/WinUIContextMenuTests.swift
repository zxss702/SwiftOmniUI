// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import SwiftOmniUIConformance
import XCTest

/// Two stacks offering a menu a button empties, the second hearing taps too.
private struct MenuStacksPage: View {
    @State private var entries = ["Open"]

    var body: some View {
        let entries = $entries
        return VStack {
            HStack { Text("menu") }
                .frame(width: 200)
                .frame(height: 40)
                .contextMenu { ForEach(entries.wrappedValue, id: \.self) { entry in MenuItem(entry) } }
            HStack { Text("tapped") }
                .frame(width: 200)
                .frame(height: 40)
                .onTapGesture {}
                .contextMenu { ForEach(entries.wrappedValue, id: \.self) { entry in MenuItem(entry) } }
            Button("Empty").onClicked { entries.wrappedValue = [] }
        }
        .horizontalAlignment(.start)
        .verticalAlignment(.start)
    }
}

final class WinUIContextMenuTests: XCTestCase {
    /// A stack offering a menu is hit where it draws nothing, so a right click past its words opens the menu;
    /// once the menu goes, it is hit there only while it still hears taps.
    func testAStackOfferingAMenuIsHitWhereItDrawsNothing() throws {
        try onUIThread {
            let host = WinUIRenderer.running { MenuStacksPage() }
            let stacks = host.views(WinUIStackView.self).filter { $0.menus == "Open" }
            XCTAssertEqual(stacks.count, 2)
            XCTAssertTrue(stacks[0].hits(190, 20))
            XCTAssertTrue(stacks[1].hits(190, 20))

            try XCTUnwrap(host.views(WinUIButtonView.self).first).invoke()
            host.settle { stacks[0].menus == "" }
            XCTAssertFalse(stacks[0].hits(190, 20), "no menu, nothing heard: hit only on its words")
            XCTAssertTrue(stacks[1].hits(190, 20), "still hearing taps")
        }
    }

    /// A menu standing open over the pointer is a popup standing over it, and its going is a popup going: what the
    /// views under it hold their hover through.
    /// Design: docs/design/platforms/winui/input.md#a-popup-over-the-pointer
    func testAMenuStandingOpenIsAPopupStandingOverThePointer() throws {
        try onUIThread {
            let host = WinUIRenderer.running {
                Menu { MenuItem("Item") } label: { Text("Trigger") }
            }
            let menu = try XCTUnwrap(host.views(WinUIMenuButtonView.self).first)
            let standing = WinUIHoverHold.isStanding

            swiftomniui_winui_menu_open_for_testing(menu.handle)
            host.settle { WinUIHoverHold.isStanding != standing }
            XCTAssertTrue(WinUIHoverHold.isStanding, "a menu standing open is a popup standing")

            swiftomniui_winui_menu_close_for_testing(menu.handle)
            host.settle { WinUIHoverHold.isStanding == standing }
            XCTAssertEqual(WinUIHoverHold.isStanding, standing, "the menu going is the popup going")
        }
    }
}
