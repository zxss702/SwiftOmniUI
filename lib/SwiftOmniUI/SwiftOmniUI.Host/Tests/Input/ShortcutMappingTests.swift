// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import XCTest

final class ShortcutMappingTests: XCTestCase {
    func testMacOSAnchoredModifiersMapToWindowsAndLinuxDesktopConventions() {
        XCTAssertEqual(ShortcutMapping.desktopModifiers(for: .command), .control)
        XCTAssertEqual(ShortcutMapping.desktopModifiers(for: .option), .alt)
        XCTAssertEqual(ShortcutMapping.desktopModifiers(for: .shift), .shift)
        XCTAssertEqual(ShortcutMapping.desktopModifiers(for: .control), .control)
        XCTAssertEqual(ShortcutMapping.desktopModifiers(for: [.command, .shift]), [.control, .shift])
        XCTAssertEqual(ShortcutMapping.desktopModifiers(for: [.command, .option]), [.control, .alt])
        // Combining macOS .command and .control stays distinct from .command alone.
        XCTAssertEqual(ShortcutMapping.desktopModifiers(for: [.command, .control]), [.control, .alt])
        XCTAssertEqual(ShortcutMapping.desktopModifiers(for: []), [])
    }

    func testPunctuationAndDefaultCancelActionsMapCleanly() {
        let stop = ShortcutMapping.desktopShortcut(for: KeyboardShortcut(".", modifiers: .command))
        XCTAssertEqual(stop.key, ".")
        XCTAssertEqual(stop.modifiers, .control)

        let accept = ShortcutMapping.desktopShortcut(for: .defaultAction)
        XCTAssertEqual(accept.key, "return")
        XCTAssertEqual(accept.modifiers, [])

        let cancel = ShortcutMapping.desktopShortcut(for: .cancelAction)
        XCTAssertEqual(cancel.key, "escape")
        XCTAssertEqual(cancel.modifiers, [])
    }

    func testStandardMacOSAnchoredDesktopShortcuts() {
        XCTAssertEqual(ShortcutMapping.standardShortcut(key: "n", modifiers: .control), .newWindow)
        XCTAssertEqual(ShortcutMapping.standardShortcut(key: "N", modifiers: .control), .newWindow)
        XCTAssertEqual(ShortcutMapping.standardShortcut(key: ",", modifiers: .control), .openSettings)
        XCTAssertEqual(ShortcutMapping.standardShortcut(key: "w", modifiers: .control), .closeWindow)
        XCTAssertEqual(ShortcutMapping.standardShortcut(key: "q", modifiers: .control), .quitApp)
        XCTAssertEqual(ShortcutMapping.standardShortcut(key: "m", modifiers: .control), .minimizeWindow)
        XCTAssertEqual(ShortcutMapping.standardShortcut(key: "s", modifiers: [.control, .alt]), .toggleSidebar)
        XCTAssertEqual(ShortcutMapping.standardShortcut(key: "f", modifiers: [.control, .alt]), .toggleFullscreen)
        XCTAssertNil(ShortcutMapping.standardShortcut(key: "n", modifiers: [.control, .shift]))
        XCTAssertNil(ShortcutMapping.standardShortcut(key: "c", modifiers: .control))
    }
}
