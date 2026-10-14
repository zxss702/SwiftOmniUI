// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

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
    }

    /// The relay's kinds: an item 0, a separator 1, a submenu opening 2 and closing 3, a disabled Text 4.
    private mutating func add(_ entries: [MenuEntry]) {
        for entry in entries {
            switch entry.kind {
            case .item:
                append(entry.element?.type == .text ? 4 : 0, entry.title, entry.isEnabled, entry.identifier,
                       mount: entry.element?.mount ?? 0)
                actions.append { [weak element = entry.element] in element?.winUI.send(.clicked, []) }
            case .separator:
                append(1, "", true, nil)
            case .submenu:
                append(2, entry.title, entry.isEnabled, entry.identifier, mount: entry.element?.mount ?? 0)
                add(entry.entries)
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
