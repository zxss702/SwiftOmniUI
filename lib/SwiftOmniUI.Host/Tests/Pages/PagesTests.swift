// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) @testable import SwiftOmniUICore
@_spi(Host) @testable import SwiftOmniUIHost
import XCTest

/// What an arrangement of pages shows, the phases its pages hear, and the chrome and the way back a window offers,
/// the same on every host.
@MainActor
final class PagesTests: XCTestCase {
    private func node(
        _ id: String, _ type: NodeType, _ properties: [Prop: HostValue] = [:], events: [Event: Int32] = [:],
        children: [HostPatch] = []
    ) -> HostPatch {
        var patch = HostPatch(id: .manual(id), type: type)
        patch.properties = properties
        patch.events = .replace(events)
        patch.children = .arranged(children)
        return patch
    }

    /// A runtime holding `root`, whose phases are written down in the order told.
    private func runtime(_ root: HostPatch, told: @escaping (Int32) -> Void) -> HostRuntime {
        let runtime = HostRuntime.still()
        runtime.tree.apply(root, complete: true)
        runtime.tree.tellPhase = told
        return runtime
    }

    private func stackWindow(_ pages: [HostPatch]) -> HostPatch {
        node("window", .windowScene, events: [.created: 1], children: [node("stack", .navigationStack, children: pages)])
    }

    private let first = [Event.appearing: Int32(2), .navigatedTo: 3]
    private let second = [Event.appearing: Int32(4), .navigatedTo: 5, .navigatingFrom: 6, .disappearing: 7,
                          .navigatedFrom: 8]

    /// A window's visible page hears it is shown, navigated to as its stack's top, and then the window that it was
    /// made - before the host shows it.
    func testAWindowTellsItsPageThenThatItWasMade() throws {
        var told: [Int32] = []
        let runtime = runtime(stackWindow([node("a", .page, events: first), node("b", .page, events: second)])) {
            told.append($0)
        }

        _ = WindowPresentation().show(try XCTUnwrap(runtime.tree.root), in: runtime.lifecycle)

        XCTAssertEqual(told, [4, 5, 1])
        try checkPagePathAfterNestedTopologyChanges()
    }

    private func checkPagePathAfterNestedTopologyChanges() throws {
        let runtime = runtime(node("outer", .page, children: [
            node("branch", .grid, children: [node("words", .text)])
        ])) { _ in }
        let outer = try XCTUnwrap(runtime.tree.root)
        XCTAssertNil(outer.contentArrangement)
        XCTAssertNil(outer.contentArrangement)
        let branch = try XCTUnwrap(outer.first(id: .manual("branch")))
        let navigation = node("navigation", .navigationStack, children: [node("detail", .page)])
        var update = HostPatch(id: .manual("outer"), type: .page)
        update.children = .changed([node("branch", .grid, children: [navigation])])
        runtime.tree.apply(update, complete: false)
        let nested = try XCTUnwrap(outer.first(id: .manual("navigation")))
        XCTAssertTrue(outer.contentArrangement === nested,
                      "insertion below a cached empty branch must refresh the page path")
        XCTAssertEqual(outer.visiblePage?.id, .manual("detail"))
        branch.isDeparting = true
        XCTAssertNil(outer.contentArrangement, "departing branches no longer own the page path")
        branch.isDeparting = false
        XCTAssertTrue(outer.contentArrangement === nested, "revival restores the arrangement")
        update.children = .changed([node("branch", .grid, children: [
            node("toolbar", .toolbarItems, children: [navigation]), node("words", .text)
        ])])
        runtime.tree.apply(update, complete: false)
        XCTAssertNil(outer.contentArrangement, "slot content must not become the page's arrangement")
        update.children = .changed([node("branch", .grid, children: [
            node("first", .navigationStack), node("second", .navigationStack)
        ])])
        runtime.tree.apply(update, complete: false)
        XCTAssertEqual(outer.contentArrangement?.id, .manual("first"))
        update.children = .changed([node("branch", .grid, children: [
            node("second", .navigationStack), node("first", .navigationStack)
        ])])
        runtime.tree.apply(update, complete: false)
        XCTAssertEqual(outer.contentArrangement?.id, .manual("second"), "reordering replaces the cached first match")
        update.children = .changed([node("branch", .grid, children: [node("words", .text)])])
        runtime.tree.apply(update, complete: false)
        XCTAssertNil(outer.contentArrangement, "removal invalidates a previously found arrangement")
    }

    /// A pop tells the page leaving everything it hears on a move before the page arriving hears anything.
    func testAPopTellsTheLeavingPageBeforeTheArrivingOne() throws {
        var told: [Int32] = []
        let runtime = runtime(stackWindow([node("a", .page, events: first), node("b", .page, events: second)])) {
            told.append($0)
        }
        _ = WindowPresentation().show(try XCTUnwrap(runtime.tree.root), in: runtime.lifecycle)
        told = []

        runtime.tree.apply(stackWindow([node("a", .page, events: first)]), complete: false)

        XCTAssertEqual(told, [6, 7, 8, 2, 3])
    }

    /// A tabbed view's tabs stand in the window's row down its stacks and split view details, and nowhere else.
    func testTabsStandInTheWindowDownItsStacksAndDetails() throws {
        let tabs = { (id: String) in self.node(id, .tabView, children: [self.node("\(id).page", .page)]) }
        let runtime = runtime(node("window", .windowScene, children: [
            node("split", .navigationSplitView, children: [
                tabs("sidebar"),
                node("stack", .navigationStack, children: [node("detail", .tabView, children: [tabs("inner")])]),
            ]),
            node("sheets", .modalStack, children: [tabs("sheet")]),
        ])) { _ in }
        let root = try XCTUnwrap(runtime.tree.root)
        let stands = { (id: String) in root.first(id: .manual(id))?.tabsStandInWindow }

        XCTAssertEqual(stands("detail"), true)
        XCTAssertEqual(stands("sidebar"), false, "a sidebar keeps its own row")
        XCTAssertEqual(stands("inner"), false, "a tab of another keeps its own row")
        XCTAssertEqual(stands("sheet"), false, "a sheet keeps its own row")
    }

    /// A stack shows its bar over a page that keeps one, and over tabs only where the chosen tab stands in no stack of
    /// its own, whose bar is the one.
    func testAStacksBarShowsOnlyWhereNoStackBelowHasOne() throws {
        let hidden = [Prop.hasNavigationBar: HostValue.bool(false)]
        let runtime = runtime(node("window", .windowScene, children: [node("stack", .navigationStack, children: [
            node("page", .page),
            node("bare", .page, hidden),
            node("pages", .tabView, children: [node("tab", .page)]),
            node("stacks", .tabView, children: [node("inner", .navigationStack, children: [node("top", .page)])]),
        ])])) { _ in }
        let root = try XCTUnwrap(runtime.tree.root)
        let shows = { (id: String) in root.first(id: .manual(id))?.showsTheStacksBar }

        XCTAssertEqual(shows("page"), true)
        XCTAssertEqual(shows("bare"), false, "a page hiding its bar")
        XCTAssertEqual(shows("pages"), true, "tabs of pages wear the bar of the stack they stand on")
        XCTAssertEqual(shows("stacks"), false, "a tab that is a stack has a bar of its own")
    }

    /// Where a tabbed view's tabs stand is already right as it is applied, while the tree that holds it is made.
    func testTabsStandRightWhileTheirTreeIsMade() {
        var read: [String: Bool] = [:]
        let runtime = HostRuntime(
            clock: StillClock(), reducesMotion: { false },
            makeNative: { TabsReading($0) { read[$0] = $1 } }, log: { _ in })
        let tabs = { (id: String) in self.node(id, .tabView, children: [self.node("\(id).page", .page)]) }

        runtime.tree.apply(
            node("window", .windowScene, children: [node("split", .navigationSplitView, children: [tabs("sidebar"), tabs("detail")])]),
            complete: true)

        XCTAssertEqual(read, ["sidebar": false, "detail": true])
    }

    /// A tab the tree asks for anew is chosen; the user's choice stands where it is another tab there is.
    func testATabChoiceFollowsTheTreeAndTheUser() {
        var choice = TabChoice()
        XCTAssertEqual(choice.shown, 0)
        XCTAssertFalse(choice.request(nil))
        XCTAssertTrue(choice.request(2))
        XCTAssertFalse(choice.request(2), "asked again, nothing changes")
        XCTAssertEqual(choice.choose(1, of: 3), 2, "the tab shown before")
        XCTAssertNil(choice.choose(1, of: 3), "the tab shown already")
        XCTAssertNil(choice.choose(5, of: 3), "no such tab")
        XCTAssertEqual(choice.shown, 1)
    }

    /// The tab shown among the tabs there are: the chosen one while it is there, else the last - one answer for the
    /// view and its row; none among no tabs.
    func testTheTabShownIsOneOfTheTabsThereAre() {
        var choice = TabChoice()
        XCTAssertEqual(choice.shown(among: 3), 0)
        _ = choice.request(2)
        XCTAssertEqual(choice.shown(among: 3), 2)
        XCTAssertEqual(choice.shown(among: 2), 1, "the chosen tab gone, the last there is")
        XCTAssertNil(choice.shown(among: 0))
    }

    /// Only the first room wider than nothing decides: a room at least the breakpoint shows a hidden sidebar.
    func testASidebarShowsOnTheFirstWideRoomOnly() {
        var adaptation = SidebarAdaptation()
        XCTAssertFalse(adaptation.room(0, breakpoint: 700, shown: false), "no room yet")
        XCTAssertTrue(adaptation.room(900, breakpoint: 700, shown: false))
        XCTAssertFalse(adaptation.room(900, breakpoint: 700, shown: false), "decided once")

        var narrow = SidebarAdaptation()
        XCTAssertFalse(narrow.room(500, breakpoint: 700, shown: false))
    }

    /// The chrome takes the visible page's actions by priority then order, the overflow apart, the way back's words
    /// from the page beneath, the title bar's content over the page's title view, and the stack's colour first.
    func testTheChromeIsComposedFromWhatTheWindowShows() throws {
        let item = { (id: String, priority: Double, overflow: Bool) in
            self.node(id, .toolbarItem, [
                .priority: .number(priority),
                .placement: .enumeration(overflow ? ToolbarItemPlacement.overflow.rawValue : 0),
            ])
        }
        let runtime = runtime(node("window", .windowScene, children: [
            node("bar", .titleBar, [.background: .string("bar")], children: [
                node("slot", .content, children: [node("search", .text)]),
            ]),
            node("stack", .navigationStack, [.barBackgroundColor: .string("stack")], children: [
                node("home", .page, [.backButtonTitle: .string("Home")]),
                node("detail", .page, [.title: .string("Detail")], children: [
                    node("items", .toolbarItems, children: [
                        item("late", 2, false), item("more", 0, true), item("first", 1, false), item("next", 1, false),
                    ]),
                    node("view", .titleView, children: [node("words", .text)]),
                ]),
            ]),
        ])) { _ in }
        let root = try XCTUnwrap(runtime.tree.root)

        let chrome = WindowChrome(window: root, arrangement: root.first(id: .manual("stack")))
        XCTAssertEqual(chrome.title, "Detail")
        XCTAssertEqual(chrome.back?.title, "Home")
        XCTAssertEqual(chrome.primaryActions.map(\.id), [.manual("first"), .manual("next"), .manual("late")])
        XCTAssertEqual(chrome.overflowActions.map(\.id), [.manual("more")])
        XCTAssertEqual(chrome.center?.id, .manual("search"), "the title bar's content over the page's title view")
        XCTAssertEqual(chrome.background, .string("stack"))
        XCTAssertNil(chrome.sidebarToggle)
    }

    /// `.toolbar { … }` writes its slot under whatever view it modified, not the page's own - the chrome gathers
    /// every slot the page holds, splits the entries by where they were placed, and a nested arrangement keeps its
    /// own.
    func testTheChromeGathersToolbarSlotsFromTheWholePage() throws {
        let entry = { (id: String, _ placement: ToolbarItemPlacement) in
            self.node(id, .toolbarItem, [.placement: .enumeration(placement.rawValue)])
        }
        let runtime = runtime(node("window", .windowScene, children: [
            node("stack", .navigationStack, children: [
                node("page", .page, children: [
                    node("content", .vStack, children: [
                        node("nested", .hStack, children: [
                            node("inner", .toolbarItems, children: [
                                entry("save", .confirmationAction),
                                entry("undo", .navigation),
                                node("gap", .toolbarSpacer, [
                                    .placement: .enumeration(ToolbarItemPlacement.primaryAction.rawValue),
                                    .variant: .enumeration(ToolbarSpacerVariant.fixed.rawValue),
                                ]),
                            ]),
                        ]),
                        node("stack", .navigationStack, children: [
                            node("innerpage", .page, children: [
                                node("own", .toolbarItems, children: [entry("inner", .primaryAction)]),
                            ]),
                        ]),
                    ]),
                    node("top", .toolbarItems, children: [entry("top", .primaryAction)]),
                ]),
            ]),
        ])) { _ in }
        let page = try XCTUnwrap(try XCTUnwrap(runtime.tree.root)
            .first(id: .manual("page")))

        let actions = page.chromeActions
        XCTAssertEqual(actions.leading.map(\.id), [.manual("undo")])
        XCTAssertEqual(actions.primary.map(\.id), [.manual("save"), .manual("gap"), .manual("top")])
        XCTAssertEqual(actions.overflow.map(\.id), [])
    }

    /// Tabs pushed onto a stack keep the title of the page beneath them; tabs with nothing beneath name the window by
    /// the chosen tab, and a stack in a tab by its top page.
    func testTabsPushedOntoAStackKeepTheTitleBeneathThem() throws {
        let runtime = runtime(node("window", .windowScene, [.title: .string("WindowScene")], children: [
            node("stack", .navigationStack, children: [
                node("group", .page, [.title: .string("Items and Cards")]),
                node("tabs", .tabView, [.currentPage: .number(1)], children: [
                    node("one", .page, [.title: .string("Example 1")]),
                    node("two", .page, [.title: .string("Example 2")]),
                ]),
            ]),
            node("alone", .tabView, children: [node("tab", .page, [.title: .string("Tab")])]),
            node("stacked", .tabView, children: [
                node("inner", .navigationStack, children: [node("top", .page, [.title: .string("Top")])]),
            ]),
        ])) { _ in }
        let root = try XCTUnwrap(runtime.tree.root)
        let title = { (id: String) in WindowChrome(window: root, arrangement: root.first(id: .manual(id))).title }

        XCTAssertEqual(title("stack"), "Items and Cards", "the page the tabs were pushed onto")
        XCTAssertEqual(title("alone"), "Tab", "the chosen tab, where nothing lies beneath")
        XCTAssertEqual(title("stacked"), "Top", "a stack in a tab names the window by its top page")
    }

    /// Tabs pushed onto a stack are its last place: a title of their own names the window, never what the tabs show.
    /// A window's own tabs name it by the chosen tab, and a stack in the chosen tab by its top page, titled or not.
    func testTabsWithATitleNameTheWindowByItOnAStack() throws {
        let runtime = runtime(node("window", .windowScene, [.title: .string("WindowScene")], children: [
            node("stack", .navigationStack, children: [
                node("group", .page, [.title: .string("Items and Cards")]),
                node("tabs", .tabView, [.title: .string("List")], children: [
                    node("one", .page, [.title: .string("Example 1")]),
                ]),
            ]),
            node("alone", .tabView, [.title: .string("Tabs")], children: [
                node("tab", .page, [.title: .string("Tab")]),
            ]),
            node("stacked", .tabView, [.title: .string("Tabs")], children: [
                node("inner", .navigationStack, children: [node("top", .page, [.title: .string("Top")])]),
            ]),
        ])) { _ in }
        let root = try XCTUnwrap(runtime.tree.root)
        let title = { (id: String) in WindowChrome(window: root, arrangement: root.first(id: .manual(id))).title }

        XCTAssertEqual(title("stack"), "List", "the pushed tabs' own title")
        XCTAssertEqual(title("alone"), "Tab", "a window's own tabs: the chosen tab")
        XCTAssertEqual(title("stacked"), "Top", "a stack in a tab names the window by its top page")
    }

    /// A wrapper's background still paints the window when its nested stack supplies the visible page/title.
    func testWindowBackgroundFallsBackToComposedPageContent() throws {
        let outer = Color.red.propValue
        let inner = Color.blue.propValue
        func window(_ detailBackground: HostValue?) -> HostPatch {
            node("window", .windowScene, children: [node("wrapper", .page, children: [
                node("content", .zStack, [.windowBackground: outer], children: [
                    node("stack", .navigationStack, children: [
                        node("detail", .page, detailBackground.map { [.windowBackground: $0] } ?? [:]),
                    ]),
                ]),
            ])])
        }
        let runtime = runtime(window(nil)) { _ in }
        let root = try XCTUnwrap(runtime.tree.root)
        let wrapper = try XCTUnwrap(root.first(id: .manual("wrapper")))
        XCTAssertEqual(WindowChrome(window: root, arrangement: wrapper).windowBackground, outer)

        runtime.tree.apply(window(inner), complete: true)
        XCTAssertEqual(WindowChrome(window: root, arrangement: wrapper).windowBackground, inner,
                       "the visible page's own background still takes precedence")
    }

    /// A menu walks its items, separators and submenus in order, each with its caption and whether it can be chosen;
    /// a bar holds only its menus.
    func testAMenuIsWalkedInOrder() throws {
        let runtime = runtime(node("bar", .menuBar, children: [
            node("file", .menu, [.text: .string("File")], children: [
                node("open", .menuItem, [.text: .string("Open"), .icon: .string("folder")]),
                node("line", .divider),
                node("erase", .menuItem, [.text: .string("Erase"), .isDestructive: .bool(true), .icon: .string("")]),
                node("recent", .menu, [.text: .string("Recent")], children: [
                    node("one", .menuItem, [.text: .string("One"), .isEnabled: .bool(false)]),
                ]),
            ]),
            node("stray", .menuItem),
        ])) { _ in }

        let menus = MenuEntry.menus(of: try XCTUnwrap(runtime.tree.root))
        XCTAssertEqual(menus.map(\.title), ["File"], "the bar holds only its menus")
        let file = try XCTUnwrap(menus.first).entries
        XCTAssertEqual(file.map(\.kind), [.item, .separator, .item, .submenu])
        XCTAssertEqual(file.map(\.title), ["Open", "", "Erase", "Recent"])
        XCTAssertEqual(file.map(\.icon), ["folder", nil, nil, nil], "an empty picture is none")
        XCTAssertEqual(file.map(\.isDestructive), [false, false, true, false])
        XCTAssertEqual(file.last?.entries.map(\.isEnabled), [false])
    }

    func testMenuPlaceholdersAreDisabledAndSubmenuCaptionsComeFromTheTrigger() throws {
        let runtime = runtime(node("menu", .contextMenu, children: [
            node("loading", .text, [.text: .string("Loading…")]),
            node("branch", .menuButton, children: [
                node("caption", .text, [.text: .string("Directory")]),
                node("content", .contextMenu, children: [
                    node("empty", .text, [.text: .string("Empty")]),
                ]),
            ]),
        ])) { _ in }
        let entries = MenuEntry.entries(of: try XCTUnwrap(runtime.tree.root))
        XCTAssertEqual(entries.map(\.title), ["Loading…", "Directory"])
        XCTAssertEqual(entries.map(\.isEnabled), [false, true])
        XCTAssertEqual(entries.last?.entries.map(\.title), ["Empty"])
        XCTAssertEqual(entries.last?.entries.map(\.isEnabled), [false])
    }

    /// A button is a menu item too: its caption on its own `text` where the
    /// button says one, else read off the first words its label's views carry,
    /// its icon off the first picture - the way a command's button reads.
    func testAButtonIsWalkedAsAnItemWithItsLabelsCaptionAndIcon() throws {
        let runtime = runtime(node("menu", .menu, children: [
            node("titled", .button, [.text: .string("Plain")]),
            node("labelled", .button, children: [
                node("words", .text, [.text: .string("Labelled")]),
                node("glyph", .image, [.source: .string("star")]),
            ]),
            node("deep", .button, children: [
                node("box", .hStack, children: [
                    node("inner", .image, [.image: .string("flag")]),
                    node("inner-words", .text, [.text: .string("Deep")]),
                ]),
            ]),
            node("nothing", .button),
        ])) { _ in }

        let entries = MenuEntry.entries(of: try XCTUnwrap(runtime.tree.root))
        XCTAssertEqual(entries.map(\.kind), [.item, .item, .item, .item])
        XCTAssertEqual(entries.map(\.title), ["Plain", "Labelled", "Deep", ""])
        XCTAssertEqual(entries.map(\.icon), [nil, "star", "flag", nil])
    }

    /// An entry's `shortcut` and a menu's `placement` ride the walk - the
    /// commands' own words for a key equivalent and a region of the platform's
    /// menus.
    func testEntriesCarryTheirShortcutAndMenusTheirPlacement() throws {
        let runtime = runtime(node("bar", .menuBar, children: [
            node("group", .menu, [.placement: .enumeration(0)], children: [
                node("about", .button, [.text: .string("About")]),
            ]),
            node("run", .menu, [.text: .string("Run")], children: [
                node("build", .button,
                    [.text: .string("Build"), .shortcut: .values([.name("b"), .enumeration(1)])]),
            ]),
        ])) { _ in }

        let menus = MenuEntry.menus(of: try XCTUnwrap(runtime.tree.root))
        XCTAssertEqual(menus.map(\.placement), [.init(rawValue: 0), nil])
        XCTAssertEqual(menus[1].entries.first?.shortcut, KeyboardShortcut("b", modifiers: .command))

        // A placement menu flattens to its entries; an ordinary one stays a submenu.
        let flat = MenuEntry.flattened(menus)
        XCTAssertEqual(flat.map(\.title), ["About", "Run"])
        XCTAssertEqual(flat.map(\.kind), [.item, .submenu])
    }

    /// The scene's menus hang off the window, the page's off the page - the
    /// chrome keeps them apart whichever page shows.
    func testTheChromeKeepsTheScenesMenusApartFromThePages() throws {
        let runtime = runtime(node("window", .windowScene, children: [
            node("stack", .navigationStack, children: [
                node("page", .page, children: [
                    node("own", .menuBar, children: [
                        node("file", .menu, [.text: .string("File")]),
                    ]),
                ]),
            ]),
            node("commands", .menuBar, children: [
                node("run", .menu, [.text: .string("Run")]),
                node("app", .menu, [.placement: .enumeration(0)], children: [
                    node("about", .button, [.text: .string("About")]),
                ]),
            ]),
        ])) { _ in }
        let root = try XCTUnwrap(runtime.tree.root)

        let chrome = WindowChrome(window: root, arrangement: root.first(id: .manual("stack")))
        let scene = MenuEntry.menus(of: try XCTUnwrap(chrome.commands))
        let page = MenuEntry.menus(of: try XCTUnwrap(chrome.menuBar))

        XCTAssertEqual(scene.map(\.title), ["Run", ""], "a group has no caption of its own")
        XCTAssertEqual(scene.map(\.placement), [nil, CommandGroupPlacement(rawValue: 0)])
        XCTAssertEqual(page.map(\.title), ["File"])
    }

    /// A page's slots furnish its chrome and stand in none of its room; another element places every child.
    func testAPagePlacesAllButItsSlots() throws {
        let runtime = runtime(node("page", .page, children: [
            node("items", .toolbarItems), node("words", .text), node("view", .titleView),
        ])) { _ in }

        XCTAssertEqual(try XCTUnwrap(runtime.tree.root).arrangedChildren.map(\.id), [.manual("words")])
    }

    /// Back in a window takes the top sheet's own stack, else the top sheet, else the arrangement's stack.
    func testTheWayBackTakesTheTopSheetFirst() throws {
        let twoPages = { (id: String) in
            self.node(id, .navigationStack, children: [self.node("\(id).a", .page), self.node("\(id).b", .page)])
        }
        func wayBack(_ sheets: [HostPatch]) throws -> WayBack? {
            let runtime = runtime(node("window", .windowScene, children: [twoPages("main"), node("modal", .modalStack, children: sheets)])) {
                _ in
            }
            let presentation = WindowPresentation()
            _ = presentation.show(try XCTUnwrap(runtime.tree.root), in: runtime.lifecycle)
            return presentation.wayBack
        }

        guard case .pop(let stack) = try wayBack([twoPages("sheet")]) else { return XCTFail("the sheet's stack") }
        XCTAssertEqual(stack.id, .manual("sheet"))
        guard case .dismissSheet(let remaining) = try wayBack([node("one", .page), node("two", .page)]) else {
            return XCTFail("the top sheet")
        }
        XCTAssertEqual(remaining, 1)
        guard case .pop(let main) = try wayBack([]) else { return XCTFail("the arrangement's stack") }
        XCTAssertEqual(main.id, .manual("main"))
    }
}

/// A native half that says, as each tabbed view is applied, whether its tabs stand in the window.
@MainActor
private final class TabsReading: NativeElement {
    unowned let element: MountedElement
    let read: (String, Bool) -> Void
    let presentsView = true

    init(_ element: MountedElement, read: @escaping (String, Bool) -> Void) {
        self.element = element
        self.read = read
    }

    func applied(changed: Set<Prop>, wasDescribed: Bool) {
        guard element.type == .tabView, case .manual(let id) = element.id else { return }
        read(id, element.tabsStandInWindow)
    }

    func standingValue(_ property: Prop) -> HostValue? { nil }
    func animates(_ property: Prop) -> Bool { false }
    func presentFrame(_ changed: Set<Prop>) {}
    func arrangeChildren() {}
    func leave() {}
}
