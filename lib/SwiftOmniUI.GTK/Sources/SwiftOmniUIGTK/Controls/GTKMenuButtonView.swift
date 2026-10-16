// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIGTK

/// A `GtkMenuButton`: its face a label child's widget or a chevron alone, its
/// menu a `GMenu` model whose items activate `GSimpleAction`s wired back to the
/// elements that own them.
@MainActor
final class GTKMenuButtonView: GTKView {
    /// The menu the button shows, holding its model and action group while it lasts.
    private(set) var menu: GTKMenu?

    /// A menu button, face a chevron until a label child's widget lands.
    init() {
        super.init { _ in gtk_menu_button_new() }
        connectSignal(UnsafeMutableRawPointer(widget), "notify::active", number: number) {
            (_: UnsafeMutableRawPointer?, _: UnsafeMutableRawPointer?, data: gpointer?) in
            MainActor.assumeIsolated {
                guard let view = GTKView.find(viewNumber(data)) as? GTKMenuButtonView,
                      gtk_menu_button_get_active(view.widget.opaque) != 0 else { return }
                view.sourceElement?.children.first { $0.type == .contextMenu }?.gtk.send(
                    ContextMenuContract.contentRequested.token, [])
            }
        }
    }

    /// The widget the button's face draws; GTK keeps its own arrow beside it.
    func setFace(_ face: GTKWidget?) {
        gtk_menu_button_set_child(widget.opaque, face)
    }

    /// Whether the button opens its menu - `.isEnabled`'s.
    var opensMenu = true {
        didSet { if opensMenu != oldValue { gtk_widget_set_sensitive(widget, opensMenu ? 1 : 0) } }
    }

    /// How the trigger draws: a `borderlessButton` keeps the label with no
    /// button frame around it.
    private var flatClass: String?
    var borderless = false {
        didSet {
            guard borderless != oldValue else { return }
            gtk_menu_button_set_has_frame(widget.opaque, borderless ? 0 : 1)
            swapClass(&flatClass, to: borderless ? "flat" : nil)
        }
    }

    /// Whether the trigger shows the arrow that says it opens a menu.
    var showsArrow = true {
        didSet {
            if showsArrow != oldValue {
                gtk_menu_button_set_always_show_arrow(widget.opaque, showsArrow ? 1 : 0)
            }
        }
    }

    /// Updates the live menu model and its actions from `entries`; a chosen item
    /// sends `clicked` to its element through `GTKMenu`.
    func setEntries(_ entries: [MenuEntry]) {
        if let menu {
            menu.replace(entries)
            return
        }
        let menu = GTKMenu(entries)
        gtk_widget_insert_action_group(widget, GTKMenu.actionGroup, OpaquePointer(menu.actions))
        menu.installShortcuts(on: widget)
        gtk_menu_button_set_menu_model(widget.opaque, g_menu_model(menu.model))
        // The popover GTK makes of the model it was handed: a menu stands over what its button drops on.
        GTKHoverHold.watch(menuButton: widget)
        self.menu = menu
    }
}
