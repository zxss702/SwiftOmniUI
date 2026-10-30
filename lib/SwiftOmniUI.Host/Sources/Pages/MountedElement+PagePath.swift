// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore

/// What an arrangement of pages shows, the same on every host: a stack's top page, the chosen tab, a split view's
/// detail and, while it shows, its sidebar.
/// Design: docs/design/host/pages.md#the-page-path
extension MountedElement {
    /// The split on the active page path, including one wrapped in a page or stack.
    public var visibleSplitView: MountedElement? {
        switch type {
        case .navigationSplitView: self
        case .page: contentArrangement?.visibleSplitView
        case .navigationStack: currentChildren.last?.visibleSplitView
        case .tabView: selectedTab?.visibleSplitView
        default: nil
        }
    }

    /// The page the user sees in this arrangement: a stack's top, the chosen tab, a split view's detail.
    public var visiblePage: MountedElement? {
        switch type {
        case .page: contentArrangement?.visiblePage ?? self
        case .navigationStack: currentChildren.last?.visiblePage
        case .tabView: selectedTab?.visiblePage
        case .navigationSplitView: currentChildren.dropFirst().first?.visiblePage
        default: nil
        }
    }

    /// The arrangement this page's content composes to, found down its arranged
    /// children. Slots stay with their owner; a found arrangement keeps its own.
    public var contentArrangement: MountedElement? {
        if hasCachedContentArrangement { return cachedContentArrangement }
        var found: MountedElement?
        for child in currentChildren {
            found = NodeType.pageTypes.contains(child.type) ? child : child.contentArrangement
            if found != nil { break }
        }
        cachedContentArrangement = found
        hasCachedContentArrangement = true
        return found
    }

    /// Every branch examined by contentArrangement caches its answer. A
    /// changed branch therefore invalidates just that path; an already dirty
    /// branch stops repeated propagation while a lazy patch adds many rows.
    func invalidateContentArrangement() {
        guard hasCachedContentArrangement else { return }
        hasCachedContentArrangement = false
        cachedContentArrangement = nil
        parent?.invalidateContentArrangement()
    }

    /// The page whose title names the window while this arrangement shows: the visible page, but tabs on a stack are
    /// its last place and name the window by their own title, else by the page beneath - their pages name their tabs
    /// alone; nil for none.
    /// Design: docs/design/host/pages.md#the-windows-chrome
    public var titledPage: MountedElement? {
        switch type {
        case .page: return contentArrangement?.titledPage ?? self
        case .navigationStack: return currentChildren.last?.titledPage
        case .navigationSplitView: return currentChildren.dropFirst().first?.titledPage
        case .tabView:
            if let tab = selectedTab, tab.type != .page { return tab.titledPage }
            guard let stack = parent, stack.type == .navigationStack else { return selectedTab }
            if value(.title) != nil { return self }
            let place = stack.currentChildren.firstIndex { $0 === self } ?? 0
            return place > 0 ? stack.currentChildren[place - 1].titledPage : selectedTab
        default: return nil
        }
    }

    /// The page whose bar stands at the arrangement's leading edge: a split view's sidebar while it shows, the
    /// visible page otherwise.
    public var leadingPage: MountedElement? {
        switch type {
        case .navigationSplitView where sidebarIsVisible: currentChildren.first?.leadingPage
        default: visiblePage
        }
    }

    /// The page's own value of `prop`, else the nearest one its content carries: a `.navigationTitle` written on a
    /// branch of the content names the page itself. The walk keeps slots and nested arrangements to their owners.
    public func pageValue(_ prop: Prop) -> HostValue? {
        if let found = value(prop) { return found }
        guard type == .page else { return nil }
        return contentValueBelow(prop)
    }

    /// The naming page's navigation metadata, falling back through its enclosing arrangements.
    /// An explicit empty value stops inheritance. Sidebar/auxiliary columns and presented content
    /// keep their own titles rather than borrowing the main window's detail title.
    public func navigationValue(_ prop: Prop) -> HostValue? {
        var current: MountedElement? = titledPage ?? self
        while let element = current {
            if element.type == .windowScene {
                return element.currentChildren.first { $0.type == .titleBar }?.value(prop) ?? element.value(prop)
            }
            if let found = element.pageValue(prop) { return found }
            guard let parent = element.parent,
                  parent.type != .modalStack, parent.type != .overlay
            else { return nil }
            if parent.type == .navigationSplitView,
               parent.currentChildren.dropFirst().first !== element { return nil }
            current = parent
        }
        return nil
    }

    /// This element's `prop`, else the nearest one below it; slots and nested arrangements stand in no page's path.
    private func contentValue(_ prop: Prop) -> HostValue? {
        value(prop) ?? contentValueBelow(prop)
    }

    /// The nearest `prop` among the current children's content, walked in place - the walk runs every render.
    private func contentValueBelow(_ prop: Prop) -> HostValue? {
        for child in children where !child.isDeparting && !NodeType.slotTypes.contains(child.type)
            && !NodeType.pageTypes.contains(child.type) {
            if let found = child.contentValue(prop) { return found }
        }
        return nil
    }

    /// The stack around the visible page, where the path has one.
    public var visibleNavigationStack: MountedElement? {
        switch type {
        case .page: contentArrangement?.visibleNavigationStack
        case .navigationStack: self
        case .tabView: selectedTab?.visibleNavigationStack
        case .navigationSplitView: currentChildren.dropFirst().first?.visibleNavigationStack
        default: nil
        }
    }

    /// Whether this stack's pushes are shown by the stack around its page; its own view keeps only the root.
    var mergesIntoPageStack: Bool {
        guard type == .navigationStack, let page = parent?.enclosing(type: .page),
              page.contentArrangement === self
        else { return false }
        return page.parent?.enclosing(type: .navigationStack) != nil
    }

    /// The stack's items as a host shows them: a top page's own stack joins it, its pushed pages above.
    public var stackedChildren: [MountedElement] {
        let shown = currentChildren
        guard type == .navigationStack else { return shown }
        if mergesIntoPageStack { return Array(shown.prefix(1)) }
        guard let top = shown.last,
              let nested = top.contentArrangement, nested.type == .navigationStack,
              nested.currentChildren.count > 1
        else { return shown }

        return Array(shown.dropLast()) + [top] + nested.currentChildren.dropFirst()
    }

    /// The page whose chrome this page shows: itself, or the visible page of a stack merged through it.
    public var chromePage: MountedElement {
        guard type == .page, contentArrangement?.type == .navigationStack else { return self }
        return visiblePage ?? self
    }

    /// Whether the stack this element stands on shows its bar over it: over a page that keeps its bar, and over an
    /// arrangement only where the page it shows stands in no stack of its own - that stack's bar is the one.
    public var showsTheStacksBar: Bool {
        guard let page = visiblePage, page.pageValue(.hasNavigationBar)?.bool != false else { return false }
        return type == .page || visibleNavigationStack == nil
    }

    /// The first tabbed view on the visible page path.
    public var visibleTabbedView: MountedElement? {
        switch type {
        case .page: contentArrangement?.visibleTabbedView
        case .tabView: self
        case .navigationStack: currentChildren.last?.visibleTabbedView
        case .navigationSplitView: currentChildren.dropFirst().first?.visibleTabbedView
        default: nil
        }
    }

    /// What this arrangement shows while it is shown itself: a stack's top page, the chosen tab, a split view's
    /// detail and - while it shows - its sidebar.
    public var shownChildren: [MountedElement] {
        switch type {
        case .page: return contentArrangement.map { [$0] } ?? []
        case .navigationStack: return currentChildren.last.map { [$0] } ?? []
        case .tabView: return selectedTab.map { [$0] } ?? []
        case .navigationSplitView:
            let columns = currentChildren
            let sidebar = sidebarIsVisible ? Array(columns.prefix(1)) : []
            guard columns.count > 2 else { return Array(columns.dropFirst().prefix(1)) + sidebar }
            let hasDetail = native.showsDetailColumn
                ?? (SplitColumnWidth(columns.last?.pageValue(.preferredColumnWidth)?.numbers).maximum != 0)
            guard hasDetail else { return [columns[1]] + sidebar }
            let showsContent = native.showsContentColumn
                ?? (value(.columnVisibility)?.enumeration != NavigationSplitViewVisibility.detailOnly.rawValue)
            return (showsContent ? [columns[1]] : []) + [columns[2]] + sidebar
        default: return []
        }
    }

    /// The tab a tabbed view shows: the one the user chose, else the one the tree says, within the tabs.
    public var selectedTab: MountedElement? {
        let children = currentChildren
        guard !children.isEmpty else { return nil }

        let chosen = native.chosenTab ?? Int(value(.currentPage)?.number ?? 0)
        return children[min(max(chosen, 0), children.count - 1)]
    }

    /// Whether a split view shows its sidebar: as it stands on screen, else as the tree says.
    public var sidebarIsVisible: Bool {
        native.showsSidebar ?? (value(.isSidebarVisible)?.bool == true)
    }

    /// The visible stack whose top page can go back. A stack merged into a page takes its own pushes first; once it
    /// is back at its root, the stack around the page takes the way back.
    public var visibleBackStack: MountedElement? {
        var stack = visiblePage?.parent?.enclosing(type: .navigationStack)
        while let candidate = stack {
            guard candidate.currentChildren.count > 1 else {
                stack = candidate.parent?.enclosing(type: .navigationStack)
                continue
            }
            guard let top = candidate.visiblePage,
                  top.pageValue(.hasNavigationBar)?.bool != false,
                  top.pageValue(.hasBackButton)?.bool != false
            else { return nil }
            return candidate
        }
        return nil
    }

    /// Whether a tabbed view's tabs stand in its window's row: the first tabbed view down the window's stacks and
    /// split view details - never one in a sidebar, in a tab of another, in a sheet or in content. A split view's
    /// sidebar is its first child as written, which holds while the children are still being made.
    public var tabsStandInWindow: Bool {
        guard type == .tabView else { return false }

        var child = self
        while let parent = child.parent {
            switch parent.type {
            case .windowScene: return true
            case .navigationStack, .page: break
            case .navigationSplitView where parent.writingOrder[child.id] != 0: break
            default: return false
            }
            child = parent
        }
        return false
    }
}
