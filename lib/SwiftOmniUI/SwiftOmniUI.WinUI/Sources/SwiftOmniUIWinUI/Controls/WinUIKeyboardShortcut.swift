// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// Native key conversion shared by buttons and command menus.
@MainActor
enum WinUIKeyboardShortcut {
    /// Named keys use VirtualKey; characters use the active Windows keyboard
    /// layout (punctuation's Unicode value is NOT a VirtualKey).
    static func numbers(_ shortcut: KeyboardShortcut) -> (Int32, Int32) {
        let mapped = ShortcutMapping.desktopShortcut(for: shortcut)
        var modifiers = mapped.modifiers.rawValue
        let key: Int32 = switch mapped.key {
        case "return": 13
        case "escape": 27
        case "tab": 9
        case "space": 32
        case "delete": 8
        case "deleteforward": 46
        case "left": 37
        case "up": 38
        case "right": 39
        case "down": 40
        case "home": 36
        case "end": 35
        case "pageup": 33
        case "pagedown": 34
        case let name where name.count > 1 && name.hasPrefix("f") && name.dropFirst().allSatisfy(\.isNumber):
            Int32(name.dropFirst()).map { $0 >= 1 && $0 <= 24 ? 111 + $0 : 0 } ?? 0
        case let name where name.unicodeScalars.count == 1:
            swiftomniui_winui_shortcut_key(name.unicodeScalars.first!.value, &modifiers)
        default: 0
        }
        return (key, modifiers)
    }

}
