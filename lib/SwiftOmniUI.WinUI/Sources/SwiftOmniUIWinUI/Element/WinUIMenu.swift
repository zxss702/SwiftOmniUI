// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// A menu as the relay takes it: its entries flat - an item, a separator, a submenu opening and closing - each with
/// its caption and whether it can be chosen, and what each item does, in the items' order. A menu bar's are its
/// menus, each one's entries within it.
/// Design: docs/design/platforms/winui/pages.md#menus
@MainActor
struct WinUIMenu {
    private(set) var kinds: [Int32] = []
    private(set) var titles: [String] = []
    private(set) var enabled: [Bool] = []
    private(set) var identifiers: [String] = []
    private(set) var mounts: [UInt64] = []
    private(set) var actions: [() -> Void] = []
    private struct Shortcut: Equatable {
        let value: KeyboardShortcut
        let item: Int32
    }
    private var shortcuts: [Shortcut] = []

    /// The entries `container` holds, as the host layer walks them; none for no container.
    init(_ container: WinUIElement? = nil) {
        if let container { add(MenuEntry.entries(of: container.element)) }
    }

    /// The menus `bar` holds, as the host layer walks them; none for no bar.
    init(bar: WinUIElement?) {
        if let bar { add(MenuEntry.menus(of: bar.element)) }
    }

    /// `menus` written as a bar's - each one a top-level menu of it.
    init(menus: [MenuEntry]) {
        add(menus)
    }

    /// `entries` written as one flyout's - a command menu a submenu in it.
    init(entries: [MenuEntry]) {
        add(entries)
    }

    /// Whether the menu has no entries.
    var isEmpty: Bool { kinds.isEmpty }

    /// Whether the menu draws as `other` does: the same entries, captions and choosable ones.
    func draws(like other: WinUIMenu) -> Bool {
        kinds == other.kinds && titles == other.titles && enabled == other.enabled
            && identifiers == other.identifiers && mounts == other.mounts
            && shortcuts == other.shortcuts
    }

    /// Scene commands must work while their flyout is closed. Own their
    /// accelerators on the live menu button/bar, not transient flyout items.
    func installShortcuts(on view: WinUIView) {
        let native = shortcuts.map { WinUIKeyboardShortcut.numbers($0.value) }
        let keys = native.map(\.0), modifiers = native.map(\.1), items = shortcuts.map(\.item)
        keys.withUnsafeBufferPointer { keys in
            modifiers.withUnsafeBufferPointer { modifiers in
                items.withUnsafeBufferPointer { items in
                    swiftomniui_winui_menu_set_shortcuts(view.handle, view.number, keys.baseAddress,
                                                       modifiers.baseAddress, items.baseAddress, Int32(keys.count))
                }
            }
        }
    }

    /// The relay's kinds: an item 0, a separator 1, a submenu opening 2 and closing 3, a disabled Text 4.
    private mutating func add(_ entries: [MenuEntry], parentEnabled: Bool = true) {
        for entry in entries {
            let enabled = parentEnabled && entry.isEnabled
            switch entry.kind {
            case .item:
                append(entry.element?.type == .text ? 4 : 0, entry.title, enabled, entry.identifier,
                       mount: entry.element?.mount ?? 0)
                if enabled, let shortcut = entry.shortcut {
                    shortcuts.append(Shortcut(value: shortcut, item: Int32(actions.count)))
                }
                actions.append { [weak element = entry.element] in element?.winUI.send(.clicked, []) }
            case .separator:
                append(1, "", true, nil)
            case .submenu:
                append(2, entry.title, enabled, entry.identifier, mount: entry.element?.mount ?? 0)
                add(entry.entries, parentEnabled: enabled)
                append(3, "", true, nil)
            }
        }
    }

    private mutating func append(_ kind: Int32, _ title: String, _ isEnabled: Bool, _ identifier: String?, mount: UInt64 = 0) {
        kinds.append(kind)
        titles.append(title)
        enabled.append(isEnabled)
        identifiers.append(identifier ?? "")
        mounts.append(mount)
    }
}
