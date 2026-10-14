// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// The scene's commands behind the button at the title bar's leading edge: a WinUI `Button` whose face is the
/// platform's navigation glyph, a press opening its `Flyout` - the placement groups' entries in it.
/// Design: docs/design/platforms/winui/pages.md#menus
@MainActor
final class WinUIAppMenuButton: WinUIView {
    /// The entries as they were last written.
    private(set) var shown = WinUIMenu()

    init() {
        super.init { number in swiftomniui_winui_app_menu_make(number) }
        swiftomniui_winui_toolbar_button_set_look(handle)
    }

    /// The entries the press opens, the flyout written again only where what it draws changed.
    func show(_ menu: WinUIMenu) {
        menuActions = menu.actions
        guard !menu.draws(like: shown) else { return }

        shown = menu
        WinUIStrings.withCStrings(menu.titles) { titles in
            WinUIStrings.withCStrings(menu.identifiers) { identifiers in
                menu.kinds.withUnsafeBufferPointer { kinds in
                    menu.enabled.withUnsafeBufferPointer { enabled in
                        swiftomniui_winui_menu_button_set_menu(
                            handle, number, kinds.baseAddress, titles, enabled.baseAddress, identifiers,
                            menu.mounts, Int32(kinds.count))
                    }
                }
            }
        }
    }

    override func detach() {
        super.detach()
        shown = WinUIMenu()
    }
}
