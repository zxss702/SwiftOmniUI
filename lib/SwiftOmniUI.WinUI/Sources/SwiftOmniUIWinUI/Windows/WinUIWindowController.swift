// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// One window element shown in a WinUI window: what the host layer says it shows - its arrangement of pages, its
/// sheets, its overlay, its frame and its chrome - turned into WinUI's, in step with the element as the tree changes.
/// Design: docs/design/platforms/winui/runtime.md#the-window
@MainActor
final class WinUIWindowController {
    /// The window element shown.
    private(set) weak var element: MountedElement?

    /// The WinUI window it is shown in.
    let window = WinUIWindow()

    /// What the window shows, by the host layer's rule.
    private let presentation = WindowPresentation()
    private var traits: WindowTraits?

    /// The sheets the window shows, one for each page its modal stack presents, the last on top.
    private var sheets: [(element: MountedElement, sheet: WinUISheetView)] = []

    init(_ element: MountedElement) {
        self.element = element
    }

    /// Shows what the element asks for now, the window it belongs to found by `windowOf`. The host layer tells
    /// the page the user sees and the window made before the window is first shown, and so before it hears it came
    /// to the front.
    func present(_ element: MountedElement, in runtime: HostRuntime, keepingSizing: Bool = false,
                 windowOf: (MountedElement) -> WinUIWindow?) {
        self.element = element
        let changes = presentation.show(element, in: runtime.lifecycle)
        if let owner = changes.owner { window.setOwner(owner.flatMap(windowOf)) }
        stand(changes)
        if let (_, arrangement) = changes.arrangement { window.show(arrangement?.winUI.view, present: false) }
        showSheets(presentation.sheets)
        if let overlay = changes.overlay { window.showOverlay(overlay?.winUI.view) }
        if runtime.tree.chromeMayChange || changes.arrangement != nil || changes.traits != nil { refreshChrome(in: runtime) }
        window.showTopSafeAreaBars(presentation.arrangement?.visiblePage?.pageTopSafeAreaBars ?? [])
        boundContent(element, requested: changes.frame, quiet: changes.arrangement == nil && changes.traits == nil, keepingSizing: keepingSizing)
        let asked = WindowFrame(of: element)
        if asked.x == nil, asked.y == nil, let anchor = element.value(.defaultPosition)?.numbers {
            window.place(anchor)
        }
        window.presentContent()
    }

    /// Stands the window as the element asks: the place, the size, the bounds and the traits the tree changed, and
    /// whether its scene hides it.
    /// Design: docs/design/platforms/winui/runtime.md#a-windows-frame
    private func stand(_ changes: WindowPresentation.Changes) {
        if let traits = changes.traits { self.traits = traits }
        if let hidden = changes.hidden { window.setHidden(hidden) }
    }

    /// The sizing last made: the window's content bounds, which neither an animation's frame nor a lazy
    /// window moving changes - measuring the whole page for them each frame is what a frame must not do.
    private var sized: WindowContentSizing?

    private func boundContent(_ element: MountedElement, requested: WindowFrame?, quiet: Bool, keepingSizing: Bool) {
        let sizing: WindowContentSizing
        if quiet, keepingSizing || LazyCells.realizing, let sized { sizing = sized } else {
            var asked: [Double?: [ObjectIdentifier: LayoutSize]] = [:]
            sizing = WindowContentSizing(of: element, content: presentation.arrangement) { node, width in
                guard let item = node.winUI.layoutItem else { return nil }
                if let known = asked[width]?[ObjectIdentifier(node)] { return known }
                let size = SingleChildArithmetic.size(of: item, padding: EdgeInsets(0), width: width)
                asked[width, default: [:]][ObjectIdentifier(node)] = size
                return size
            }
            sized = sizing
        }
        if let traits { window.apply(traits, isResizable: sizing.isResizable) }
        let chromeHeight = window.chromeHeight
        window.boundContent(sizing.bounds, chromeHeight: chromeHeight)
        if let requested { window.requestContent(requested, chromeHeight: chromeHeight) }
        let frame = sizing.constrain(window.contentSize(chromeHeight: chromeHeight))
        if !frame.isEmpty { window.requestContent(frame, chromeHeight: chromeHeight) }
    }

    /// Keeps a sheet for each page shown as one, in its order, each under its page's title.
    /// Design: docs/design/platforms/winui/pages.md#the-modal-stack
    private func showSheets(_ pages: [MountedElement]) {
        guard !pages.isEmpty || !sheets.isEmpty else { return }

        sheets = pages.map { page in
            let sheet = sheets.first { $0.element === page }?.sheet ?? WinUISheetView()
            let shown = page.visiblePage
            sheet.show(title: shown?.pageValue(.title)?.string ?? "", page: page.winUI.view, height: Self.height(shown))
            return (page, sheet)
        }
        window.showSheets(sheets.map(\.sheet))
    }

    /// The height the page's first detent asks for, as `WinUISheetView.show` takes it: points over 0, a share of the
    /// window under 0, the content's own where none is asked.
    private static func height(_ page: MountedElement?) -> Double {
        guard let detents = page?.pageValue(.presentationDetents).flatMap({ [PresentationDetent](propValue: $0) }),
              let first = detents.first
        else { return 0 }

        return switch first {
        case .medium: -0.5
        case .large: 0
        case .fraction(let part): -part
        case .height(let points): points
        }
    }

    /// The user took the top sheet away - Escape, its dismissing: the window is told how many remain. A page that
    /// says `interactiveDismissDisabled` hears nothing of it.
    func dismissTopSheet(in runtime: HostRuntime) {
        guard let element, !presentation.sheets.isEmpty else { return }
        guard !(presentation.sheets.last?.visiblePage?.pageValue(.interactiveDismissDisabled)?.bool ?? false) else { return }

        runtime.goBack(.dismissSheet(remaining: presentation.sheets.count - 1), in: element)
    }

    /// Goes the way back the window offers: the top sheet's, else the arrangement's.
    /// Design: docs/design/host/pages.md#the-way-back
    private func goBack(in runtime: HostRuntime) {
        guard let element, let way = presentation.wayBack else { return }

        runtime.goBack(way, in: element)
    }

    /// Lays the chrome the host layer composes from what the window shows in WinUI's: the title, the way back, the
    /// page's actions, the slots, the colours, the menus, the sidebar's toggle, a sheet's buttons and the tabs.
    /// Design: docs/design/platforms/winui/pages.md#the-windows-chrome
    func refreshChrome(in runtime: HostRuntime) {
        guard let element else { return }

        let composed = WindowChrome(window: element, arrangement: presentation.arrangement)
        var chrome = WinUIWindowChrome()
        chrome.title = composed.title ?? ""
        chrome.showsToolbar = composed.toolbarVisibility?.enumeration != Visibility.hidden.rawValue
        chrome.back = composed.back.map { back in
            WinUIToolbarAction(title: back.title, isEnabled: true, perform: { [weak element, weak stack = back.stack] in
                if let element, let stack { runtime.goBack(.pop(stack), in: element) }
            })
        }
        chrome.sidebarToggle = composed.sidebarToggle.map { split in
            { [weak split] in
                guard let split else { return }
                split.winUI.changeSidebarVisibility(to: !split.sidebarIsVisible)
            }
        }
        chrome.leading = composed.leading?.winUI.view
        chrome.center = composed.center?.winUI.view
        chrome.trailing = composed.trailing?.winUI.view
        chrome.leadingActions = composed.leadingActions.map(Self.action)
        chrome.actions = composed.primaryActions.map(Self.action)
        chrome.overflow = composed.overflowActions.map(Self.action)
        chrome.background = composed.toolbarBackground?.enumeration == Visibility.hidden.rawValue
            ? Color.clear.propValue : composed.background
        chrome.foreground = composed.foreground
        // A placement group's entries stand for the platform's own menus: the app menu's button carries them.
        // A scene's own command menus stand beside the page's in the bar.
        let commands = composed.commands.map { MenuEntry.menus(of: $0) } ?? []
        chrome.appMenu = WinUIMenu(entries: commands.filter { $0.placement != nil }.flatMap(\.entries))
        chrome.menuBar = WinUIMenu(menus: commands.filter { $0.placement == nil }
            + (composed.menuBar.map { MenuEntry.menus(of: $0) } ?? []))
        if !presentation.sheets.isEmpty {
            chrome.sheet = (
                back: { [weak self] in self?.goBack(in: runtime) },
                dismiss: { [weak self] in self?.dismissTopSheet(in: runtime) })
        }
        window.setBackground(composed.windowBackground)
        window.apply(chrome, tabs: windowTabs)
    }

    /// A page's toolbar entry as a command of the chrome: a spacer's room, the view an item carries, or a
    /// titled or pictured action.
    private static func action(_ item: MountedElement) -> WinUIToolbarAction {
        let picture = item.value(.icon).flatMap(ImageSource.init(propValue:))
        var action = WinUIToolbarAction(
            title: item.value(.text)?.string ?? "", isEnabled: item.value(.isEnabled)?.bool ?? true,
            identifier: item.value(.accessibilityIdentifier)?.string,
            icon: picture.map(\.file).flatMap { $0.isEmpty ? nil : PictureArithmetic.files(for: $0) } ?? [],
            symbol: picture?.symbol,
            perform: { [weak item] in item?.winUI.send(.clicked, []) })
        if item.type == .toolbarSpacer {
            action.spacer = ToolbarSpacerVariant(rawValue: item.value(.variant)?.enumeration ?? 0)
        } else {
            action.view = item.children.lazy.compactMap(\.presentingElement).first?.winUI.view
        }
        return action
    }

    /// The tabs the window shows - the visible tabbed view's, where its tabs stand in the window - and the split view
    /// whose detail they stand across, if any.
    private var windowTabs: WinUIWindowTabs? {
        guard let tabbed = presentation.arrangement?.visibleTabbedView, tabbed.tabsStandInWindow,
              let tabs = tabbed.winUI.view as? WinUITabbedView
        else { return nil }

        return WinUIWindowTabs(
            titles: tabs.titles, selected: tabs.shownIndex, select: { [weak tabs] index in tabs?.selectByUser(index) },
            split: tabbed.parent?.enclosing(type: .navigationSplitView)?.winUI.view as? WinUISplitView)
    }

    /// The page's frame in the window, in DIPs: where content stands clear of the window's chrome.
    var safeArea: Rect {
        guard let content = window.content else { return Rect(x: 0, y: 0, width: 0, height: 0) }
        let corner = content.origin
        let size = content.placedFrame
        return Rect(x: corner.x, y: corner.y, width: size.width, height: size.height)
    }
}
