// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIGTK

/// A menu as GTK's menus hold one: the host layer's walk of its entries (`MenuEntry`) as a `GMenu` - the entries
/// between two separators a section, a submenu a link - each item an action of the group the menu hands the widget
/// it stands on, enabled where the item can be chosen. GNOME's menus show words alone: no picture, no warning.
/// Design: docs/design/platforms/gtk/pages.md#menus
@MainActor
final class GTKMenu {
    /// The prefix the menu's actions stand under on the widget they are handed to.
    static let actionGroup = "swiftomniui-menu"

    /// The model, held until the menu goes.
    let model: OpaquePointer

    /// The actions its items run, by name.
    let actions: UnsafeMutablePointer<GSimpleActionGroup>

    /// Each item's element, by its action's name.
    private(set) var items: [String: () -> MountedElement?] = [:]

    /// The numbers its actions' signals carry.
    private var numbers: [String: Int64] = [:]

    /// What the menu draws: its entries' kinds, captions and whether each can be chosen, in order.
    private(set) var drawn: [String] = []

    /// How many submenus it holds, each with the action it opens by.
    private var models: [UInt64: OpaquePointer] = [:]
    private var modelEntries: [UInt64: [MenuEntry]] = [:]
    private var currentEntries: [MenuEntry] = []
    private var usedModels: Set<UInt64> = []
    private var usedActions: Set<String> = []
    private var actionNames: Set<String> = []

    /// Whether the menu holds no entries.
    var isEmpty: Bool { drawn.isEmpty }

    /// The menu of `entries`.
    init(_ entries: [MenuEntry]) {
        model = g_menu_new()
        actions = g_simple_action_group_new()!
        replace(entries)
    }

    isolated deinit {
        for number in numbers.values { Self.chosen[number] = nil; Self.requested[number] = nil }
        for submenu in models.values { g_object_unref(UnsafeMutableRawPointer(submenu)) }
        g_object_unref(UnsafeMutableRawPointer(model))
        g_object_unref(UnsafeMutableRawPointer(actions))
    }

    /// Apply another description to this live menu without replacing its native objects.
    func replace(with other: GTKMenu) {
        replace(other.currentEntries)
    }

    /// Update the live model, keeping each unchanged submenu model and action attached to GTK.
    func replace(_ entries: [MenuEntry]) {
        guard !Self.same(entries, currentEntries) else { return }
        usedModels = []
        usedActions = []
        render(entries, to: model, key: 0)
        for key in Array(models.keys) where !usedModels.contains(key) {
            if let submenu = models.removeValue(forKey: key) { g_object_unref(UnsafeMutableRawPointer(submenu)) }
            modelEntries[key] = nil
        }
        for name in actionNames.subtracting(usedActions) {
            g_action_map_remove_action(OpaquePointer(actions), name)
            items[name] = nil
            if let number = numbers.removeValue(forKey: name) {
                Self.chosen[number] = nil
                Self.requested[number] = nil
            }
        }
        actionNames = usedActions
        currentEntries = entries
        drawn = []
        func describe(_ entries: [MenuEntry]) {
            for entry in entries {
                if entry.kind == .separator { drawn.append("-"); continue }
                drawn.append((entry.isEnabled ? "" : "!") + entry.title + (entry.kind == .submenu ? "[" : ""))
                if entry.kind == .submenu { describe(entry.entries); drawn.append("]") }
            }
        }
        describe(entries)
    }

    private static func sameHeaders(_ entries: [MenuEntry], _ old: [MenuEntry]) -> Bool {
        entries.count == old.count && zip(entries, old).allSatisfy {
            $0.kind == $1.kind && $0.title == $1.title && $0.isEnabled == $1.isEnabled && $0.element === $1.element
        }
    }

    private static func same(_ entries: [MenuEntry], _ old: [MenuEntry]) -> Bool {
        sameHeaders(entries, old) && zip(entries, old).allSatisfy { same($0.entries, $1.entries) }
    }

    private func render(_ entries: [MenuEntry], to menu: OpaquePointer, key: UInt64) {
        if let old = modelEntries[key], Self.sameHeaders(entries, old) {
            for entry in entries where entry.kind != .separator {
                let name = (entry.kind == .submenu ? "s" : "e") + String(entry.element?.mount ?? 0)
                usedActions.insert(name)
                if entry.kind == .submenu, let mount = entry.element?.mount, let submenu = models[mount] {
                    usedModels.insert(mount)
                    render(entry.entries, to: submenu, key: mount)
                }
            }
        } else {
            g_menu_remove_all(menu)
            add(entries, to: menu)
        }
        modelEntries[key] = entries
    }

    /// Adds `entries` to `menu`, a section between each two separators.
    private func add(_ entries: [MenuEntry], to menu: OpaquePointer) {
        let sections = entries.split(omittingEmptySubsequences: true) { $0.kind == .separator }
        for section in sections {
            let part = sections.count > 1 ? g_menu_new()! : menu
            for entry in section { add(entry, to: part) }
            guard sections.count > 1 else { continue }
            g_menu_append_section(menu, nil, g_menu_model(part))
            g_object_unref(UnsafeMutableRawPointer(part))
        }
    }

    /// Adds an item, or a submenu holding its own entries.
    private func add(_ entry: MenuEntry, to menu: OpaquePointer) {
        if entry.kind == .submenu {
            let mount = entry.element?.mount ?? 0
            let submenu = models[mount] ?? g_menu_new()!
            models[mount] = submenu
            usedModels.insert(mount)
            render(entry.entries, to: submenu, key: mount)
            // A submenu out of reach is one whose action - the one GTK tracks it open by - cannot run.
            let name = "s\(mount)"
            let existing = g_action_map_lookup_action(OpaquePointer(actions), name)
            let opens = existing.map { UnsafeMutableRawPointer($0).assumingMemoryBound(to: GSimpleAction.self) }
                ?? g_simple_action_new_stateful(name, nil, g_variant_new_boolean(0))!
            usedActions.insert(name)
            if existing == nil {
                let number = Self.nextNumber
                Self.nextNumber += 1
                numbers[name] = number
                Self.requested[number] = { [weak element = entry.element] in element }
                connectSignal(UnsafeMutableRawPointer(opens), "change-state", number: number) {
                    (action: UnsafeMutableRawPointer?, state: UnsafeMutableRawPointer?, data: gpointer?) in
                    guard let action, let state else { return }
                    g_simple_action_set_state(action.assumingMemoryBound(to: GSimpleAction.self), OpaquePointer(state))
                    guard g_variant_get_boolean(OpaquePointer(state)) != 0 else { return }
                    let number = viewNumber(data)
                    MainActor.assumeIsolated {
                        guard let element = GTKMenu.requested[number]?(), let host = element.gtk.host else { return }
                        element.requestMenuContent(in: host.runtime)
                    }
                }
                g_action_map_add_action(OpaquePointer(actions), opens)
            }
            g_simple_action_set_enabled(opens, entry.isEnabled ? 1 : 0)
            if existing == nil { g_object_unref(UnsafeMutableRawPointer(opens)) }
            let item = g_menu_item_new_submenu(entry.title, g_menu_model(submenu))!
            g_menu_item_set_attribute_value(item, "submenu-action", g_variant_new_string(Self.actionGroup + "." + name))
            g_menu_append_item(menu, item)
            g_object_unref(UnsafeMutableRawPointer(item))
            return
        }
        let name = "e\(entry.element?.mount ?? 0)"
        usedActions.insert(name)
        let existing = g_action_map_lookup_action(OpaquePointer(actions), name)
        let action = existing.map { UnsafeMutableRawPointer($0).assumingMemoryBound(to: GSimpleAction.self) }
            ?? g_simple_action_new(name, nil)!
        g_simple_action_set_enabled(action, entry.isEnabled ? 1 : 0)
        let element = entry.element
        items[name] = { [weak element] in element }
        if existing == nil {
            let number = Self.nextNumber
            Self.nextNumber += 1
            numbers[name] = number
            Self.chosen[number] = { [weak element] in element }
            connectSignal(UnsafeMutableRawPointer(action), "activate", number: number) {
                (_: UnsafeMutableRawPointer?, _: UnsafeMutableRawPointer?, data: gpointer?) in
                MainActor.assumeIsolated { GTKMenu.chosen[viewNumber(data)]?()?.gtk.send(.clicked, []) }
            }
            g_action_map_add_action(OpaquePointer(actions), action)
            g_object_unref(UnsafeMutableRawPointer(action))
        }
        let item = g_menu_item_new(entry.title, Self.actionGroup + "." + name)!
        g_menu_append_item(menu, item)
        g_object_unref(UnsafeMutableRawPointer(item))
    }

    /// Every item's element, by the number its action's signal carries, one across the process.
    private static var chosen: [Int64: () -> MountedElement?] = [:]
    private static var requested: [Int64: () -> MountedElement?] = [:]
    private static var nextNumber: Int64 = 1
}

/// The model of a `GMenu`, as GTK's menus take it.
func g_menu_model(_ menu: OpaquePointer) -> UnsafeMutablePointer<GMenuModel> {
    UnsafeMutablePointer<GMenuModel>(menu)
}
