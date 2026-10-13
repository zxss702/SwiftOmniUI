// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// Pages and their arrangements on GTK: the chrome each page's header bar shows - its title or title view, its
/// actions, whether it offers the way back - and the user's choices handed to the host layer, which tells the pages
/// and the states.
/// Design: docs/design/platforms/gtk/pages.md
extension GTKElement {
    /// What stands in a frame of its own, with a header bar: a page, and a tabbed view.
    static let framedTypes: Set<NodeType> = [.page, .tabView]

    /// The tab the user chose on a tabbed view, which the host layer shows.
    var chosenTab: Int? {
        (view as? GTKTabbedView)?.choice.chosen
    }

    /// Whether a split view's sidebar shows on screen.
    var showsSidebar: Bool? {
        (view as? GTKSplitView)?.isPresented
    }

    // MARK: - The header bar

    /// What a framed element's header bar shows. A page's own: its title or title view, its actions as the host layer
    /// orders them, whether its bar shows and whether it offers the way back. A tabbed view's: the chosen tab's
    /// page's, named by the page that names the window (`titledPage`), its switcher beneath the bar.
    /// Design: docs/design/platforms/gtk/pages.md#the-chrome
    var chrome: GTKPageChrome {
        if type == .tabView {
            var chrome = element.selectedTab?.visiblePage?.gtk.chrome ?? GTKPageChrome()
            chrome.title = element.titledPage?.pageValue(.title)?.string
                ?? element.enclosing(type: .windowScene)?.value(.title)?.string ?? ""
            chrome.subtitle = element.titledPage?.pageValue(.subtitle)?.string ?? ""
            chrome.tabs = (view as? GTKTabbedView)?.switcher
            chrome.showsBar = value(.hasNavigationBar)?.bool != false
            chrome.offersBack = value(.hasBackButton)?.bool != false
            (chrome.barBackground, chrome.barForeground) = element.barColors
            return chrome
        }

        let page = element.chromePage
        var chrome = GTKPageChrome()
        chrome.title = page.pageValue(.title)?.string ?? ""
        chrome.subtitle = page.pageValue(.subtitle)?.string ?? ""
        chrome.titleView = page.slotContent(.titleView)?.gtk.view
        chrome.showsBar = page.pageValue(.hasNavigationBar)?.bool != false
        chrome.offersBack = page.pageValue(.hasBackButton)?.bool != false
        (chrome.barBackground, chrome.barForeground) = page.barColors
        if let window = element.enclosing(type: .windowScene) {
            let arrangement = window.currentChildren.first { NodeType.pageTypes.contains($0.type) }
            let composed = WindowChrome(window: window, arrangement: arrangement)
            if composed.toolbarVisibility?.enumeration == Visibility.hidden.rawValue { chrome.showsBar = false }
            if composed.toolbarBackground?.enumeration == Visibility.hidden.rawValue {
                chrome.barBackground = Color.clear.propValue
            }
        }
        let actions = page.chromeActions
        chrome.leadingActions = actions.leading.map(Self.action)
        chrome.actions = actions.primary.map(Self.action)
        chrome.overflow = actions.overflow.map(Self.action)
        let menus = page.children.first { $0.type == .menuBar }.map { MenuEntry.menus(of: $0) } ?? []
        chrome.mainMenu = menus.isEmpty ? nil : GTKMenu(menus)
        return chrome
    }

    /// The scene's menus as the app menu's entries - a command group's entries
    /// spliced where they stand, a `CommandMenu` a submenu.
    static func appMenuEntries(of element: MountedElement) -> [MenuEntry] {
        guard let menus = element.enclosing(type: .windowScene)?.currentChildren.first(where: { $0.type == .menuBar })
        else { return [] }
        return MenuEntry.flattened(MenuEntry.menus(of: menus))
    }

    /// A page's toolbar entry as a widget of its header bar: a spacer's room, the view an item carries, or a
    /// titled or pictured action.
    private static func action(_ item: MountedElement) -> GTKToolbarAction {
        // A symbol is the icon theme's name for it, a picture its file: `GTKPictures.icon` tells them apart.
        let picture = item.value(.icon).flatMap(ImageSource.init(propValue:))
        var action = GTKToolbarAction(
            title: item.value(.text)?.string ?? "", icon: picture?.symbol ?? picture.flatMap { $0.file.isEmpty ? nil : $0.file },
            isEnabled: item.value(.isEnabled)?.bool ?? true,
            perform: { [weak item] in item?.gtk.send(.clicked, []) })
        action.isDestructive = item.value(.isDestructive)?.bool == true
        if item.type == .toolbarSpacer {
            action.spacer = ToolbarSpacerVariant(rawValue: item.value(.variant)?.enumeration ?? 0)
        } else {
            action.view = item.children.lazy.compactMap(\.presentingElement).first?.gtk.view
        }
        return action
    }

    /// The first visible native header this arrangement carries. A wrapper page is not necessarily framed;
    /// stacks and split panes carry the actual frames, and tabs use the frame supplied by their parent.
    var leadingHeaderFrame: GTKPageFrame? {
        func header(_ frame: GTKPageFrame?, of page: GTKElement?) -> GTKPageFrame? {
            if let frame, page?.chrome.showsBar == true { return frame }
            return page?.leadingHeaderFrame
        }
        switch type {
        case .page:
            return element.contentArrangement?.gtk.leadingHeaderFrame
        case .navigationStack:
            return header((view as? GTKNavigationView)?.frames.last, of: element.stackedChildren.last?.gtk)
        case .navigationSplitView:
            guard let split = view as? GTKSplitView else { return nil }
            if element.sidebarIsVisible, let frame = header(split.sidebarFrame, of: children.first) { return frame }
            if split.showsDetailColumn {
                if split.showsContentColumn,
                   let frame = header(split.contentFrame, of: children.dropFirst().first) { return frame }
                return header(split.detailFrame, of: children.last)
            }
            return header(split.detailFrame, of: children.dropFirst().first)
        case .tabView:
            return element.selectedTab?.gtk.leadingHeaderFrame
        default:
            return nil
        }
    }

    /// Writes each framed element's chrome on its header bar, through this arrangement and every one it holds;
    /// `sidebar` shows a split view's sidebar from the header bar of the page the user sees in its detail.
    func composeChrome(
        showingSidebar sidebar: (shows: Bool, toggle: () -> Void)? = nil,
        show: (GTKPageFrame, GTKPageChrome) -> Void = { frame, chrome in frame.show(chrome) }
    ) {
        switch type {
        case .page:
            element.contentArrangement?.gtk.composeChrome(showingSidebar: sidebar, show: show)
        case .navigationStack:
            guard let navigation = view as? GTKNavigationView else { return }
            let pages = element.stackedChildren.map(\.gtk)
            for (index, (page, frame)) in zip(pages, navigation.frames).enumerated() {
                var chrome = page.chrome
                if index == pages.count - 1 { chrome.sidebar = sidebar }
                show(frame, chrome)
                navigation.describe(
                    frame, title: page.element.visiblePage?.pageValue(.title)?.string ?? "", canPop: chrome.offersBack)
                page.composeChrome(show: show)
            }
        case .navigationSplitView:
            guard let split = view as? GTKSplitView else { return }
            let shows = element.sidebarIsVisible
            let showing: (shows: Bool, toggle: () -> Void) = (shows, { [weak self] in
                self?.changeSidebarVisibility(to: !shows)
            })
            if let sidebar = children.first {
                if let frame = split.sidebarFrame { show(frame, sidebar.chrome) }
                sidebar.composeChrome(show: show)
            }
            if split.showsDetailColumn, let content = children.dropFirst().first {
                if let frame = split.contentFrame { show(frame, content.chrome) }
                content.composeChrome(show: show)
            }
            let detail = split.showsDetailColumn ? children.last : children.dropFirst().first
            if let detail {
                if let frame = split.detailFrame {
                    var chrome = detail.chrome
                    chrome.sidebar = showing
                    show(frame, chrome)
                    detail.composeChrome(show: show)
                } else {
                    detail.composeChrome(showingSidebar: showing, show: show)
                }
            }
        case .tabView:
            element.selectedTab?.gtk.composeChrome(show: show)
        default:
            break
        }
    }

    /// Keeps an arrangement's own parts with the tree: a stack hears the user take its top page away, a tabbed view
    /// names its tabs and hears the user choose one, a split view shows its sidebar as the tree says.
    func arrangePages(changed: Set<Prop>) {
        switch type {
        case .navigationStack:
            (view as? GTKNavigationView)?.onPopped = { [weak self] remaining in self?.userPopped(remaining: remaining) }
        case .tabView:
            guard let tabs = view as? GTKTabbedView else { return }
            tabs.show(children.map { $0.value(.title)?.string ?? "" }, requested: value(.currentPage)?.number.map { Int($0) })
            tabs.onSelection = { [weak self] previous, selected in self?.tabChosen(from: previous, to: selected) }
        case .navigationSplitView:
            guard let split = view as? GTKSplitView else { return }
            split.onPresentationChanged = { [weak self] presented in self?.sidebarChanged(to: presented) }
            split.onVisibilityChanged = { [weak self] visibility in self?.columnsChanged(to: visibility) }
            if changed.contains(.isSidebarVisible) { split.present(value(.isSidebarVisible)?.bool == true) }
            if changed.contains(.columnVisibility), let visibility = value(.columnVisibility) {
                split.present(visibility: NavigationSplitViewVisibility(propValue: visibility) ?? .automatic)
            }
        default:
            break
        }
    }

    /// The user chose another tab: the host layer tells the pages and the state, and the chrome follows what the user
    /// sees now whether or not the application renders again.
    private func tabChosen(from previous: Int, to selected: Int) {
        host?.runtime.tabChosen(element, from: previous, to: selected)
        host?.refreshChrome()
    }

    // MARK: - The way back, and the sidebar

    /// Takes the visible stack's top page away as the user does; whether there was one to take.
    func goBack() -> Bool {
        guard let stack = element.visibleBackStack else { return false }
        if let navigation = stack.gtk.view as? GTKNavigationView { return navigation.popByUser() }

        return (stack.parent?.enclosing(type: .page)?.enclosing(type: .navigationStack)?.gtk.view
            as? GTKNavigationView)?.popByUser() ?? false
    }

    /// The user took the stack's top pages away - the back button, the swipe, the keys: the path is told how long
    /// it is now.
    private func userPopped(remaining: Int) {
        guard type == .navigationStack else { return }
        let ownCount = element.currentChildren.count
        if remaining >= ownCount, let nested = element.currentChildren.last?.visibleNavigationStack,
           nested !== element, nested.currentChildren.count > 1, let handler = nested.handler(.popped) {
            host?.runtime.dispatch(handler, payload: [.number(Double(remaining - ownCount))])
            return
        }
        guard let handler = element.handler(.popped) else { return }
        host?.runtime.dispatch(handler, payload: [.number(Double(remaining - 1))])
    }

    /// The user showed or hid a split view's sidebar through a header bar's button - a three-column split's answer
    /// is a visibility, a two-column one's a Bool.
    func changeSidebarVisibility(to presented: Bool) {
        guard type == .navigationSplitView, let split = view as? GTKSplitView, split.isPresented != presented else { return }

        if split.hasContentColumn {
            split.present(visibility: presented ? .all : .doubleColumn)
            columnsChanged(to: presented ? .all : .doubleColumn)
        } else {
            split.present(presented)
            sidebarChanged(to: presented)
        }
    }

    /// The sidebar showed or hid: the host layer tells its page and the state, and the chrome follows.
    func sidebarChanged(to presented: Bool) {
        host?.runtime.sidebarShown(element, presented)
        host?.refreshChrome()
    }

    /// The split's columns showed or hid: the host layer tells the pages and the state, and the chrome follows.
    func columnsChanged(to visibility: NavigationSplitViewVisibility) {
        host?.runtime.columnsShown(element, visibility)
        host?.refreshChrome()
    }
}
