// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// A WinUI window: its title, its one chrome across the top, its menu bar and the row of tabs beneath it, and the
/// page shown in it, activated the first time it has one.
/// Design: docs/design/platforms/winui/pages.md#the-windows-chrome
@MainActor
final class WinUIWindow {
    /// The window, held until this is released.
    let handle: SwiftOmniUIObjectRef

    /// The title last given; nil before the first.
    private var title: String??

    /// The view the window shows.
    private(set) var content: WinUIView?

    /// What the window lays over its page and its sheets.
    private(set) var overlay: WinUIView?

    private var safeBars: [WinUISafeAreaBarHost] = []
    private var requestedSafeBars: [MountedElement] = []
    private var safeBarCommitPending = false
    private weak var safeBarPage: MountedElement?
    private var safeBarFrame: Rect?
    private var safeBarFramePending = false

    /// The window's chrome, its menu bar, and the row a window's tabs stand in.
    let titleBar = WinUITitleBarView()
    let menuBar = WinUIMenuBarView()
    let tabRow = WinUITabsView()

    /// The toolbar occupies a row only while shown. Native caption buttons can overlay the full-size content.
    private(set) var titleBarStands = true
    private var windowBackground: UInt32??

    /// Whether the menu bar stands beneath the chrome: while the visible page has menus.
    private(set) var menuBarStands = false

    /// Where the row of tabs stands: across the window beneath its chrome, or across a split view's detail.
    private(set) var tabsStandInWindow = false
    private(set) weak var tabsSplit: WinUISplitView?

    private var activated = false

    /// Whether the window's scene hides it: while another scene is in front.
    private(set) var isHidden = false

    /// The number the window's own events name it by: its chrome's.
    var number: Int64 { titleBar.number }

    /// Whether the window was closed: what it tells after that is its closing's, and no one's to hear.
    private(set) var isClosed = false

    init() {
        handle = swiftomniui_winui_window_make(titleBar.number)!
        swiftomniui_winui_window_set_chrome(handle, titleBar.handle, nil, nil)
        let rows: [WinUIView] = [titleBar, menuBar, tabRow]
        for row in rows {
            row.watchNativeHeight { [weak self] in self?.refreshSafeAreaEnvironment() }
        }
    }

    isolated deinit {
        if !isClosed { swiftomniui_winui_window_set_safe_area_bars(handle, nil, 0) }
        for host in safeBars { host.releaseBar() }
        swiftomniui_winui_release(handle)
    }

    func showTopSafeAreaBars(_ bars: [MountedElement], in page: MountedElement?) {
        if safeBarPage !== page {
            safeBarFrame = nil
            // The previous page's column is no longer the new bar's place.
            // Keep its overlay out of view until the new native page is laid out.
            if !safeBars.isEmpty { swiftomniui_winui_window_set_safe_area_bar_frame(handle, 0, 0, 0) }
        }
        safeBarPage = page
        requestSafeBarFrame()
        requestedSafeBars = bars
        let views = bars.compactMap { $0.winUI.view }
        let sameBars = views.count == safeBars.count && zip(views, safeBars).allSatisfy { $0 === $1.bar }
        if sameBars { for host in safeBars { host.updateBackground() } }
        if sameBars, !safeBarCommitPending { return }
        guard !safeBarCommitPending else { return }
        safeBarCommitPending = true
        WinUIDoorbell.afterPass { [weak self] in
            self?.commitSafeAreaBars()
        }
    }

    /// Finish the page's initial native composition before the window's first
    /// frame. Later updates keep their normal after-pass batching.
    func prepareFirstPresentation(split: WinUISplitView?) {
        guard !activated, !isClosed else { return }
        split?.prepareFirstPresentation(width: contentSize.width)
        if WinUIView.arranging == 0, WinUIView.measuring == 0 { commitSafeAreaBars() }
    }

    private func commitSafeAreaBars() {
        guard safeBarCommitPending else { return }
        safeBarCommitPending = false
        guard !isClosed else { return }
        let views = requestedSafeBars.compactMap { $0.winUI.view }
        if views.count != safeBars.count || !zip(views, safeBars).allSatisfy({ $0 === $1.bar }) {
            swiftomniui_winui_window_set_safe_area_bars(handle, nil, 0)
            for host in safeBars { host.releaseBar() }
            safeBars = views.map { WinUISafeAreaBarHost(bar: $0) }
            for host in safeBars {
                host.onSourcePlaced = { [weak self] in self?.requestSafeBarFrame() }
            }
            safeBarFrame = nil
        }
        let handles: [SwiftOmniUIObjectRef?] = safeBars.map(\.presentationHandle)
        swiftomniui_winui_window_set_safe_area_bars(handle, handles, Int32(handles.count))
        if safeBarFrame == nil, !safeBars.isEmpty {
            swiftomniui_winui_window_set_safe_area_bar_frame(handle, 0, 0, 0)
        }
        updateSafeBarFrame()
    }

    private func requestSafeBarFrame() {
        guard !safeBarFramePending else { return }
        safeBarFramePending = true
        WinUIDoorbell.afterPass { [weak self] in
            guard let self else { return }
            self.safeBarFramePending = false
            self.updateSafeBarFrame()
        }
    }

    /// Native split/navigation templates own the page's actual origin. Scope the promoted surface to that page,
    /// rather than proposing the complete window width to a bar still measured by its logical detail column.
    private func updateSafeBarFrame() {
        guard !isClosed, !safeBars.isEmpty, let page = safeBarPage?.winUI.view, let content else { return }
        guard page.isAttached, content.isAttached else { return }
        let size = page.laidOutFrame
        guard size.width > 0, size.height > 0 else { return }
        let origin = page.origin, root = content.origin
        let frame = Rect(origin.x - root.x, origin.y - root.y, size.width, 0)
        guard frame != safeBarFrame else { return }
        safeBarFrame = frame
        swiftomniui_winui_window_set_safe_area_bar_frame(handle, frame.x, frame.y, frame.width)
    }

    /// The window's name, which the system shows for it; nil for none.
    func setTitle(_ title: String?) {
        guard self.title != .some(title) else { return }
        self.title = .some(title)
        swiftomniui_winui_window_set_title(handle, title ?? "")
    }

    /// The window's own background, behind its complete client area; nil restores the system backdrop.
    func setBackground(_ value: HostValue?) {
        let color = value?.argb
        guard windowBackground != .some(color) else { return }
        windowBackground = .some(color)
        swiftomniui_winui_window_set_background(handle, color != nil, color ?? 0)
    }

    /// Moves and sizes the window as `frame` asks, each request alone: a place from the corner of the screen's work
    /// area, a size the content's, in DIPs.
    /// Design: docs/design/platforms/winui/runtime.md#a-windows-frame
    func request(_ frame: WindowFrame) {
        let requests = [frame.x, frame.y, frame.width, frame.height]
        swiftomniui_winui_window_set_frame(handle, requests.map { $0 != nil }, requests.map { $0 ?? 0 })
    }

    /// Places the window by the anchor `position` names, as `.defaultPosition` asks - only where it has not been
    /// shown: where the user moved it, it stays.
    func place(_ position: [Double]) {
        guard !activated, position.count == 2 else { return }
        swiftomniui_winui_window_set_anchor(handle, position)
    }

    /// Bounds the content's size as `bounds` says; one it leaves unsaid is WinUI's own.
    func bound(_ bounds: WindowBounds) {
        let limits = [bounds.minimumWidth, bounds.minimumHeight, bounds.maximumWidth, bounds.maximumHeight]
        swiftomniui_winui_window_set_limits(handle, limits.map { $0 ?? 0 })
    }

    private var clientSize: LayoutSize {
        var values = [0.0, 0.0]
        swiftomniui_winui_window_client_size(handle, &values)
        return LayoutSize(width: values[0], height: values[1])
    }

    var chromeHeight: Double {
        // TitleBar's template declares its row height. Before activation its
        // Measure can return zero even after ApplyTemplate; using that answer
        // undersizes the first window and a later navigation grows it to fit.
        // Read the declaration before sizing, without changing native styling
        // or flushing the page's pending layout.
        let width = clientSize.width
        let caption = titleBarStands
            ? max(swiftomniui_winui_window_title_bar_height(handle), titleBar.layoutHeight)
            : 0
        let bars: [WinUIView] = (menuBarStands ? [menuBar] : []) + (tabsStandInWindow ? [tabRow] : [])
        return bars.reduce(caption) { $0 + $1.measure(width: width, height: nil).height }
    }

    var contentSize: LayoutSize {
        contentSize(chromeHeight: chromeHeight)
    }

    func contentSize(chromeHeight: Double) -> LayoutSize {
        let size = clientSize
        return LayoutSize(width: size.width, height: max(0, size.height - chromeHeight))
    }

    func boundContent(_ bounds: WindowBounds, chromeHeight: Double? = nil) {
        var bounds = bounds
        let chrome = chromeHeight ?? self.chromeHeight
        bounds.minimumHeight = bounds.minimumHeight.map { $0 + chrome }
        bounds.maximumHeight = bounds.maximumHeight.map { $0 + chrome }
        bound(bounds)
    }

    func requestContent(_ frame: WindowFrame, chromeHeight: Double? = nil) {
        var frame = frame
        let chrome = chromeHeight ?? self.chromeHeight
        frame.height = frame.height.map { $0 + chrome }
        request(frame)
    }

    /// Makes the window what `traits` says: a button it leaves unsaid is WinUI's own, which lets the user press it.
    /// `.contentSize` stands it as a fixed-size window does - the caption keeps only the button that closes it.
    func apply(_ traits: WindowTraits, isResizable: Bool? = nil) {
        let sizedByContent = isResizable.map { !$0 } ?? (traits.resizability == WindowResizability.contentSize.rawValue)
        swiftomniui_winui_window_set_traits(
            handle, traits.isMaximizable ?? !sizedByContent, traits.isMinimizable ?? !sizedByContent,
            !sizedByContent, traits.isTranslucent, traits.floatsOnTop)
    }

    /// Shows `view` as the window's content - the first one activates the window, unless its scene hides it.
    func show(_ view: WinUIView?, present: Bool = true) {
        let changed = content !== view
        if changed {
            content?.rootSafeAreaContext = nil
            view?.placingLayout = nil
            view?.safeAreaContext = nil
        }
        content = view
        view?.rootSafeAreaContext = { [weak self] bounds in
            guard let self else { return SafeAreaContext(bounds: bounds) }
            // Native chrome already removed these rows from the content's
            // allocation. Keep the outside strips in its safe environment;
            // readers still observe them and scrollers can extend behind them.
            // Read committed metrics here; measuring chrome during Arrange
            // would recursively enter the native layout engine.
            let caption = max(swiftomniui_winui_window_title_bar_height(self.handle),
                              self.titleBar.laidOutFrame.height)
            let menu = self.menuBarStands ? self.menuBar.laidOutFrame.height : 0
            let tabs = self.tabsStandInWindow ? self.tabRow.laidOutFrame.height : 0
            let top = max(0, caption + menu + tabs)
            return SafeAreaContext(bounds: Rect(bounds.x, bounds.y - top, bounds.width, bounds.height + top),
                                   layout: bounds, container: bounds)
        }
        swiftomniui_winui_window_set_content(handle, view?.presentationHandle)
        if changed { view?.safeAreaChanged() }
        if present { activateFirstTime() }
    }

    func presentContent() { activateFirstTime() }

    /// Hides the window as its scene goes behind another, or shows it again without activating it; one never shown
    /// is activated as it is first shown.
    func setHidden(_ hidden: Bool) {
        guard hidden != isHidden else { return }
        isHidden = hidden
        if activated {
            swiftomniui_winui_window_set_shown(handle, !hidden)
        } else {
            activateFirstTime()
        }
    }

    /// Makes the window `owner`'s - above it, hidden with it, out of the switchers - or, for nil, one of its own.
    func setOwner(_ owner: WinUIWindow?) {
        swiftomniui_winui_window_set_owner(handle, owner?.handle)
    }

    /// Activates the window the first time it has content and stands shown.
    private func activateFirstTime() {
        guard content != nil, !activated, !isHidden else { return }

        activated = true
        swiftomniui_winui_window_activate(handle)
    }

    /// Shows `chrome`, its menus beneath it, and `tabs` - across the split view's detail they stand in, or across the
    /// window.
    func apply(_ chrome: WinUIWindowChrome, tabs: WinUIWindowTabs?) {
        setTitle(chrome.windowTitle ?? chrome.title)
        titleBar.apply(chrome)
        if titleBarStands != chrome.showsToolbar {
            titleBarStands = chrome.showsToolbar
            standChrome()
        }
        menuBar.show(chrome.menuBar)
        if chrome.menuBar.isEmpty == menuBarStands {
            menuBarStands.toggle()
            standChrome()
        }
        if let tabs {
            tabRow.onChosen = tabs.select
            tabRow.show(tabs.titles, chosen: tabs.selected)
        }

        let inWindow = tabs != nil && tabs?.split == nil
        let split = tabs?.split
        guard inWindow != tabsStandInWindow || split !== tabsSplit else { return }

        // Out of where it stood before it stands anywhere else: an element has one parent.
        tabsSplit?.setDetailRow(nil)
        if tabsStandInWindow {
            tabsStandInWindow = false
            standChrome()
        }
        tabsSplit = split
        tabsStandInWindow = inWindow
        split?.setDetailRow(tabRow)
        if inWindow { standChrome() }
    }

    /// Stands the chrome across the window, and beneath it the menu bar and the tabs where they stand there.
    private func standChrome() {
        swiftomniui_winui_window_set_chrome(
            handle, titleBarStands ? titleBar.handle : nil, menuBarStands ? menuBar.handle : nil,
            tabsStandInWindow ? tabRow.handle : nil)
        refreshSafeAreaEnvironment()
    }

    private var safeAreaRefreshPending = false

    /// Read the committed native rows after their structural change. A new
    /// environment starts a pass even when the content's final size is equal.
    private func refreshSafeAreaEnvironment() {
        guard !safeAreaRefreshPending else { return }
        safeAreaRefreshPending = true
        WinUIDoorbell.afterPass { [weak self] in
            guard let self else { return }
            self.safeAreaRefreshPending = false
            guard !self.isClosed else { return }
            self.content?.safeAreaChanged()
        }
    }

    /// Shows `sheets` over everything the window shows, the last on top.
    /// Design: docs/design/platforms/winui/pages.md#the-modal-stack
    func showSheets(_ sheets: [WinUISheetView]) {
        let handles: [SwiftOmniUIObjectRef?] = sheets.map(\.presentationHandle)
        swiftomniui_winui_window_set_sheets(handle, handles, Int32(handles.count))
    }

    /// Lays `view` over the page and its sheets, where the page stands - a click beside what it holds goes on to
    /// them; nil takes it away.
    /// Design: docs/design/platforms/winui/pages.md#the-windows-overlay
    func showOverlay(_ view: WinUIView?) {
        overlay = view
        swiftomniui_winui_window_set_overlay(handle, view?.presentationHandle)
    }

    /// Closes the window; one closed already stays as it is.
    func close() {
        guard !isClosed else { return }
        isClosed = true
        swiftomniui_winui_window_close(handle)
    }

    /// The window closed of WinUI's accord - the user closed it: what it tells after that is no one's to hear.
    func closed() {
        isClosed = true
    }
}
