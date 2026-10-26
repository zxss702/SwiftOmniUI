// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// A menu living in the view: a WinUI `Button` whose `Flyout` a press opens,
/// the label child filling the content column, a chevron in its own auto column.
/// Design: docs/design/platforms/winui/pages.md#menus
@MainActor
final class WinUIMenuButtonView: WinUIView {
    /// A control: it lays its face and chevron out in the element's direction.
    override var takesDirection: Bool { true }

    /// The entries as they were last written.
    private(set) var shown = WinUIMenu()
    private weak var labelRoot: WinUIView?
    private var attachmentMeasurePending = false
    private var indicatorShown: Bool?
    private var borderlessLook: Bool?

    /// The platform's menu button, or - `toolbar` - the same button dressed as the bar's: no ground of its own,
    /// the bar's faint fill under the pointer.
    init(toolbar: Bool = false) {
        super.init { number in toolbar ? swiftomniui_winui_toolbar_menu_button_make(number) : swiftomniui_winui_menu_button_make(number) }
        isToolbarControl = toolbar
        swiftomniui_winui_menu_button_on_loaded(handle, number) { number in
            MainActor.assumeIsolated {
                guard let menu = WinUIView.find(number) as? WinUIMenuButtonView,
                      !menu.attachmentMeasurePending else { return }
                menu.attachmentMeasurePending = true
                WinUIDoorbell.afterPass { [weak menu] in
                    guard let menu else { return }
                    menu.attachmentMeasurePending = false
                    guard !menu.isDetached, menu.isAttached else { return }
                    // Native templates/resources can change a detached size.
                    // Compare only on attachment, and propagate only a change.
                    if menu.refreshMeasurementsAfterAttachment() {
                        WinUILayoutView.commitAttachedTextMeasurements([menu])
                    }
                }
            }
        }
    }

    /// The face the press opens the menu from: the label child's view; nil for the chevron alone.
    func setFace(_ face: WinUIView?) {
        if labelRoot !== face {
            if labelRoot?.nativeContentOwner === self { labelRoot?.nativeContentOwner = nil }
            labelRoot = face
            face?.nativeContentOwner = self
            invalidateMeasure()
        }
        swiftomniui_winui_menu_button_set_face(handle, face?.presentationHandle)
    }

    /// Whether the face draws the chevron that says it opens a menu.
    func setIndicator(_ shown: Bool) {
        guard indicatorShown != shown else { return }
        indicatorShown = shown
        swiftomniui_winui_menu_button_set_indicator(handle, shown ? 1 : 0)
        invalidateMeasure()
    }

    /// Whether the trigger draws the platform's frameless look - `.borderlessButton`'s.
    func setBorderless(_ borderless: Bool) {
        guard borderlessLook != borderless else { return }
        borderlessLook = borderless
        swiftomniui_winui_menu_button_set_borderless(handle, borderless ? 1 : 0)
        invalidateMeasure()
    }

    /// Whether the press opens the menu.
    /// The entries the press opens, the flyout written again only where what it draws changed.
    func show(_ menu: WinUIMenu) {
        menuActions = menu.actions
        guard !menu.draws(like: shown) else { return }

        shown = menu
        menu.installShortcuts(on: self)
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
        if labelRoot?.nativeContentOwner === self { labelRoot?.nativeContentOwner = nil }
        labelRoot = nil
        swiftomniui_winui_menu_set_shortcuts(handle, number, nil, nil, nil, 0)
        super.detach()
        shown = WinUIMenu()
    }
}
