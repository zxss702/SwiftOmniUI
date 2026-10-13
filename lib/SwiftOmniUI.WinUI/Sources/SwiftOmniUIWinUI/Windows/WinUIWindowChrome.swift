// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// What a window's chrome shows, composed from the visible arrangement and an authored `TitleBar`: the title, the
/// way back and the sidebar's toggle, the page's actions and those in overflow, three slots, the bar's colours, and
/// the page's menus beneath.
/// Design: docs/design/platforms/winui/pages.md#the-windows-chrome
@MainActor
struct WinUIWindowChrome {
    var title = ""
    var subtitle = ""
    var showsToolbar = true
    var back: WinUIToolbarAction?
    var sidebarToggle: (() -> Void)?
    var leading: WinUIView?
    var center: WinUIView?
    var trailing: WinUIView?
    var leadingActions: [WinUIToolbarAction] = []
    var actions: [WinUIToolbarAction] = []
    var overflow: [WinUIToolbarAction] = []
    var background: HostValue?
    var foreground: HostValue?
    var menuBar = WinUIMenu()

    /// The scene's commands behind the app menu's button at the bar's leading edge - a placement group's entries,
    /// which stand for the platform's own menus on this family.
    var appMenu = WinUIMenu()

    /// While a sheet shows: its way back - its own stack's, else it going - and it going, which Escape asks.
    var sheet: (back: () -> Void, dismiss: () -> Void)?
}
