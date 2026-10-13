// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore

/// The one chrome a window composes from what it shows, the same on every host: its title, the way back, the visible
/// page's actions, what stands in the title's place and beside it, the bars' colours, the page's menus and the
/// sidebar's toggle - elements and values a host turns into its toolkit's chrome.
/// Design: docs/design/host/pages.md#the-windows-chrome
@_spi(Host) @MainActor public struct WindowChrome {
    /// The title of the page that names the window (`titledPage`), else the window's; nil where neither names one,
    /// which leaves the host's own.
    public var title: String?

    /// The second line the naming page asks the title area to show; nil where it asks none.
    public var subtitle: String?

    /// The document the naming page stands for, as its path; nil where it stands for none.
    public var document: String?

    /// The colour the naming page asks the window to paint behind everything; nil where it asks none.
    public var windowBackground: HostValue?

    /// Whether the naming page shows the window's own toolbar: nil for the platform's own choice.
    public var toolbarVisibility: HostValue?

    /// Whether the naming page has the window's own toolbar paint its background: nil for the platform's own.
    public var toolbarBackground: HostValue?

    /// The stack whose top page the way back takes, and the way back's words.
    public var back: (stack: MountedElement, title: String)?

    /// The visible page's actions at the chrome's leading edge - navigation
    /// and the cancelling action - by priority, then in the order written.
    public var leadingActions: [MountedElement] = []

    /// The visible page's actions on the chrome, by priority, then in the order written.
    public var primaryActions: [MountedElement] = []

    /// The visible page's actions behind the overflow, in the same order.
    public var overflowActions: [MountedElement] = []

    /// What stands at the chrome's leading edge: the title bar's leading content.
    public var leading: MountedElement?

    /// What stands in the title's place: the title bar's content, else the visible page's title view.
    public var center: MountedElement?

    /// What stands at the chrome's trailing edge: the title bar's trailing content.
    public var trailing: MountedElement?

    /// The bars' colour: the nearest stack's or tabbed view's around the visible page, else the title bar's.
    public var background: HostValue?

    /// The colour of what stands on the bars: the nearest stack's, else the title bar's.
    public var foreground: HostValue?

    /// The visible page's menu bar.
    public var menuBar: MountedElement?

    /// The scene's own menus - `.commands` on the scene and on its window
    /// groups, hanging off the window - standing whichever page shows. A menu
    /// in it carrying a `placement` is a command group's: its entries splice
    /// into the platform's own menus rather than standing as one.
    public var commands: MountedElement?

    /// The split view whose sidebar the chrome's toggle shows and hides: the one the window shows.
    public var sidebarToggle: MountedElement?

    /// The chrome of `window` showing `arrangement`.
    public init(window: MountedElement, arrangement: MountedElement?) {
        let page = arrangement?.visiblePage
        let titleBar = window.children.first { $0.type == .titleBar }
        title = arrangement?.titledPage?.pageValue(.title)?.string ?? window.value(.title)?.string
        subtitle = arrangement?.titledPage?.pageValue(.subtitle)?.string
            ?? arrangement?.value(.subtitle)?.string
        document = arrangement?.titledPage?.pageValue(.document)?.string
            ?? arrangement?.value(.document)?.string
        windowBackground = arrangement?.titledPage?.pageValue(.windowBackground)
            ?? arrangement?.pageValue(.windowBackground)
        toolbarVisibility = arrangement?.titledPage?.pageValue(.toolbarVisibility)
            ?? arrangement?.pageValue(.toolbarVisibility)
        toolbarBackground = arrangement?.titledPage?.pageValue(.toolbarBackground)
            ?? arrangement?.pageValue(.toolbarBackground)
        back = arrangement?.visibleBackStack.map { stack in
            let pages = stack.currentChildren
            return (stack, pages[pages.count - 2].value(.backButtonTitle)?.string ?? "Back")
        }
        if let page { (leadingActions, primaryActions, overflowActions) = page.chromeActions }
        leading = titleBar?.slotContent(.leadingContent)
        center = titleBar?.slotContent(.content) ?? page?.slotContent(.titleView)
        trailing = titleBar?.slotContent(.trailingContent)
        (background, foreground) = (page ?? window).barColors
        menuBar = page?.children.first { $0.type == .menuBar }
        commands = window.children.first { $0.type == .menuBar }
        sidebarToggle = arrangement?.visibleSplitView
    }

    /// Whether the chrome shows what an element of `type` moves on a frame: a window's frame, a title bar's own
    /// colours, a stack's or a tabbed view's bar colours - the chrome is composed again as they move.
    public static func follows(_ type: NodeType) -> Bool {
        followed.contains(type)
    }

    private static let followed: Set<NodeType> = [.windowScene, .titleBar, .navigationStack, .tabView, .navigationSplitView]
}
