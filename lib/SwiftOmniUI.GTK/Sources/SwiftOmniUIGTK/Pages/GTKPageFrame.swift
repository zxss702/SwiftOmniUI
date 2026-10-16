// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIGTK

/// A page as GNOME's applications stand one: an `AdwToolbarView` whose top bar is the page's own `AdwHeaderBar` -
/// and a tabbed view's tabs in a bar beneath it - over the page's view. In a navigation view the frame slides with its page, header bar and all.
/// Design: docs/design/platforms/gtk/pages.md#a-page-and-its-header-bar
@MainActor
final class GTKPageFrame {
    /// The toolbar view, held until the frame goes.
    let widget: GTKWidget

    /// The page's view, which the toolbar view shows under its bar.
    let page: GTKView

    /// What the header bar shows now.
    private(set) var chrome = GTKPageChrome()

    let header: GTKWidget
    private let heading: GTKWidget
    private let actionsBox: GTKWidget
    private let menuBox: GTKWidget

    /// The bar's main menu - GNOME's in place of a menu bar - and the menus it holds; nil while the page declares none.
    private(set) var mainMenu: (button: GTKWidget, menu: GTKMenu)?
    private var leadingBox: GTKWidget?
    private(set) var buttons: [GTKButtonView] = []
    private(set) var leadingButtons: [GTKButtonView] = []
    private var sidebarButton: GTKButtonView?
    private(set) var appMenuButton: GTKMenuButtonView?
    /// What the app menu last showed, for writing it again only where it changed.
    private var appMenuDrawn: [MenuEntry] = []
    private var overflowButton: GTKWidget?
    fileprivate var overflowPopover: GTKWidget?

    /// The bar beneath the header bar holding a tabbed view's switcher, where the page has one.
    private var tabsBar: GTKWidget?

    private var safeBars: [GTKSafeAreaBarHost] = []
    private var scrollEdges: [(scroller: GTKScrollerView, ear: GTKScrollEar)] = []
    private var scrollEdgePending = false

    /// The style sheet's class painting the header bar, and the tabs' bar with it.
    private var barClass: String?
    private(set) var overflowButtons: [GTKButtonView] = []

    init(page: GTKView) {
        self.page = page
        widget = adw_toolbar_view_new()!
        g_object_ref_sink(widget)
        header = adw_header_bar_new()!
        // Held by the frame too: a title view takes its place in the bar, and the bar lets go of it there.
        heading = adw_window_title_new("", nil)!
        g_object_ref_sink(heading)
        adw_header_bar_set_title_widget(header.opaque, heading)
        actionsBox = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6)!
        adw_header_bar_pack_end(header.opaque, actionsBox)
        menuBox = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6)!
        adw_header_bar_pack_end(header.opaque, menuBox)
        adw_toolbar_view_add_top_bar(widget.opaque, header)
        var previous = gtk_widget_get_parent(page.widget)
        while let parent = previous {
            if g_type_check_instance_is_a(parent.of(GTypeInstance.self), adw_toolbar_view_get_type()) != 0,
               adw_toolbar_view_get_content(parent.opaque) == page.widget {
                adw_toolbar_view_set_content(parent.opaque, nil)
                break
            }
            previous = gtk_widget_get_parent(parent)
        }
        adw_toolbar_view_set_content(widget.opaque, page.widget)
        page.safeAreaContext = nil
        page.rootSafeAreaContext = { [weak self] bounds in
            guard let self else { return SafeAreaContext(bounds: bounds) }
            let headerHeight = self.chrome.showsBar ? Double(gtk_widget_get_height(self.header)) : 0
            let tabsHeight = self.tabsBar.map { Double(gtk_widget_get_height($0)) } ?? 0
            let top = headerHeight + tabsHeight
            if self.safeBars.isEmpty {
                // Native row layout already excluded chrome from this
                // allocation, but did not consume its safe-area environment.
                return SafeAreaContext(bounds: bounds,
                                       consumed: EdgeInsets(top: top, leading: 0, bottom: 0, trailing: 0))
            }
            // The content extends below all top bars. Reserve the native
            // header here; source inset modifiers reserve their own bars.
            return SafeAreaContext(bounds: bounds).padding(
                EdgeInsets(top: top, leading: 0, bottom: 0, trailing: 0))
        }
    }

    /// Returns promoted bars to local placement before releasing the frame.
    /// GTK can still own the departing page through its navigation slide.
    isolated deinit {
        page.rootSafeAreaContext = nil
        for watched in scrollEdges {
            watched.ear.owner = nil
            gtk_widget_remove_css_class(watched.scroller.widget, GTKStyleSheet.mergedTopBarScroll)
        }
        for host in safeBars {
            adw_toolbar_view_remove(widget.opaque, host.widget)
            host.releaseBar()
        }
        adw_toolbar_view_set_extend_content_to_top_edge(widget.opaque, 0)
        g_object_unref(heading)
        g_object_unref(widget)
    }

    /// Shows `chrome` on the header bar, writing only what differs from what it shows.
    func show(_ chrome: GTKPageChrome) {
        if chrome.title != self.chrome.title { adw_window_title_set_title(heading.opaque, chrome.title) }
        if chrome.subtitle != self.chrome.subtitle {
            adw_window_title_set_subtitle(heading.opaque, chrome.subtitle)
        }
        if chrome.titleView !== self.chrome.titleView {
            adw_header_bar_set_title_widget(header.opaque, chrome.titleView?.widget ?? heading)
        }
        if chrome.showsBar != self.chrome.showsBar {
            gtk_widget_set_visible(header, chrome.showsBar ? 1 : 0)
            adw_toolbar_view_set_reveal_top_bars(widget.opaque, chrome.showsBar || !safeBars.isEmpty ? 1 : 0)
        }
        if chrome.offersBack != self.chrome.offersBack {
            adw_header_bar_set_show_back_button(header.opaque, chrome.offersBack ? 1 : 0)
        }
        if chrome.tabs !== self.chrome.tabs { showTabs(chrome.tabs) }
        if chrome.barBackground != self.chrome.barBackground || chrome.barForeground != self.chrome.barForeground {
            paintBar(background: chrome.barBackground, foreground: chrome.barForeground)
        }
        showAppMenu(chrome.appMenu)
        showMainMenu(chrome.mainMenu)
        showSidebarButton(chrome.sidebar)
        showActions(leading: chrome.leadingActions, chrome.actions, overflow: chrome.overflow)
        self.chrome = chrome
        refreshSafeBars()
    }

    private func refreshSafeBars() {
        let bars = page.sourceElement?.pageTopSafeAreaBars.compactMap { $0.gtk.view } ?? []
        guard bars.count != safeBars.count || !zip(bars, safeBars).allSatisfy({ $0 === $1.bar }) else {
            refreshScrollEdges()
            return
        }
        for host in safeBars {
            adw_toolbar_view_remove(widget.opaque, host.widget)
            host.releaseBar()
        }
        safeBars = bars.map { GTKSafeAreaBarHost(bar: $0) }
        for host in safeBars {
            if let barClass { gtk_widget_add_css_class(host.widget, barClass) }
            adw_toolbar_view_add_top_bar(widget.opaque, host.widget)
        }
        adw_toolbar_view_set_extend_content_to_top_edge(widget.opaque, safeBars.isEmpty ? 0 : 1)
        adw_toolbar_view_set_reveal_top_bars(widget.opaque, chrome.showsBar || !safeBars.isEmpty ? 1 : 0)
        refreshScrollEdges()
        (page as? GTKLayoutView)?.invalidateMeasurements()
    }

    private func refreshScrollEdges() {
        var scrollers: [GTKScrollerView] = []
        func collect(_ element: MountedElement) {
            guard element.value(.isVisible)?.bool != false else { return }
            if let scroll = element.gtk.view as? GTKScrollView {
                scrollers.append(scroll.scroller)
                return // Nested scrolling has its own edge and lifecycle.
            }
            let children = element.currentChildren
            if element.safeAreaInsetEdge != nil {
                if let base = children.first { collect(base) }
            } else {
                for child in children { collect(child) }
            }
        }
        if chrome.showsBar || !safeBars.isEmpty, let source = page.sourceElement { collect(source) }
        for watched in scrollEdges where !scrollers.contains(where: { $0 === watched.scroller }) {
            watched.ear.owner = nil
            gtk_widget_remove_css_class(watched.scroller.widget, GTKStyleSheet.mergedTopBarScroll)
        }
        scrollEdges = scrollers.map { scroller in
            if let existing = scrollEdges.first(where: { $0.scroller === scroller }) { return existing }
            gtk_widget_add_css_class(scroller.widget, GTKStyleSheet.mergedTopBarScroll)
            let ear = GTKScrollEar(owner: self) { [weak self] in self?.requestScrollEdge() }
            scroller.ears.append(ear)
            return (scroller, ear)
        }
        requestScrollEdge()
    }

    private func requestScrollEdge() {
        guard !scrollEdgePending else { return }
        scrollEdgePending = true
        GTKDoorbell.afterLayout { [weak self] in
            guard let self else { return }
            self.scrollEdgePending = false
            // Extend-content disables AdwToolbarView's flat undershoot. Use
            // its raised native surface at the complete top region's lower
            // edge, driven by the owning scroll offset, outside allocation.
            let scrolled = self.scrollEdges.contains { $0.scroller.standing.offset.y > 0.5 }
            let style = scrolled ? ADW_TOOLBAR_RAISED : ADW_TOOLBAR_FLAT
            if adw_toolbar_view_get_top_bar_style(self.widget.opaque) != style {
                adw_toolbar_view_set_top_bar_style(self.widget.opaque, style)
            }
        }
    }

    /// The scene's commands in the window's app menu - a menu button at the
    /// header bar's start, ahead of the sidebar's toggle; gone for none.
    private func showAppMenu(_ entries: [MenuEntry]) {
        if entries.isEmpty {
            if let appMenuButton { adw_header_bar_remove(header.opaque, appMenuButton.widget) }
            appMenuButton = nil
            appMenuDrawn = []
            return
        }
        if appMenuButton == nil {
            let button = GTKMenuButtonView()
            gtk_menu_button_set_icon_name(button.widget.opaque, "open-menu-symbolic")
            button.showsArrow = false
            adw_header_bar_pack_start(header.opaque, button.widget)
            appMenuButton = button
        }
        func matches(_ entries: [MenuEntry], _ previous: [MenuEntry]) -> Bool {
            entries.count == previous.count && zip(entries, previous).allSatisfy {
                $0.kind == $1.kind && $0.title == $1.title && $0.isEnabled == $1.isEnabled
                    && $0.element === $1.element && matches($0.entries, $1.entries)
            }
        }
        guard !matches(entries, appMenuDrawn) else { return }
        appMenuButton?.setEntries(entries)
        appMenuDrawn = entries
    }

    /// Paints the header bar and what stands on it, as a class of the host's style sheet; nil keeps the platform's.
    private func paintBar(background: HostValue?, foreground: HostValue?) {
        let painted = GTKStyleSheet.bar(
            background: GTKBrush(background).firstColor, foreground: foreground.flatMap(GTKBrush.rgba))
        for bar in [header] + (tabsBar.map { [$0] } ?? []) + safeBars.map(\.widget) {
            if let barClass { gtk_widget_remove_css_class(bar, barClass) }
            if let painted { gtk_widget_add_css_class(bar, painted) }
        }
        barClass = painted
    }

    /// The tabs' switcher at the start of a bar of its own beneath the header bar, which scrolls it across where the
    /// page is narrower than its tabs: the header bar keeps its room for the title and the buttons.
    /// Design: docs/design/platforms/gtk/pages.md#tabs
    private func showTabs(_ tabs: GTKView?) {
        if let tabsBar { adw_toolbar_view_remove(widget.opaque, tabsBar) }
        tabsBar = nil
        guard let tabs else { return }

        if let row = gtk_widget_get_parent(tabs.widget),
           g_type_check_instance_is_a(row.of(GTypeInstance.self), gtk_box_get_type()) != 0 {
            gtk_box_remove(row.of(GtkBox.self), tabs.widget)
        }
        let row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0)!
        gtk_widget_add_css_class(row, "toolbar")
        gtk_box_append(row.of(GtkBox.self), tabs.widget)
        let bar = gtk_scrolled_window_new()!
        gtk_scrolled_window_set_policy(bar.opaque, GTK_POLICY_AUTOMATIC, GTK_POLICY_NEVER)
        gtk_scrolled_window_set_propagate_natural_height(bar.opaque, 1)
        gtk_scrolled_window_set_child(bar.opaque, row)
        if let barClass { gtk_widget_add_css_class(bar, barClass) }
        adw_toolbar_view_add_top_bar(widget.opaque, bar)
        tabsBar = bar
    }

    /// The sidebar's toggle at the bar's start, pressed in while the sidebar shows, while the page offers it.
    private func showSidebarButton(_ sidebar: (shows: Bool, toggle: () -> Void)?) {
        guard let sidebar else {
            if let sidebarButton { adw_header_bar_remove(header.opaque, sidebarButton.widget) }
            sidebarButton = nil
            return
        }
        if sidebarButton == nil {
            let button = GTKButtonView(toggles: true)
            gtk_button_set_icon_name(button.widget.of(GtkButton.self), "sidebar-left-symbolic")
            gtk_widget_set_tooltip_text(button.widget, "Toggle Sidebar")
            adw_header_bar_pack_start(header.opaque, button.widget)
            sidebarButton = button
        }
        sidebarButton?.onClicked = sidebar.toggle
        gtk_toggle_button_set_active(sidebarButton?.widget.of(GtkToggleButton.self), sidebar.shows ? 1 : 0)
    }

    /// The sidebar's toggle, where the bar shows one.
    var sidebarToggle: GTKButtonView? { sidebarButton }

    /// The page's actions as buttons at the bar's end, in order, its leading
    /// actions at the bar's start, and the overflow behind a menu after them.
    /// A spacer stands as room between them, an item's view as the view itself.
    private func showActions(leading: [GTKToolbarAction], _ actions: [GTKToolbarAction], overflow: [GTKToolbarAction]) {
        let same = leading.count == chrome.leadingActions.count && zip(leading, chrome.leadingActions).allSatisfy { $0.draws(like: $1) }
            && actions.count == chrome.actions.count && zip(actions, chrome.actions).allSatisfy { $0.draws(like: $1) }
            && overflow.count == chrome.overflow.count && zip(overflow, chrome.overflow).allSatisfy { $0.draws(like: $1) }
        guard !same else {
            for (button, action) in zip(leadingButtons, leading.filter(\.isAction)) { button.onClicked = action.perform }
            for (button, action) in zip(buttons, actions.filter(\.isAction)) { button.onClicked = action.perform }
            for (button, action) in zip(overflowButtons, overflow) { button.onClicked = closingOverflow(action) }
            return
        }

        overflowButton = nil
        overflowPopover = nil
        overflowButtons = []
        if !leading.isEmpty, leadingBox == nil {
            let box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6)!
            adw_header_bar_pack_start(header.opaque, box)
            leadingBox = box
        } else if leading.isEmpty, let leadingBox {
            adw_header_bar_remove(header.opaque, leadingBox)
            self.leadingBox = nil
        }
        if let leadingBox { refill(leadingBox, entries: leading, buttons: &leadingButtons) }
        else { leadingButtons = [] }
        refill(actionsBox, entries: actions, buttons: &buttons)
        guard !overflow.isEmpty else { return }

        let list = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        let popover = gtk_popover_new()!
        overflowPopover = popover
        overflowButtons = overflow.map { action in
            let button = GTKButtonView.action(action, inMenu: true)
            button.onClicked = closingOverflow(action)
            gtk_box_append(list.of(GtkBox.self), button.widget)
            return button
        }
        gtk_popover_set_child(popover.of(GtkPopover.self), list)
        let menu = gtk_menu_button_new()!
        gtk_menu_button_set_icon_name(menu.opaque, "view-more-symbolic")
        gtk_menu_button_set_popover(menu.opaque, popover)
        // The overflow's own menu stands over what its button drops on, as a page menu's does.
        GTKHoverHold.watch(menuButton: menu)
        gtk_box_append(actionsBox.of(GtkBox.self), menu)
        overflowButton = menu
    }
}

extension GTKPageFrame {
    /// Refills `box` with `entries`' widgets - a button for an action, the
    /// item's own view, or room for a spacer - recording the buttons.
    private func refill(_ box: GTKWidget, entries: [GTKToolbarAction], buttons: inout [GTKButtonView]) {
        while let child = gtk_widget_get_first_child(box) {
            gtk_box_remove(box.of(GtkBox.self), child)
        }
        buttons = []
        for entry in entries {
            let widget: GTKWidget
            if entry.spacer == .fixed {
                widget = gtk_separator_new(GTK_ORIENTATION_VERTICAL)!
            } else if entry.spacer != nil {
                let room = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0)!
                gtk_widget_set_hexpand(room, 1)
                widget = room
            } else if let view = entry.view {
                if let parent = gtk_widget_get_parent(view.widget),
                   g_type_check_instance_is_a(parent.of(GTypeInstance.self), gtk_box_get_type()) != 0 {
                    gtk_box_remove(parent.of(GtkBox.self), view.widget)
                }
                widget = view.widget
            } else {
                let button = GTKButtonView.action(entry)
                buttons.append(button)
                widget = button.widget
            }
            gtk_box_append(box.of(GtkBox.self), widget)
        }
    }

    /// The menus at the bar's very end, as GNOME's applications hold theirs: a main menu holding each as a submenu.
    /// Design: docs/design/platforms/gtk/pages.md#menus
    private func showMainMenu(_ menu: GTKMenu?) {
        if let mainMenu, let menu, !menu.isEmpty {
            mainMenu.menu.replace(with: menu)
            return
        }
        if let mainMenu { gtk_box_remove(menuBox.of(GtkBox.self), mainMenu.button) }
        mainMenu = nil
        guard let menu, !menu.isEmpty else { return }

        let button = gtk_menu_button_new()!
        gtk_menu_button_set_icon_name(button.opaque, "open-menu-symbolic")
        gtk_widget_set_tooltip_text(button, "Main Menu")
        gtk_menu_button_set_menu_model(button.opaque, g_menu_model(menu.model))
        GTKHoverHold.watch(menuButton: button)
        gtk_widget_insert_action_group(button, GTKMenu.actionGroup, OpaquePointer(menu.actions))
        gtk_box_append(menuBox.of(GtkBox.self), button)
        mainMenu = (button, menu)
    }

    /// `action`, closing the overflow's menu first.
    private func closingOverflow(_ action: GTKToolbarAction) -> () -> Void {
        { [weak self] in
            if let popover = self?.overflowPopover { gtk_popover_popdown(popover.of(GtkPopover.self)) }
            action.perform()
        }
    }
}

extension GTKButtonView {
    /// A button performing `action`: on the header bar its picture as an icon, else its title; in the overflow's
    /// menu its title, flat; coloured where it destroys something.
    /// Design: docs/design/platforms/gtk/pages.md#the-chrome
    static func action(_ action: GTKToolbarAction, inMenu: Bool = false) -> GTKButtonView {
        let button = GTKButtonView()
        button.showsPictureAlone = !inMenu
        button.setText(action.title)
        button.setPictureNamed(inMenu ? nil : action.icon)
        button.setEnabled(action.isEnabled)
        if inMenu { gtk_widget_add_css_class(button.widget, "flat") }
        if action.isDestructive {
            gtk_widget_add_css_class(button.widget, "destructive-action")
            if inMenu { gtk_widget_add_css_class(button.widget, GTKStyleSheet.destructiveWords) }
        }
        button.onClicked = action.perform
        return button
    }
}
