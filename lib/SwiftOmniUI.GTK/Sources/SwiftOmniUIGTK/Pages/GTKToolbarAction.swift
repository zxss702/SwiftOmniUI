// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// One entry a page's header bar holds for the page - an action, a spacer, or the view a `ToolbarItem` carries.
@MainActor
struct GTKToolbarAction {
    let title: String

    /// The picture the button shows in place of its title - the theme's name for a symbol, a file's name for a
    /// picture; nil for the title.
    var icon: String? = nil
    let isEnabled: Bool

    /// Whether the action destroys something: libadwaita's `destructive-action` colours its button.
    var isDestructive = false
    let perform: () -> Void

    /// The view the item shows on the bar, where it stands for one; nil for a titled or pictured button.
    var view: GTKView? = nil
    var spacer: ToolbarSpacerVariant? = nil
    var isAction: Bool { view == nil && spacer == nil }

    /// Whether two actions draw the same button. What an action performs is taken again on every composition.
    func draws(like other: GTKToolbarAction) -> Bool {
        title == other.title && icon == other.icon && isEnabled == other.isEnabled
            && isDestructive == other.isDestructive && view === other.view && spacer == other.spacer
    }
}

/// What a page's header bar shows: the page's title or its title view, the page's actions, the overflow behind the
/// bar's menu, whether the bar shows at all and whether it offers the way back - and the tabs beneath it.
@MainActor
struct GTKPageChrome {
    var title = ""
    var subtitle = ""
    var titleView: GTKView?

    /// A tabbed view's switcher, which stands in a bar of its own beneath the header bar; nil for none.
    var tabs: GTKView?
    var leadingActions: [GTKToolbarAction] = []
    var actions: [GTKToolbarAction] = []
    var overflow: [GTKToolbarAction] = []
    var showsBar = true
    var offersBack = true

    /// What the bar is painted in, and what stands on it in; nil for the platform's.
    var barBackground: HostValue?
    var barForeground: HostValue?

    /// The split view's sidebar, where this page's header bar offers its toggle - the detail's: whether it shows,
    /// and what turns it.
    var sidebar: (shows: Bool, toggle: () -> Void)?

    /// The scene's commands, standing in the window's app menu - a menu button at the header bar's start.
    var appMenu: [MenuEntry] = []

    /// The menus the page's path declares, which stand in the bar's main menu - GNOME's in place of a menu bar.
    var mainMenu: GTKMenu?
}
