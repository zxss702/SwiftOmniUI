// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore

/// Normalized modifier flags for Windows and Linux desktop hosts, mapped from
/// macOS-anchored SwiftUI `EventModifiers`.
@_spi(Host) public struct DesktopModifiers: OptionSet, Equatable, Sendable {
    public let rawValue: Int32

    public init(rawValue: Int32) { self.rawValue = rawValue }

    /// Physical Control key (`VirtualKeyModifiers.Control` / `GDK_CONTROL_MASK`).
    public static let control = DesktopModifiers(rawValue: 1 << 0)
    /// Physical Alt key (`VirtualKeyModifiers.Menu` / `GDK_ALT_MASK`).
    public static let alt = DesktopModifiers(rawValue: 1 << 1)
    /// Physical Shift key (`VirtualKeyModifiers.Shift` / `GDK_SHIFT_MASK`).
    public static let shift = DesktopModifiers(rawValue: 1 << 2)
}

/// Maps macOS-anchored SwiftUI keyboard shortcuts to Windows and Linux
/// desktop conventions so application code authors shortcuts once for macOS:
/// - macOS `.command` (⌘) -> `Ctrl`
/// - macOS `.option`  (⌥) -> `Alt`
/// - macOS `.shift`   (⇧) -> `Shift`
/// - macOS `.control` (⌃) -> `Ctrl` when used without `.command`, or `Alt`
///   when combined with `.command` so `[.command, .control]` stays distinct
///   from `.command` alone.
/// - `.defaultAction` / `.cancelAction` -> bare `return` / `escape`.
@_spi(Host) public enum ShortcutMapping {
    public static func desktopModifiers(for modifiers: EventModifiers) -> DesktopModifiers {
        var result: DesktopModifiers = []
        let hasCommand = modifiers.contains(.command)
        let hasControl = modifiers.contains(.control)
        if hasCommand { result.insert(.control) }
        if hasControl {
            result.insert(hasCommand ? .alt : .control)
        }
        if modifiers.contains(.option) { result.insert(.alt) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        return result
    }

    public static func desktopShortcut(for shortcut: KeyboardShortcut) -> (key: String, modifiers: DesktopModifiers) {
        switch shortcut.key.name {
        case "defaultaction":
            return ("return", [])
        case "cancelaction":
            return ("escape", [])
        default:
            return (shortcut.key.name, desktopModifiers(for: shortcut.modifiers))
        }
    }

    /// Matches a normalized desktop key name (lowercase, e.g. `"n"`, `","`, `"w"`)
    /// and `DesktopModifiers` against the built-in macOS-anchored standard shortcuts.
    public static func standardShortcut(key: String, modifiers: DesktopModifiers) -> StandardShortcut? {
        switch (key.lowercased(), modifiers) {
        case ("n", .control): return .newWindow
        case (",", .control): return .openSettings
        case ("w", .control): return .closeWindow
        case ("q", .control): return .quitApp
        case ("m", .control): return .minimizeWindow
        case ("s", [.control, .alt]): return .toggleSidebar
        case ("f", [.control, .alt]): return .toggleFullscreen
        default: return nil
        }
    }
}

/// Built-in macOS-anchored standard shortcuts supported automatically on
/// Windows and Linux when no view button or menu command claims the same key.
@_spi(Host) public enum StandardShortcut: Int32, CaseIterable, Equatable, Sendable {
    /// macOS `⌘N` -> `Ctrl+N`: open/activate the app's new / primary window.
    case newWindow = 1
    /// macOS `⌘,` -> `Ctrl+,`: open/activate the app's settings window.
    case openSettings = 2
    /// macOS `⌘W` -> `Ctrl+W`: close the active window.
    case closeWindow = 3
    /// macOS `⌘Q` -> `Ctrl+Q`: quit the application (close all windows).
    case quitApp = 4
    /// macOS `⌘M` -> `Ctrl+M`: minimize the active window.
    case minimizeWindow = 5
    /// macOS `⌘⌃S` / `⌘⌥S` -> `Ctrl+Alt+S`: toggle the active window's sidebar.
    case toggleSidebar = 6
    /// macOS `⌘⌃F` -> `Ctrl+Alt+F`: toggle fullscreen on the active window.
    case toggleFullscreen = 7
}
