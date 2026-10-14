// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// Pages and their arrangements on WinUI: a tabbed view's row and a split view's pane kept with the tree, and the
/// user's choices on them handed to the host layer, which tells the pages and the states.
/// Design: docs/design/platforms/winui/pages.md
extension WinUIElement {
    /// The tab the user chose on a tabbed view, which the host layer shows.
    var chosenTab: Int? {
        (view as? WinUITabbedView)?.choice.chosen
    }

    /// Whether a split view's sidebar shows on screen.
    var showsSidebar: Bool? {
        (view as? WinUISplitView)?.isPresented
    }
    var showsContentColumn: Bool? { (view as? WinUISplitView)?.isContentPresented }
    var showsDetailColumn: Bool? { (view as? WinUISplitView)?.showsDetailColumn }

    /// Keeps an arrangement's own parts with the tree: a tabbed view's row, a split view's sidebar.
    func arrangePages(changed: Set<Prop>) {
        switch type {
        case .tabView:
            guard let tabs = view as? WinUITabbedView else { return }
            tabs.tabsShownByWindow = element.tabsStandInWindow
            tabs.show(
                children.map { child in
                    // A badge stands by its tab's title in brackets, the way
                    // the platform counts in tab labels.
                    let title = child.element.pageValue(.title)?.string ?? ""
                    guard let badge = child.element.pageValue(.badge)?.string, !badge.isEmpty else { return title }
                    return title.isEmpty ? badge : "\(title) (\(badge))"
                },
                requested: value(.currentPage)?.number.map { Int($0) })
            tabs.onSelection = { [weak self] previous, selected in self?.tabChosen(from: previous, to: selected) }
        case .navigationSplitView:
            guard let split = view as? WinUISplitView else { return }
            // The split's first room is decided inside a layout pass, and said once the pass is over.
            split.onPresentationChanged = { [weak self] presented in
                WinUIDoorbell.afterPass { [weak self] in self?.sidebarShown(presented) }
            }
            split.onVisibilityChanged = { [weak self] visibility in
                WinUIDoorbell.afterPass { [weak self] in self?.columnsShown(visibility) }
            }
            if changed.contains(.isSidebarVisible) { split.present(value(.isSidebarVisible)?.bool == true) }
            if changed.contains(.columnVisibility), let visibility = value(.columnVisibility) {
                split.present(visibility: NavigationSplitViewVisibility(propValue: visibility) ?? .automatic)
            }
        default:
            break
        }
    }

    /// The user chose another tab: the host layer tells the pages and the state, and the window's chrome follows what
    /// the user sees whether or not the application renders again.
    private func tabChosen(from previous: Int, to selected: Int) {
        host?.runtime.tabChosen(element, from: previous, to: selected)
        host?.refreshWindowChrome()
    }

    /// The user showed or hid a split view's sidebar through the window's chrome.
    func changeSidebarVisibility(to presented: Bool) {
        guard type == .navigationSplitView, let split = view as? WinUISplitView, split.isPresented != presented else { return }

        if split.hasContentColumn {
            split.present(visibility: presented ? .all : .doubleColumn)
            columnsShown(presented ? .all : .doubleColumn)
        } else {
            split.present(presented)
            sidebarShown(presented)
        }
    }

    /// The sidebar showed or hid: the host layer tells its page and the state, and the chrome follows.
    private func sidebarShown(_ presented: Bool) {
        host?.runtime.sidebarShown(element, presented)
        host?.refreshWindowChrome()
    }

    /// The split's columns showed or hid: the host layer tells the pages and the state, and the chrome follows.
    private func columnsShown(_ visibility: NavigationSplitViewVisibility) {
        host?.runtime.columnsShown(element, visibility)
        host?.refreshWindowChrome()
    }
}
