// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

final class WinUIPickerViewTests: XCTestCase {
    func testNativeCaptionFollowsSelectionAndReplacementOptionsOnTheirFirstLayout() throws {
        try onUIThread {
            let models = State(wrappedValue: ["Alpha", "Beta"])
            let selected = State(wrappedValue: 1)
            let host = WinUIRenderer.running {
                VStack {
                    Picker(models.wrappedValue).selectedIndex(selected.projectedValue).id("models")
                }
            }
            let picker = try XCTUnwrap(host.view(id: .manual("models")) as? WinUIPickerView)
            XCTAssertEqual(picker.chosen, 1)
            XCTAssertEqual(Self.caption(picker), "Beta", "verify the template's text, not only SelectedIndex")
            XCTAssertGreaterThan(picker.laidOutFrame.width, 0)

            models.wrappedValue = ["New Alpha", "New Beta with a longer model name"]
            host.step()
            host.layOut()
            XCTAssertTrue(host.view(id: .manual("models")) === picker)
            XCTAssertEqual(picker.chosen, 1, "ItemsSource replacement reapplies the same selected index")
            XCTAssertEqual(Self.caption(picker), "New Beta with a longer model name")

            selected.wrappedValue = 0
            host.step()
            host.layOut()
            XCTAssertEqual(picker.chosen, 0)
            XCTAssertEqual(Self.caption(picker), "New Alpha")
        }
    }

    func testInitiallyEmptyOptionsAndReopenedSettingsDisplayTheStoredChoice() throws {
        try onUIThread {
            let options = State(wrappedValue: [String]())
            let settings = State(wrappedValue: true)
            let selected = State(wrappedValue: 1)
            let host = WinUIRenderer.running {
                VStack {
                    if settings.wrappedValue {
                        Picker(options.wrappedValue).selectedIndex(selected.projectedValue).id("models")
                    } else { Text("Closed") }
                }
            }
            options.wrappedValue = ["Alpha", "Beta"]
            host.step()
            host.layOut()
            let first = try XCTUnwrap(host.views(WinUIPickerView.self).first)
            XCTAssertEqual(first.chosen, 1)
            XCTAssertEqual(Self.caption(first), "Beta")
            settings.wrappedValue = false
            host.step()
            settings.wrappedValue = true
            host.step()
            host.layOut()
            let reopened = try XCTUnwrap(host.views(WinUIPickerView.self).first)
            XCTAssertEqual(reopened.chosen, 1)
            XCTAssertEqual(Self.caption(reopened), "Beta")
            XCTAssertEqual(selected.wrappedValue, 1)
        }
    }

    @MainActor private static func caption(_ picker: WinUIPickerView) -> String {
        WinUIStrings.read { swiftomniui_winui_read(picker.handle, "displayedText", $0, $1) }
    }
}
