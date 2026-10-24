// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

final class WinUIPickerDeletionTests: XCTestCase {
    func testRemovingSelectedOptionDiscardsItsIntrinsicMeasurement() throws {
        try onUIThread {
            let longName = String(repeating: "Selected model ", count: 12)
            let host = WinUIRenderer.running {
                VStack { Picker(["Alpha", longName]).selectedIndex(1) }
            }
            let picker = try XCTUnwrap(host.views(WinUIPickerView.self).first)
            let selectedSize = WinUILayoutView.querySize { picker.measure(width: nil, height: nil) }
            ProgramWrite.perform { picker.setChoices([], chosen: -1, writeChosen: true, title: "") }
            let queriedSize = WinUILayoutView.querySize { picker.measure(width: nil, height: nil) }
            var nativeSize = [0.0, 0.0]
            swiftomniui_winui_measure(picker.handle, .infinity, .infinity, &nativeSize)
            XCTAssertEqual(queriedSize, LayoutSize(width: nativeSize[0], height: nativeSize[1]),
                           "a parent must not receive the removed selected item's cached size")
            XCTAssertNotEqual(queriedSize, selectedSize)
        }
    }

    func testRemovingSelectedTaggedOptionLeavesTheStoredSelectionUnchanged() throws {
        try onUIThread {
            let models = State(wrappedValue: ["Alpha", "Beta", "Gamma"])
            let selected = State(wrappedValue: "Beta")
            let host = WinUIRenderer.running {
                VStack {
                    Picker("", selection: selected.projectedValue) {
                        ForEach(models.wrappedValue, id: \.self) { Text($0).tag($0) }
                    }
                }
            }
            let picker = try XCTUnwrap(host.views(WinUIPickerView.self).first)
            XCTAssertEqual(picker.chosen, 1)
            swiftomniui_winui_picker_open_as_user(picker.handle, true)
            host.step()
            withAnimation(.snappy) { models.wrappedValue = ["Alpha", "Gamma"] }
            host.step()
            host.layOut()
            XCTAssertEqual(picker.chosen, -1)
            XCTAssertEqual(Self.caption(picker), "")
            XCTAssertEqual(selected.wrappedValue, "Beta")
            swiftomniui_winui_picker_set_open(picker.handle, false)
            swiftomniui_winui_picker_choose_as_user(picker.handle, 1)
            host.step()
            XCTAssertEqual(selected.wrappedValue, "Gamma")
            withAnimation(.snappy) { models.wrappedValue = [] }
            host.step()
            host.layOut()
            XCTAssertEqual(picker.chosen, -1)
            XCTAssertEqual(Self.caption(picker), "")
            XCTAssertEqual(selected.wrappedValue, "Gamma")
        }
    }

    @MainActor private static func caption(_ picker: WinUIPickerView) -> String {
        WinUIStrings.read { swiftomniui_winui_read(picker.handle, "displayedText", $0, $1) }
    }
}
