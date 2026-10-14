// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore

/// One entry of a menu as every host walks it - an item, a separator, or a submenu holding entries of its own - with
/// its caption, its picture, whether it can be chosen, whether it destroys something and its identifier; the host
/// turns the walk into its toolkit's menu.
/// Design: docs/design/host/pages.md#menus
@_spi(Host) @MainActor public struct MenuEntry {
    /// What an entry is.
    public enum Kind: Sendable {
        /// An item the user chooses.
        case item

        /// A line between items.
        case separator

        /// A submenu, holding entries of its own.
        case submenu
    }

    /// What the entry is.
    public let kind: Kind

    /// The element: an item's, which hears it chosen, or a submenu's; nil for a separator.
    public let element: MountedElement?

    /// The caption; empty for a separator.
    public let title: String

    /// The picture shown with the caption, by name, where one is said.
    public let icon: String?

    /// The key that chooses the item from the keyboard, where one is said.
    public let shortcut: KeyboardShortcut?

    /// The region the menu's entries splice into, where the element stands
    /// for a command group rather than a menu of its own; nil for an
    /// ordinary menu.
    public let placement: CommandGroupPlacement?

    /// Whether the user can choose it.
    public let isEnabled: Bool

    /// Whether choosing it destroys something, which the platform marks.
    public let isDestructive: Bool

    /// The identifier a test and assistive technology find it by, where one is said.
    public let identifier: String?

    /// A submenu's entries, in order.
    public let entries: [MenuEntry]

    /// The entries `container` holds - a menu, a context menu, a submenu - in order; what is none of them is none. A
    /// `Button` stands as an item, its caption and icon read off its label's views, the way a command's button does.
    public static func entries(of container: MountedElement) -> [MenuEntry] {
        container.children.filter { !$0.isDeparting && $0.value(.isVisible)?.bool != false }.flatMap { entry -> [MenuEntry] in
            switch entry.type {
            case .menuItem, .button: [MenuEntry(entry, kind: .item, entries: [])]
            case .divider: [MenuEntry(nil, kind: .separator, entries: [])]
            case .menu: [MenuEntry(entry, kind: .submenu, entries: entries(of: entry))]
            case .menuButton:
                [MenuEntry(entry, kind: .submenu,
                           entries: entry.children.first { $0.type == .contextMenu }.map { entries(of: $0) } ?? [])]
            default: NodeType.slotTypes.contains(entry.type) ? [] : entries(of: entry)
            }
        }
    }

    /// The menus a menu bar holds, in order - what else stands at its top stands on no bar. A menu written for a
    /// region of the platform's own menus - a command group's - stands here too, its `placement` saying where.
    public static func menus(of bar: MountedElement) -> [MenuEntry] {
        bar.children.filter { $0.type == .menu }.map { MenuEntry($0, kind: .submenu, entries: entries(of: $0)) }
    }

    /// The entries `menus`' groups and menus hold, in order: a placement menu
    /// flattens to its entries - the region's, wherever the host splices
    /// them - an ordinary menu stays a submenu.
    public static func flattened(_ menus: [MenuEntry]) -> [MenuEntry] {
        menus.flatMap { menu in menu.placement == nil ? [menu] : menu.entries }
    }

    private init(_ element: MountedElement?, kind: Kind, entries: [MenuEntry]) {
        self.kind = kind
        self.element = element
        // A button's caption and picture live on its label's views; a menu's
        // on its own `text` and `icon`, never on its entries'.
        title = element?.value(.text)?.string
            ?? (element?.type == .button || element?.type == .menuButton ? element.flatMap(Self.caption) : nil) ?? ""
        icon = element?.value(.icon)?.string.flatMap { $0.isEmpty ? nil : $0 }
            ?? (element?.type == .button || element?.type == .menuButton ? element.flatMap(Self.picture) : nil)
        shortcut = element?.value(.shortcut).flatMap(KeyboardShortcut.init(propValue:))
        placement = element?.value(.placement).flatMap(CommandGroupPlacement.init(propValue:))
        isEnabled = element?.value(.isEnabled)?.bool ?? true
        isDestructive = element?.value(.isDestructive)?.bool == true
            || element?.value(.role)?.enumeration == ButtonRole.destructive.rawValue
        identifier = element?.value(.accessibilityIdentifier)?.string
        self.entries = entries
    }

    /// The first words a descendant carries - a `Button`'s caption lives on
    /// its label's `Text`, not on the button.
    private static func caption(of element: MountedElement) -> String? {
        for child in element.arrangedChildren {
            if let words = child.value(.text)?.string, !words.isEmpty { return words }
            if let words = caption(of: child) { return words }
        }
        return nil
    }

    /// The first picture a descendant carries - a label's icon is an `Image`
    /// under it, its name on `source`.
    private static func picture(of element: MountedElement) -> String? {
        for child in element.arrangedChildren {
            for token: Prop in [.source, .image] {
                if let name = child.value(token)?.string, !name.isEmpty { return name }
            }
            if let name = picture(of: child) { return name }
        }
        return nil
    }
}
