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

    /// WinUI's navigation view, whose pane is the sidebar.
    let sidebar = WinUISidebarView()

    /// The middle column's own navigation view inside the outer one's
    /// detail: its pane is the content column, its content the detail - a
    /// three-column split as two two-column ones.
    let middle = WinUISidebarView()

    /// Whether the content column shows, where three columns can.
    private(set) var isContentPresented = true

    /// The sidebar's [minimum, ideal, maximum] width the tree asks: the
    /// pane's open length is the ideal, or the minimum it has alone.
    var sidebarPaneLength: [Double]? {
        didSet { configure() }
    }

    /// The content column's [minimum, ideal, maximum] width, as
    /// `sidebarPaneLength` is the sidebar's.
    var contentPaneLength: [Double]? {
        didSet { configure() }
    }

    var detailWidthBounds: [Double]? {
        didSet { if detailWidthBounds != oldValue { configure(); invalidateMeasurements() } }
    }

    /// The pane's open length from a width triple: the ideal, or the minimum.
    private static func paneLength(_ bounds: [Double]?) -> Double {
        guard let bounds else { return 0 }
        return bounds.count > 1 ? bounds[1] : (bounds.first ?? 0)
    }

    /// The sidebar page and the detail page, as the tree gives them, and the row across the detail.
    private var pages: [WinUILayoutItem] = []
    private(set) weak var detailRow: WinUIView?

    /// The size WinUI's navigation view was last arranged at, which it is measured at too; and what it last asked.
    private var arranged: LayoutSize?
    private var asked = LayoutSize.zero
    private var adaptation = SidebarAdaptation()
    private var configurationPending = false

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
        middle.onPresented = { [weak self] open in
            guard let self, open != isContentPresented else { return }
            isContentPresented = open
            if let visibility = effectiveVisibility {
                onVisibilityChanged?(visibility)
            }
        }
        setChildren([sidebar])
    }

    /// Whether a content column stands between the sidebar and the detail.
    private var hasContentColumn: Bool { pages.count > 2 }

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

    /// The pages go in WinUI's navigation view, which places them; the panel holds it alone.
    @discardableResult
    override func setItems(_ items: [WinUILayoutItem]) -> Bool {
        guard items.count != pages.count || !zip(items, pages).allSatisfy({ $0.arranges(like: $1) }) else { return false }

        pages = items
        for page in items { page.view.placingLayout = nil }
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

    /// What WinUI's navigation view asked, never its pages' own sizes: WinUI measures them in the room it gives them.
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
            asked = sidebar.measure(width: size.width, height: size.height)
        }
        adaptToFirstRoom(width: bounds.width)
        sidebar.layout(bounds)
    }

    /// The host's one adaptation: a window wide enough for both panes opens with its sidebar shown, and says so.
    private func adaptToFirstRoom(width: Double) {
        guard adaptation.room(width, breakpoint: WinUISidebarView.expandsAt, shown: isPresented) else { return }

        present(true)
        onPresentationChanged?(true)
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
            if pages.count > 2, detailWidthBounds?.last != 0 {
                middle.set(
                    sidebar: pages[1].view, detail: pages[2].view, row: detailRow,
                    open: isContentPresented, paneLength: Self.paneLength(contentPaneLength))
                sidebar.set(
                    sidebar: pages.first?.view, detail: middle, row: nil,
                    open: isPresented, paneLength: Self.paneLength(sidebarPaneLength))
            } else {
                middle.set(sidebar: nil, detail: nil, row: nil, open: false)
                sidebar.set(
                    sidebar: pages.first?.view, detail: pages.dropFirst().first?.view, row: detailRow,
                    open: isPresented, paneLength: Self.paneLength(sidebarPaneLength))
            }
        }
    }

    override func detach() {
        super.detach()
        onPresentationChanged = nil
        onVisibilityChanged = nil
        middle.detach()
        sidebar.detach()
    }
}
