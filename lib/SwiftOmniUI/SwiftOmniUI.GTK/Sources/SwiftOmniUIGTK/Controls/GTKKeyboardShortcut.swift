// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIGTK

/// Native key conversion shared by buttons and command menus.
enum GTKKeyboardShortcut {
    static func modifiers(_ shortcut: KeyboardShortcut) -> GdkModifierType {
        let mapped = ShortcutMapping.desktopShortcut(for: shortcut).modifiers
        var mask = GdkModifierType(rawValue: 0).rawValue
        if mapped.contains(.control) { mask |= GDK_CONTROL_MASK.rawValue }
        if mapped.contains(.shift) { mask |= GDK_SHIFT_MASK.rawValue }
        if mapped.contains(.alt) { mask |= GDK_ALT_MASK.rawValue }
        return GdkModifierType(rawValue: mask)
    }

    static func trigger(_ shortcut: KeyboardShortcut) -> OpaquePointer? {
        let mapped = ShortcutMapping.desktopShortcut(for: shortcut)
        let key = keyval(mapped.key)
        guard key != GDK_KEY_VoidSymbol, key != 0 else { return nil }
        return gtk_keyval_trigger_new(key, modifiers(shortcut))
    }

    /// The key's GDK keyval: the named keys by the names GDK gives them, a
    /// character by itself.
    static func keyval(_ name: String) -> guint {
        if name.unicodeScalars.count == 1, let scalar = name.unicodeScalars.first {
            return gdk_unicode_to_keyval(scalar.value)
        }
        let gdk: String = switch name {
        case "return", "defaultaction": "Return"
        case "escape", "cancelaction": "Escape"
        case "tab": "Tab"
        case "space": "space"
        case "delete": "BackSpace"
        case "deleteforward": "Delete"
        case "up": "Up"
        case "down": "Down"
        case "left": "Left"
        case "right": "Right"
        case "home": "Home"
        case "end": "End"
        case "pageup": "Page_Up"
        case "pagedown": "Page_Down"
        case let name where name.hasPrefix("f") && Int(name.dropFirst()).map({ (1...35).contains($0) }) == true:
            "F" + String(name.dropFirst())
        default: name
        }
        return gdk.withCString { gdk_keyval_from_name($0) }
    }

}
