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

    /// The size requested by the native split for the current proposal.
    private var asked = LayoutSize.zero
    private var adaptation = SidebarAdaptation()
    private var configurationPending = false
    private struct NativeSlot {
        let owner: WinUISidebarView
        let position: Int // pane, toolbar row, content
        let view: WinUIView
    }
    private var ownedSlots: [NativeSlot] = []

    override init() {
        super.init()
        sidebar.placingLayout = self
        middle.nativeLayoutOwner = self
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
            release(page.view)
        }
        pages = items
        for page in items {
            let view = page.view
            view.placingLayout = nil
            guard view.nativeLayoutOwner !== self else { continue }
            view.nativeLayoutOwner = self
            // A SplitView places its pages in XAML, so `WinUIView.layout` never
            // passes them the enclosing safe region. Resolve that region when
            // the native page is arranged, using its actual column position.
            view.rootSafeAreaContext = { [weak self, weak view] bounds in
                guard let self, let view else { return SafeAreaContext(bounds: bounds) }
                return self.safeArea(for: view, in: bounds)
            }
            view.safeAreaContext = nil
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

    /// Measures the native split at the current proposal, including unbounded
    /// intrinsic queries. A previous allocation is not a measurement constraint.
    /// Design: docs/design/platforms/winui/pages.md#a-native-arrangement
    override func measure(width: Double, height: Double) -> LayoutSize {
        guard WinUIView.arranging == 0 else { return super.measure(width: width, height: height) }
        asked = sidebar.measure(width: width, height: height)
        return super.measure(width: width, height: height)
    }

    override func arrange(in bounds: Rect) {
        adaptToFirstRoom(width: bounds.width)
        sidebar.layout(bounds)
    }

    /// A newly created window already knows its client width before activation.
    /// Establish a wide window's initial pane while it is still detached, so
    /// its first native frame has the sidebar content instead of a closed pane.
    func prepareFirstPresentation(width: Double) {
        guard width.isFinite, width >= WinUISidebarView.expandsAt else { return }
        adaptToFirstRoom(width: width)
    }

    private func safeArea(for page: WinUIView, in bounds: Rect) -> SafeAreaContext {
        // TransformToVisual has no useful coordinate before both native views
        // are attached. The page will read this closure again when arranged.
        guard isAttached, page.isAttached,
              allocatedBounds.width > 0, allocatedBounds.height > 0 else {
            return SafeAreaContext(bounds: bounds)
        }
        let parent = origin, child = page.origin
        let place = Rect(child.x - parent.x, child.y - parent.y, bounds.width, bounds.height)
        return layoutSafeArea(in: allocatedBounds).child(
            in: place, preservingOutsets: page.sourceElement?.observesSafeArea == true)
    }

    override func safeAreaChanged() {
        super.safeAreaChanged()
        // Native pages have no `placingLayout` to receive the usual context
        // assignment. Their root closures read the new region on arrangement.
        for page in pages { page.view.safeAreaChanged() }
    }

    private func release(_ page: WinUIView) {
        guard page.nativeLayoutOwner === self else { return }
        page.nativeLayoutOwner = nil
        page.rootSafeAreaContext = nil
        page.safeAreaContext = nil
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
            var next: [NativeSlot] = []
            if let pane = pages.first?.view { next.append(NativeSlot(owner: sidebar, position: 0, view: pane)) }
            if three {
                next.append(NativeSlot(owner: sidebar, position: 2, view: middle))
                next.append(NativeSlot(owner: middle, position: 0, view: pages[2].view))
                next.append(NativeSlot(owner: middle, position: 2, view: pages[1].view))
            } else if pages.count > 1 {
                next.append(NativeSlot(owner: sidebar, position: 2, view: pages[1].view))
            }
            if let detailRow { next.append(NativeSlot(owner: three ? middle : sidebar, position: 1, view: detailRow)) }
            // Detach only changed slots, before attaching any moved page. Replacing
            // the detail must not unload an unchanged pane and its scroll presenter.
            for old in ownedSlots where !next.contains(where: {
                $0.owner === old.owner && $0.position == old.position && $0.view === old.view
            }) {
                old.owner.remove(old.view)
            }
            ownedSlots = next
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
        for page in pages { release(page.view) }
        sidebar.clear()
        middle.clear()
        ownedSlots = []
        super.detach()
        onPresentationChanged = nil
        onVisibilityChanged = nil
        middle.detach()
        sidebar.detach()
    }
}
