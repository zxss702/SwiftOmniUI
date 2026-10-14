// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// A menu living in the view: a WinUI `Button` whose `Flyout` a press opens,
/// the label child its face, a chevron beside it the indicator shows or hides.
/// Design: docs/design/platforms/winui/pages.md#menus
@MainActor
final class WinUIMenuButtonView: WinUIView {
    /// A control: it lays its face and chevron out in the element's direction.
    override var takesDirection: Bool { true }

    /// The entries as they were last written.
    private(set) var shown = WinUIMenu()

    /// The platform's menu button, or - `toolbar` - the same button dressed as the bar's: no ground of its own,
    /// the bar's faint fill under the pointer.
    init(toolbar: Bool = false) {
        super.init { number in toolbar ? swiftomniui_winui_toolbar_menu_button_make(number) : swiftomniui_winui_menu_button_make(number) }
        isToolbarControl = toolbar
    }

    /// The face the press opens the menu from: the label child's view; nil for the chevron alone.
    func setFace(_ face: WinUIView?) {
        swiftomniui_winui_menu_button_set_face(handle, face?.presentationHandle)
    }

    /// Whether the face draws the chevron that says it opens a menu.
    func setIndicator(_ shown: Bool) {
        swiftomniui_winui_menu_button_set_indicator(handle, shown ? 1 : 0)
    }

    /// Whether the trigger draws the platform's frameless look - `.borderlessButton`'s.
    func setBorderless(_ borderless: Bool) {
        swiftomniui_winui_menu_button_set_borderless(handle, borderless ? 1 : 0)
    }

    /// Whether the press opens the menu.
    func setEnabled(_ enabled: Bool) {
        swiftomniui_winui_set_enabled(handle, enabled)
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
