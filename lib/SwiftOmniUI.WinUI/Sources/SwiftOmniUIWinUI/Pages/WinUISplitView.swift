// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// A NavigationSplitView: the sidebar page in WinUI's own navigation pane - beside the detail page where the window is wide,
/// over it and closed by a click beside it where it is narrow - which WinUI places, as it places any Windows app's.
/// Whether the sidebar shows is SwiftOmniUI's binding, which the window's chrome toggles and which follows what WinUI
/// shows. An automatic presentation can open in a wide first room; an explicit
/// application preference owns the initial presentation as well.
/// Design: docs/design/platforms/winui/pages.md#a-split-view
@MainActor
final class WinUISplitView: WinUILayoutView {
    /// Whether the sidebar shows.
    private(set) var isPresented = false
    var automaticallyOpensSidebar = true

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

    override var contentSizeDependsOnHeight: Bool { true }

    /// Each intrinsic query measures this native split at that complete
    /// proposal. A result from its last native callback belongs to another
    /// query, and is zero before the first callback has even run.
    override func contentSize(width: Double?) -> LayoutSize {
        contentSize(proposal: ProposedViewSize(width: width))
    }

    override func contentSize(proposal: ProposedViewSize) -> LayoutSize {
        sidebar.measure(width: proposal.width, height: proposal.height)
    }

    override var hasNativeProposals: Bool { true }

    override func nativeProposals(width: Double?, size: LayoutSize) -> [NativeProposal] {
        [NativeProposal(view: sidebar, place: Rect(0, 0, width ?? size.width, size.height))]
    }

    override func arrange(in bounds: Rect) {
        adaptToFirstRoom(width: bounds.width)
        for proposal in preparedLayoutPlan(in: bounds) { proposal.view?.layout(proposal.place) }
    }

    /// A newly created window already knows its client width before activation.
    /// Establish a wide window's initial pane while it is still detached, so
    /// its first native frame has the sidebar content instead of a closed pane.
    func prepareFirstPresentation(width: Double) {
        guard width.isFinite, width > 0 else { return }
        // Select Inline/Overlay before opening the pane or activating XAML.
        // ActualWidth is still zero while this window is detached.
        sidebar.prepareFirstRoom(width: width)
        if width >= WinUISidebarView.expandsAt { adaptToFirstRoom(width: width) }
    }

    private func safeArea(for page: WinUIView, in bounds: Rect) -> SafeAreaContext {
        // A page has no column position until it joins the native tree. Its
        // first Measure uses the incoming allocation's safe region.
        let preservingOutsets = page.sourceElement?.observesSafeArea == true
        let actual = page.laidOutFrame
        guard isAttached, page.isAttached, allocatedBounds.width > 0, allocatedBounds.height > 0,
              actual.width > 0, actual.height > 0, let offset = page.layoutOffset(relativeTo: self) else {
            return layoutSafeArea(in: bounds).child(in: bounds, preservingOutsets: preservingOutsets)
        }
        // Pair layout size with layout offset. TransformToVisual includes a
        // native transition's translation; interpreting it as an unsafe strip
        // feeds animated drawing back into the next layout's available width.
        let place = Rect(offset.x, offset.y, actual.width, actual.height)
        return layoutSafeArea(in: allocatedBounds).child(
            in: place, preservingOutsets: preservingOutsets).resizedLayout(to: bounds)
    }

    override func safeAreaChanged() {
        super.safeAreaChanged()
        // Native pages have no `placingLayout` to receive the usual context
        // assignment. Their root closures read the new region on arrangement.
        for page in pages {
            if isReceivingLayoutContext { page.view.withLayoutContext { page.view.safeAreaChanged() } }
            else { page.view.safeAreaChanged() }
        }
    }

    private func release(_ page: WinUIView) {
        guard page.nativeLayoutOwner === self else { return }
        page.nativeLayoutOwner = nil
        page.rootSafeAreaContext = nil
        page.safeAreaContext = nil
    }

    /// The host's one adaptation: a window wide enough for both panes opens with its sidebar shown, and says so.
    private func adaptToFirstRoom(width: Double) {
        let opens = adaptation.room(width, breakpoint: WinUISidebarView.expandsAt, shown: isPresented)
        guard automaticallyOpensSidebar, opens else { return }

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
        WinUILayoutDiagnostics.record("split.configure", view: self,
            "open=\(isPresented) content=\(isContentPresented) automatic=\(automaticallyOpensSidebar) pages=\(pages.map { $0.view.number })")
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
