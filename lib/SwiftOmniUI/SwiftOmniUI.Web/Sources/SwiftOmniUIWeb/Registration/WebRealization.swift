// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// What this host realizes beyond its registry - the library's elements it makes none of, which it shows by name as
/// unsupported - and, member by member, what its records say: the Web column of the control dictionary.
/// Design: docs/design/contracts/dictionary.md#marks
enum WebRealization {
    /// The elements the host makes itself, outside the registry: the pages, the arrangements they stand in, and
    /// what a window lays over them.
    static let madeByHost: Set<NodeType> = [.page, .navigationStack, .navigationSplitView, .tabView, .overlay]

    /// The entries this host leaves to the application, which registers its own control for each: the browser has
    /// no map of its own, and a map needs a provider and its key.
    static let byApplication: Set<String> = ["Map", "Pin"]

    /// The entries this host presents with no view of their own: a span is a run of its text's words.
    static let viewless: Set<String> = ["Span"]

    /// What the host's own records say, member by member, before what its registry says: what it realizes through
    /// the host layer's pages and chrome, outside the registry, and what a page never asks of the browser's window.
    static let records: [HostRecord] = [
        // MARK: Tiers - a member every wearer realizes alike
        .complete("BarElement", "barBackgroundColor"),
        .complete("TitleBar", "barForegroundColor"),
        .notPlanned("TitleBar", "icon",
                    reason: "A page's bar names its page and the application, and no mark: the browser's tab shows the site's icon."),
        .complete("TitleBar", "subtitle"),
        .complete("TitleBar", "title"),
        .complete("Menu", "isEnabled"),
        .complete("Menu", "text"),
        .complete("MenuItemElement", "clicked"),
        .complete("MenuItemElement", "icon"),
        .complete("MenuItemElement", "isDestructive"),
        .complete("MenuItemElement", "isEnabled"),
        .complete("MenuItemElement", "text"),
        .complete("PageElement", "title"),
        .complete("VisualElement", "style"),
        .unrealized("List", "style", why: "No style can name a List: a style names its control by an "
            + "initializer that sets nothing, which a list of some items has not."),

        // MARK: Entries - a control's or a part's own
        .complete("WindowScene", "modalPopped"),
        .complete("NavigationStack", "popped"),
        .complete("Page", "appearing"),
        .complete("Page", "backButtonTitle"),
        .complete("Page", "background"),
        .complete("Page", "disappearing"),
        .complete("Page", "navigatedFrom"),
        .complete("Page", "navigatedTo"),
        .complete("Page", "navigatingFrom"),
        .complete("Page", "hasBackButton"),
        .complete("Page", "hasNavigationBar"),
        .complete("NavigationSplitView", "isSidebarVisible"),
        .complete("NavigationSplitView", "isSidebarVisibleChanged"),
        .complete("TabView", "currentPage"),
        .complete("TabView", "currentPageChanged"),
        .complete("Span", "background"),
        .complete("Span", "fontAttributes"),
        .complete("Span", "fontFamily"),
        .complete("Span", "fontSize"),
        .complete("Span", "text"),
        .complete("Span", "textCase"),
        .complete("Span", "foregroundStyle"),
        .complete("Span", "textDecorations"),
        .complete("Span", "characterSpacing"),
        .complete("ToolbarItem", "placement"),
        .complete("Scene", "activated"),
        .complete("Scene", "deactivated"),
        .complete("Scene", "stopped"),
        .notPlanned("Scene", "windowClosed", reason: "A page's one window closes with its tab, which hears nothing after."),
        .notPlanned("WindowScene", "windowType", reason: "A page is one window: it opens none of a kind."),
        .notPlanned("WindowScene", "windowValue", reason: "A page is one window: it opens none for a value."),
        .complete("WindowScene", "activated"),
        .complete("WindowScene", "created"),
        .complete("WindowScene", "deactivated"),
        .complete("WindowScene", "destroying"),
        .complete("WindowScene", "resumed"),
        .complete("WindowScene", "stopped"),
        .notPlanned("WindowScene", "floatsOnTop", reason: "A page keeps no browser window above the others: the system stacks them."),
        .notPlanned("WindowScene", "height", reason: "A page sizes no browser window: the user does, and the page fills it."),
        .notPlanned("WindowScene", "hidesWhenInactive",
                    reason: "The browser shows a page whenever its tab shows, whichever application the user is in."),
        .notPlanned("WindowScene", "isMaximizable", reason: "A page asks nothing of how the browser's window is resized."),
        .notPlanned("WindowScene", "isMinimizable", reason: "A page asks nothing of how the browser's window is put away."),
        .notPlanned("WindowScene", "isTranslucent",
                    reason: "A page draws its window opaque: no material of the system shows through it."),
        .notPlanned("WindowScene", "maximumHeight", reason: "A page bounds no browser window: the user sizes it."),
        .notPlanned("WindowScene", "maximumWidth", reason: "A page bounds no browser window: the user sizes it."),
        .notPlanned("WindowScene", "minimumHeight", reason: "A page bounds no browser window: the user sizes it."),
        .notPlanned("WindowScene", "minimumWidth", reason: "A page bounds no browser window: the user sizes it."),
        .complete("WindowScene", "title"),
        .notPlanned("WindowScene", "width", reason: "A page sizes no browser window: the user does, and the page fills it."),
        .notPlanned("WindowScene", "x", reason: "A page places no browser window: the system does."),
        .notPlanned("WindowScene", "y", reason: "A page places no browser window: the system does."),
    ]

    /// The acts this host performs: every host's (`HostActs.performed`), a list scrolled to an item, and a web view's
    /// steps and scripts.
    static let acts: [any ContractMember] = HostActs.performed + [
        ListContract.scrollTo, WebViewContract.goBack, WebViewContract.goForward, WebViewContract.reload,
        WebViewContract.evaluateJavaScript, CanvasContract.measureText,
    ]

    @MainActor static var unmade: Set<String> {
        Set(LibraryContracts.elements.map { $0.nodeType.name })
            .subtracting(WebRegistrations.registry.realization.elements)
            .subtracting(NodeType.viewlessTypes.map(\.name))
            .subtracting(madeByHost.map(\.name))
    }

    /// What the Web realizes, member by member: these records before what its registry says.
    @MainActor static var register: HostRegister {
        let registry = WebRegistrations.registry
        return HostRegister(
            records: records, unrealized: unmade.subtracting(byApplication), viewless: viewless
        ).and(HostDeclaration(realization: registry.realization, shared: registry.sharedNames, acts: acts.map(\.name)))
    }
}
