// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// A NavigationSplitView: the sidebar page in WinUI's own navigation pane - beside the detail page where the window is wide,
/// over it and closed by a click beside it where it is narrow - which WinUI places, as it places any Windows app's.
/// Whether the sidebar shows is SwiftOmniUI's binding, which the window's chrome toggles and which follows what WinUI
/// shows. The host's one adaptation is that a window wide enough for both panes opens with the sidebar shown; after
/// that, the user and the application decide.
/// Design: docs/design/platforms/winui/pages.md#a-split-view
@MainActor
final class WinUISplitView: WinUILayoutView {
    /// Whether the sidebar shows.
    private(set) var isPresented = false

    /// What the split does when the sidebar shows or hides of its own accord - its first room, a click beside it,
    /// the window's room changing.
    var onPresentationChanged: ((Bool) -> Void)?

    /// What the split does when the user moves which of three columns show.
    var onVisibilityChanged: ((NavigationSplitViewVisibility) -> Void)?

    /// WinUI's split view, whose pane is the sidebar.
    let sidebar = WinUISidebarView()

    /// The inner split keeps the main content flexible and the auxiliary detail in a trailing pane.
    let middle = WinUISidebarView(trailing: true)

    /// Whether the content column shows, where three columns can.
    private(set) var isContentPresented = true

    /// The sidebar's [minimum, ideal, maximum] width the tree asks: the
    /// pane's open length is the ideal, or the minimum it has alone.
    var sidebarPaneLength: [Double]? {
        didSet { if sidebarPaneLength != oldValue { configure() } }
    }

    /// The content column's [minimum, ideal, maximum] width, as
    /// `sidebarPaneLength` is the sidebar's.
    var contentPaneLength: [Double]? {
        didSet { if contentPaneLength != oldValue { configure() } }
    }

    var detailWidthBounds: [Double]? {
        didSet { if detailWidthBounds != oldValue { configure(); invalidateMeasurements() } }
    }

    /// The sidebar page and the detail page, as the tree gives them, and the row across the detail.
    private var pages: [WinUILayoutItem] = []
    private(set) weak var detailRow: WinUIView?

    /// The size WinUI's split view was last arranged at, which it is measured at too; and what it last asked.
    private var arranged: LayoutSize?
    private var asked = LayoutSize.zero
    private var adaptation = SidebarAdaptation()
    private var configurationPending = false
    private var ownedPages: [WinUIView] = []
    private var ownedThreeColumns = false

    override init() {
        super.init()
        sidebar.placingLayout = self
        sidebar.onPresented = { [weak self] open in
            guard let self, open != isPresented else { return }
            isPresented = open
            if let visibility = effectiveVisibility {
                onVisibilityChanged?(visibility)
            } else {
                onPresentationChanged?(open)
            }
        }
        setChildren([sidebar])
    }

    /// Whether a content column stands between the sidebar and the detail.
    var hasContentColumn: Bool { pages.count > 2 }
    var showsDetailColumn: Bool { hasContentColumn && SplitColumnWidth(detailWidthBounds, defaultIdeal: 320).maximum != 0 }

    /// Which columns stand shown on screen, where three can.
    private var effectiveVisibility: NavigationSplitViewVisibility? {
        guard hasContentColumn else { return nil }
        switch (isPresented, isContentPresented) {
        case (true, true): return .all
        case (false, true): return .doubleColumn
        case (false, false): return .detailOnly
        case (true, false): return .all
        }
    }

    /// The pages go in WinUI's split view, which places them; the panel holds it alone.
    @discardableResult
    override func setItems(_ items: [WinUILayoutItem]) -> Bool {
        guard items.count != pages.count || !zip(items, pages).allSatisfy({ $0.arranges(like: $1) }) else { return false }

        for page in pages where !items.contains(where: { $0.view === page.view }) {
            page.view.nativeLayoutOwner = nil
        }
        pages = items
        for page in items {
            page.view.placingLayout = nil
            page.view.nativeLayoutOwner = self
        }
        configure()
        invalidateMeasurements()
        return true
    }

    override func heldViews() -> [WinUIView] {
        [sidebar]
    }

    /// Shows a row across the top of the detail - the tabs of a tabbed view standing in it - or takes it away.
    func setDetailRow(_ row: WinUIView?) {
        guard row !== detailRow else { return }
        detailRow = row
        configure()
    }

    /// Applies the tree's value without echoing it back as a user's change.
    func present(_ presented: Bool) {
        guard presented != isPresented else { return }

        isPresented = presented
        configure()
    }

    /// The columns the tree says show, without echoing them back as the
    /// user's change: `.all` shows all three, `.doubleColumn` drops the
    /// sidebar of three or keeps two of two, `.detailOnly` drops all but the
    /// detail, and `.automatic` asks nothing.
    func present(visibility: NavigationSplitViewVisibility) {
        let threeColumns = hasContentColumn
        switch visibility {
        case .automatic:
            break
        case .all:
            isPresented = true
            isContentPresented = true
        case .doubleColumn:
            isPresented = !threeColumns
            isContentPresented = true
        case .detailOnly:
            isPresented = false
            isContentPresented = false
        }
        configure()
    }

    /// What WinUI's split view asked, never its pages' own sizes: WinUI measures them in the room it gives them.
    override func contentSize(width: Double?) -> LayoutSize {
        asked
    }

    /// Measures at the current finite proposal; a previous allocation only
    /// supplies axes left unspecified by a speculative parent measurement.
    /// Design: docs/design/platforms/winui/pages.md#a-native-arrangement
    override func measure(width: Double, height: Double) -> LayoutSize {
        guard WinUIView.arranging == 0 else { return super.measure(width: width, height: height) }
        let size = LayoutSize(width: width.isFinite ? width : arranged?.width ?? width,
                              height: height.isFinite ? height : arranged?.height ?? height)
        asked = sidebar.measure(width: size.width, height: size.height)
        return super.measure(width: width, height: height)
    }

    override func arrange(in bounds: Rect) {
        let size = LayoutSize(width: bounds.width, height: bounds.height)
        if size != arranged {
            arranged = size
        }
        adaptToFirstRoom(width: bounds.width)
        sidebar.layout(bounds)
    }

    /// The host's one adaptation: a window wide enough for both panes opens with its sidebar shown, and says so.
    private func adaptToFirstRoom(width: Double) {
        guard adaptation.room(width, breakpoint: WinUISidebarView.expandsAt, shown: isPresented) else { return }

        present(true)
        if let visibility = effectiveVisibility { onVisibilityChanged?(visibility) }
        else { onPresentationChanged?(true) }
    }

    private func configure() {
        if WinUIView.arranging > 0 || WinUIView.measuring > 0 {
            guard !configurationPending else { return }
            configurationPending = true
            WinUIDoorbell.afterPass { [weak self] in
                guard let self else { return }
                self.configurationPending = false
                guard !self.isDetached else { return }
                self.configure()
            }
            return
        }
        ProgramWrite.perform {
            let three = pages.count > 2 && SplitColumnWidth(detailWidthBounds, defaultIdeal: 320).maximum != 0
            let views = pages.map(\.view)
            if three != ownedThreeColumns || views.count != ownedPages.count
                || !zip(views, ownedPages).allSatisfy({ $0 === $1 }) {
                // Release each native owner before moving a page between two and three columns.
                sidebar.clear()
                middle.clear()
                ownedPages = views
                ownedThreeColumns = three
            }
            if three {
                let detail = SplitColumnWidth(detailWidthBounds, defaultIdeal: 320)
                let content = SplitColumnWidth(contentPaneLength)
                middle.set(
                    sidebar: pages[2].view, detail: pages[1].view, row: detailRow, open: true,
                    widths: detail, contentShown: isContentPresented, contentWidths: content)
                sidebar.set(
                    sidebar: pages.first?.view, detail: middle, row: nil,
                    open: isPresented, widths: SplitColumnWidth(sidebarPaneLength),
                    contentWidths: SplitColumnWidth([middle.minimumRoom, -1, -1]))
            } else {
                sidebar.set(
                    sidebar: pages.first?.view, detail: pages.dropFirst().first?.view, row: detailRow,
                    open: isPresented, widths: SplitColumnWidth(sidebarPaneLength),
                    contentWidths: SplitColumnWidth(contentPaneLength))
            }
        }
    }

    override func detach() {
        for page in pages { page.view.nativeLayoutOwner = nil }
        sidebar.clear()
        middle.clear()
        ownedPages = []
        super.detach()
        onPresentationChanged = nil
        onVisibilityChanged = nil
        middle.detach()
        sidebar.detach()
    }
}
