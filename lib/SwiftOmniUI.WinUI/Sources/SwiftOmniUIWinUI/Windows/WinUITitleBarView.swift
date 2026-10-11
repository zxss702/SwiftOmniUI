// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// The one chrome of a SwiftOmniUI window: WinUI's `TitleBar`. WinUI owns placement, overflow, the caption buttons and
/// dragging the window; SwiftOmniUI owns what stands on it - its way back and sidebar toggle as the bar's own buttons,
/// an action as a button of its command bar, an authored slot's view attached as it is.
/// Design: docs/design/platforms/winui/pages.md#the-windows-chrome
@MainActor
final class WinUITitleBarView: WinUIView {
    /// The chrome the bar shows, as it was last composed.
    private(set) var chrome = WinUIWindowChrome()

    /// The actions as they were last drawn, the primary ones first.
    private var drawn: [WinUIToolbarAction] = []
    private var drawnOverflow: [Bool] = []
    /// The scene's commands' button, while a placement group gives it entries.
    private var appMenuButton: WinUIAppMenuButton?

    init() {
        super.init { number in swiftomniui_winui_title_bar_make(number) }
    }

    /// Shows `chrome`, writing only the parts that changed.
    func apply(_ chrome: WinUIWindowChrome) {
        let previous = self.chrome
        self.chrome = chrome

        let background = chrome.background?.argb
        let foreground = chrome.foreground?.argb
        // Words on a bar the tree paints: light on a dark one, dark on a light one (`BandWords`).
        let light = chrome.background.flatMap(BandWords.light(on:))
        if previous.title != chrome.title || (previous.back == nil) != (chrome.back == nil)
            || (previous.sidebarToggle == nil) != (chrome.sidebarToggle == nil)
            || previous.background != chrome.background || previous.foreground != chrome.foreground {
            swiftomniui_winui_title_bar_set(
                handle, chrome.title, chrome.back != nil, chrome.sidebarToggle != nil,
                background != nil, background ?? 0, foreground != nil, foreground ?? 0, light.map { $0 ? 1 : 2 } ?? 0)
        }

        let actions = chrome.leadingActions + chrome.actions + chrome.overflow
        let overflows = (chrome.leadingActions + chrome.actions).map { _ in false } + chrome.overflow.map { _ in true }
        if actions.count != drawn.count || overflows != drawnOverflow || chrome.leadingActions.count != previous.leadingActions.count
            || !zip(actions, drawn).allSatisfy({ $0.draws(like: $1) }) {
            WinUIStrings.withCStrings(actions.map(\.title)) { titles in
                WinUIStrings.withCStrings(actions.map { $0.identifier ?? "" }) { identifiers in
                    WinUIStrings.withCStrings(actions.map { $0.icon.map { $0 + "\n" }.joined() }) { icons in
                    WinUIStrings.withCStrings(actions.map { $0.symbol ?? "" }) { symbols in
                        swiftomniui_winui_title_bar_set_actions(
                            handle, titles, identifiers, icons, symbols, overflows, actions.map(\.isEnabled),
                            actions.map(\.view?.handle), actions.map { $0.spacer.map { Int32($0.rawValue) + 1 } ?? 0 },
                            Int32(actions.count), Int32(chrome.leadingActions.count))
                    }
                    }
                }
            }
            drawnOverflow = overflows
        }
        drawn = actions

        showAppMenu(chrome.appMenu)

        if previous.leading !== chrome.leading || previous.center !== chrome.center
            || previous.trailing !== chrome.trailing {
            swiftomniui_winui_title_bar_set_slots(handle, chrome.leading?.handle, chrome.center?.handle, chrome.trailing?.handle)
        }
    }

    /// Stands the commands' button at the bar's leading edge while a placement group gives it entries; an empty
    /// menu takes it away.
    private func showAppMenu(_ menu: WinUIMenu) {
        if menu.isEmpty {
            if appMenuButton != nil {
                swiftomniui_winui_title_bar_set_app_menu(handle, nil)
                appMenuButton?.detach()
                appMenuButton = nil
            }
            return
        }
        if appMenuButton == nil {
            let button = WinUIAppMenuButton()
            appMenuButton = button
            swiftomniui_winui_title_bar_set_app_menu(handle, button.handle)
        }
        appMenuButton?.show(menu)
    }

    /// The user pressed the way back (-1), the sidebar's toggle (-2), or an action by its place.
    override func chose(_ index: Int) {
        switch index {
        case -1: if let sheet = chrome.sheet { sheet.back() } else { chrome.back?.perform() }
        case -2: chrome.sidebarToggle?()
        case -3: chrome.sheet?.dismiss()
        default: if drawn.indices.contains(index), drawn[index].isEnabled { drawn[index].perform() }
        }
    }

    override func detach() {
        super.detach()
        chrome = WinUIWindowChrome()
        drawn = []
        appMenuButton?.detach()
        appMenuButton = nil
    }
}
