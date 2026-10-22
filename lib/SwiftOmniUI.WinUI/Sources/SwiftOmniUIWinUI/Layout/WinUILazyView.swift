// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// One entry per measured identity. Reading the widest row is constant time;
/// changing a width repairs only its path through this indexed max heap.
struct WinUILazyCrossExtents {
    private var heap: [(identity: String, extent: Double)] = []
    private var positions: [String: Int] = [:]

    var maximum: Double? { heap.first?.extent }

    subscript(identity: String) -> Double? {
        get { positions[identity].map { heap[$0].extent } }
        set {
            if let index = positions[identity] {
                if let newValue {
                    guard heap[index].extent != newValue else { return }
                    heap[index].extent = newValue
                } else {
                    let last = heap.removeLast()
                    positions.removeValue(forKey: identity)
                    guard index < heap.count else { return }
                    heap[index] = last
                    positions[last.identity] = index
                }
                repair(at: index)
            } else if let newValue {
                positions[identity] = heap.count
                heap.append((identity, newValue))
                repair(at: heap.count - 1)
            }
        }
    }

    private mutating func swap(_ a: Int, _ b: Int) {
        heap.swapAt(a, b)
        positions[heap[a].identity] = a
        positions[heap[b].identity] = b
    }

    private mutating func repair(at index: Int) {
        var index = index
        if index > 0, heap[index].extent > heap[(index - 1) / 2].extent {
            while index > 0 {
                let parent = (index - 1) / 2
                guard heap[index].extent > heap[parent].extent else { break }
                swap(index, parent)
                index = parent
            }
        } else {
            while index * 2 + 1 < heap.count {
                var child = index * 2 + 1
                if child + 1 < heap.count, heap[child + 1].extent > heap[child].extent { child += 1 }
                guard heap[child].extent > heap[index].extent else { break }
                swap(index, child)
                index = child
            }
        }
    }
}

/// What a lazy container's view does alike: it keeps the children in view
/// mounted - and only those - telling the tree which identities the window
/// wants built, and standing each at the offset its measure says.
///
/// The run's length is the estimates' before the children exist, so the
/// scroll room answers at once; a child's own measure lands as it mounts and
/// shifts the places after it, the way a scroller of estimated rows does.
/// Design: docs/design/host/items.md#the-view-moving
@MainActor
class WinUILazyView: WinUITravellingLayout {
    /// The direction the children stack in.
    let axis: StackArithmetic.Axis

    /// The cells' bookkeeping: identities, mounted children, the runs' measures.
    let cells: LazyCells

    /// The children mounted now, by identity.
    private(set) var mounted: [String: WinUILayoutItem] = [:]
    private var identitiesByView: [Int64: String] = [:]
    private var measurementRows: Set<String> = []
    private var measuredEmptyGeneration = -1
    var isPreparingRows = false
    private var measuringRowsNatively = false

    override var hasNativeProposals: Bool { true }

    // A committed window can contain new rows (including empty fragments)
    // even when its range and the document's estimated extent did not change.
    var needsRowMeasurements: Bool {
        !measurementRows.isEmpty || (cells.requestedItemsAreCurrent
            && cells.element?.lazyRequestGeneration != measuredEmptyGeneration)
    }

    // Row invalidation names its work directly. A viewport pass must not
    // rediscover that work by polling every surviving row's revision.
    func rowMeasurementChanged(_ view: WinUIView) {
        if let identity = identitiesByView[view.number] { measurementRows.insert(identity) }
    }

    func measureMountedRows() {
        measurementRows.formUnion(mounted.keys)
        measuredEmptyGeneration = -1
    }

    func takeMeasurementRows() -> Set<String> {
        let rows = measurementRows
        measurementRows = []
        return rows
    }

    func completedMeasurement(_ identity: String) { measurementRows.remove(identity) }

    func rowSize(_ identity: String, item: WinUILayoutItem, proposedWidth: Double?) -> LayoutSize {
        if let kept = measured[identity], kept.proposal == proposedWidth,
           measuredRevisions[identity] == item.view.measurementRevision,
           measuredContexts[identity] == item.view.layoutContextRevision {
            return kept.size
        }
        let size = measuringRowsNatively
            ? item.size(offered: proposedWidth)
            : Self.querySize { item.size(offered: proposedWidth) }
        cells.measurements += 1
        measured[identity] = (proposedWidth, size)
        measuredRevisions[identity] = item.view.measurementRevision
        measuredContexts[identity] = item.view.layoutContextRevision
        return size
    }

    /// A mounted row has a real measurement before its first visible placement.
    /// Only rows that have not been requested keep an estimated document extent.
    override func prepareLayoutContent(in bounds: Rect, measuringNative: Bool) {
        for (identity, item) in mounted where !item.departing {
            if measured[identity] == nil || measuredRevisions[identity] != item.view.measurementRevision
                || measuredContexts[identity] != item.view.layoutContextRevision {
                measurementRows.insert(identity)
            }
        }
        let previousQuery = Self.queryingSize
        let previousPreparation = isPreparingRows
        let previousNative = measuringRowsNatively
        Self.queryingSize = 0
        isPreparingRows = true
        measuringRowsNatively = measuringNative
        defer {
            Self.queryingSize = previousQuery
            isPreparingRows = previousPreparation
            measuringRowsNatively = previousNative
        }
        _ = contentSize(width: axis == .vertical ? bounds.width : nil)
    }

    func takeEmptyRows() -> [String] {
        guard cells.requestedItemsAreCurrent,
              let generation = cells.element?.lazyRequestGeneration,
              generation != measuredEmptyGeneration else { return [] }
        measuredEmptyGeneration = generation
        return cells.orderedIdentities[cells.built].filter { mounted[$0] == nil }
    }

    // New rows must have real arranged coordinates before the native scroller
    // can use them as anchors. Promote them on the following measure pass.
    private var pendingAnchors: Set<Int64> = []
    private var placedAnchors: Set<Int64> = []
    private var readyAnchors: Set<Int64> = []
    private var mountedSourceID: ObjectIdentifier?
    private var hasMountedSource = false
    private var lastAcknowledgedGeneration = 0

    /// The scroller whose window the run answers, and the ear it hears it by.
    private weak var watching: WinUIScrollView?

    /// Natural sizes survive scrolling; content invalidation or a changed
    /// cross-axis proposal clears only the measurements that can be stale.
    var measured: [String: (proposal: Double?, size: LayoutSize)] = [:]
    /// The revision of each row's view when it was measured: a row is measured again when its own view changed.
    var measuredRevisions: [String: Int] = [:]
    private var measuredContexts: [String: Int] = [:]
    var measuredRevision = -1
    var measuredAcross: Double?
    var naturalAcross = 44.0
    /// The across size of every row measured in the room `measuredAcross` names: the
    /// widest row the document was told about, and not the widest row now mounted.
    var acrossWidest = WinUILazyCrossExtents()
    var geometryChanged = false
    var measuredExtent = 0.0
    private var contentExtentRevision = 0
    override var parentMeasurementRevision: Int { contentExtentRevision }

    /// A window change under way asks the run again once, not per notice.
    private var retellQueued = false
    /// WinUI's effective viewport is the compositor's window in this panel's coordinates.
    private var effectiveViewport: Rect?
    private var lastTargetViewport: Rect?

    /// The viewport the scroller's own notices last named - newer than the
    /// effective viewport while a move stands between them.
    private var announcedRect: Rect?
    /// A program jump deferred by native layout still owes its requested window.
    private var preparedViewport: Rect?
    private var pendingScrollTarget: Point?
    private(set) var isWaitingForViewport = false
    /// The ear the run hears its scroller's moves by, ahead of the effective viewport's notice.
    private var scrollEar: WinUIScrollEar?
    /// A notice realizing rows is under way; one it raises itself is heard
    /// after it, its viewport already taken.
    private var inViewportChange = false
    private var pendingViewport = false

    /// The mounted rows still on their way: a change's own rows while the change stands, and
    /// afterwards the mounts the motion itself says are moving.
    ///
    /// A row the run no longer shows is none of them. `LazyCells.show` keeps only the rows it
    /// still holds a place for, so one left here would stand against the set the run kept for
    /// good - a viewport re-ask, and a window re-tell, on every pass until the animation ends,
    /// and for ever where none ends.
    var travellingIdentities: Set<String> {
        let moving = cells.animatesChanges
            ? Set(mounted.keys)
            : Set(mounted.compactMap { identity, item in
                places.layoutMotion?.isTravelling(mount: item.mount) == true ? identity : nil
            })
        return Set(moving.filter { cells.position(of: $0) != nil })
    }

    init(axis: StackArithmetic.Axis, cells: LazyCells) {
        self.axis = axis
        self.cells = cells
        super.init()
        cells.prefetchReady = { [weak self] in
            guard let self else { return false }
            // Optional work stands unless a change is still waiting for its rows. It is what
            // fills the window ahead of a moving one, and holding it until every mounted row
            // is measured holds it exactly while the window moves - the frames of a fling -
            // so the rows it would have asked for are the rows the next frame paints.
            return !self.cells.animatesChanges
        }
        swiftomniui_winui_panel_watch_viewport(handle, true)
    }

    /// A sparse patch can refresh row content without rebuilding layout items.
    func refreshContent() {
        let contentChanged = cells.takeItems()
        refreshContent(contentChanged: contentChanged)
    }

    private func refreshContent(contentChanged: Bool) {
        let generation = cells.element?.lazyRequestGeneration ?? 0
        let requestAcknowledged = generation != lastAcknowledgedGeneration
        lastAcknowledgedGeneration = generation
        let source = cells.element?.lazyRows
        let sourceID = source.map(ObjectIdentifier.init)
        let sourceChanged = !hasMountedSource || mountedSourceID != sourceID
        let followsSource = hasMountedSource && source?.predecessor == mountedSourceID
        mountedSourceID = sourceID
        hasMountedSource = true
        // A content revision can be only a drawing change. The row's own measurement
        // revision is the layout signal; an unchanged revision needs no native pass.
        // Structural changes still need a pass to place their new window.
        let rowSizeChanged = contentChanged && !measurementRows.isEmpty
        if sourceChanged || rowSizeChanged {
            invalidateMeasure()
            invalidateArrange()
        }
        if sourceChanged {
            // A local edit removes only widths belonging to deleted identities.
            // Surviving offscreen measurements need neither scanning nor rebuilding.
            if let source, followsSource {
                for identity in source.removed { acrossWidest[identity] = nil }
            } else {
                acrossWidest = WinUILazyCrossExtents()
            }
            measureMountedRows()
            if cells.total != measuredExtent { commitChangedContentExtent() }
        }
        if sourceChanged || requestAcknowledged { retell() }
    }

    func setItems(_ items: [(identity: String, item: WinUILayoutItem)], contentChanged: Bool = false) {
        let sourceID = cells.element?.lazyRows.map(ObjectIdentifier.init)
        let sourceChanged = !hasMountedSource || mountedSourceID != sourceID
        let now = Dictionary(items.map { ($0.0, $0.1) }, uniquingKeysWith: { first, _ in first })
        guard now.keys != mounted.keys || now.contains(where: {
            mounted[$0.key]?.arranges(like: $0.value) != true
        }) else {
            // A content patch may change a row's drawing without changing its
            // geometry. Re-measure only when its own view says its size is stale.
            refreshContent(contentChanged: contentChanged)
            return
        }
        if now.contains(where: { identity, item in
            guard let old = mounted[identity], old.view === item.view else { return false }
            return !old.arranges(like: item)
        }) { cells.animatesChanges = true }
        for (identity, previous) in mounted {
            if now[identity]?.view !== previous.view {
                identitiesByView.removeValue(forKey: previous.view.number)
                measurementRows.remove(identity)
                swiftomniui_winui_scroller_anchor(previous.view.presentationHandle, false)
                pendingAnchors.remove(previous.view.number)
                placedAnchors.remove(previous.view.number)
                readyAnchors.remove(previous.view.number)
            }
            if now[identity]?.view !== previous.view || now[identity]?.values != previous.values {
                measured.removeValue(forKey: identity)
                measuredRevisions.removeValue(forKey: identity)
                measuredContexts.removeValue(forKey: identity)
            }
        }
        if !cells.inserting.isDisjoint(with: now.keys) { cells.animatesChanges = true }
        for item in items {
            identitiesByView[item.item.view.number] = item.identity
            if mounted[item.identity]?.arranges(like: item.item) != true {
                measurementRows.insert(item.identity)
            }
            if cells.inserting.contains(item.identity),
               item.item.element?.transition?.insertion.blur != nil {
                item.item.view.prepareBlur()
            }
            item.item.view.placingLayout = self
            if mounted[item.identity]?.view !== item.item.view
                || mounted[item.identity]?.departing != item.item.departing {
                let view = item.item.view
                swiftomniui_winui_scroller_anchor(view.presentationHandle, false)
                readyAnchors.remove(view.number)
                placedAnchors.remove(view.number)
                if item.item.departing { pendingAnchors.remove(view.number) }
                else { pendingAnchors.insert(view.number) }
            }
        }
        mounted = now
        measuredEmptyGeneration = -1
        refreshContent(contentChanged: contentChanged)
        setChildren(items.map(\.item.view))
        // Recycling and row patches only change this panel's arrangement.
        // The document is invalidated when measured content extent actually
        // changes, never for a paint-only update or an overscan row swap.
        forgetMeasurements()
        invalidateMeasure()
        invalidateArrange()
        if sourceChanged, cells.total != measuredExtent { commitChangedContentExtent() }
    }

    func commitChangedContentExtent() {
        // Internal row invalidation is not a changed document size. Parents
        // observe this revision only when this layout reports a new extent.
        contentExtentRevision &+= 1
        // Discard old arithmetic now; native requests already defer during layout.
        let scroll = clip ?? declaredScroll
        ProgramWrite.perform {
            forgetMeasurements()
            (placingLayout ?? declaredScroll)?.invalidateMeasurements()
            scroll?.invalidateContentExtent()
        }
    }

    /// The scroller an ancestor element declares on this run's own axis, where the placing
    /// layouts do not reach one yet.
    private var declaredScroll: WinUIScrollView? {
        var ancestor = sourceElement?.parent
        while let each = ancestor {
            if let scroll = each.winUI.view as? WinUIScrollView, scroll.orientation.takes(axis) { return scroll }
            ancestor = each.parent
        }
        return nil
    }

    /// The nearest scroller clipping this run on its own axis, found up the
    /// placing layouts through the document it holds, or none: a scroller
    /// turned the other way narrows nothing of this run's window.
    private var clip: WinUIScrollView? {
        var layout: WinUILayoutView? = placingLayout
        while let current = layout {
            if let document = current as? WinUIScrollDocument {
                guard let scroll = document.scrollView else { break }
                if scroll.orientation.takes(axis) { return scroll }
                layout = scroll.placingLayout
            } else {
                layout = current.placingLayout
            }
        }
        return nil
    }

    /// Scroll notices name the actual position before layout's viewport event catches up.
    private var viewport: Rect? {
        announcedRect ?? effectiveViewport
    }

    func viewportReported(_ rect: Rect) {
        viewportChanged(rect)
    }

    private func currentNativeViewport() -> Rect? {
        guard let scroll = watching else { return nil }
        let result = scroll.scroller.viewport(of: self)
        switch result {
        case .ready(let rect):
            isWaitingForViewport = false
            return rect
        case .failed:
            preconditionFailure("WinUI could not read the lazy view's native viewport")
        case .notReady:
            // The relay retains the request and resumes it from a real native
            // layout notification. Do not turn an old allocation into a viewport.
            isWaitingForViewport = true
            effectiveViewport = nil
            announcedRect = nil
            lastTargetViewport = nil
            preparedViewport = nil
            return nil
        }
    }

    /// A native viewport notice triggers a fresh intersection read. Its event
    /// rectangle can already precede another allocation or compositor offset.
    /// Program jumps supply their explicit target separately.
    func viewportChanged(_ reported: Rect, effective: Bool = true, target override: Rect? = nil,
                         completingJump: Bool = false) {
        guard clip != nil else { return }
        watchClip()
        let rect: Rect
        if effective {
            guard let current = currentNativeViewport() else { return }
            rect = current
            effectiveViewport = current
            announcedRect = current
        } else {
            rect = reported
        }
        // A finite empty intersection is a real offscreen window. It must
        // retire the previous visible range instead of waiting for attachment.
        guard rect.x.isFinite, rect.y.isFinite, rect.width.isFinite, rect.height.isFinite,
              rect.width >= 0, rect.height >= 0 else {
            preconditionFailure("WinUI supplied an invalid lazy viewport")
        }
        isWaitingForViewport = false
        if let override { preparedViewport = override }
        // A notice a mount or a place of this one's own raises answers nothing
        // new - but its viewport is news, so it re-asks once this one is over.
        guard !inViewportChange else { pendingViewport = true; return }
        inViewportChange = true
        defer {
            inViewportChange = false
            if pendingViewport {
                pendingViewport = false
                WinUIDoorbell.afterPass { [weak self] in
                    guard let self, let viewport = self.viewport else { return }
                    self.viewportChanged(viewport, effective: false)
                }
            }
        }
        guard let target = override ?? preparedViewport ?? announcedRect ?? viewport else { return }
        let grid = self is WinUILazyGridView
        let revision = grid ? cells.runs.revision : cells.extents.revision
        let keeping = travellingIdentities
        // Anchor geometry follows the actual native window. Only an explicit
        // program jump selects a different window before that position changes.
        let incoming = windowSpan(in: target)
        // A finite zero-area panel has not yet received a native allocation.
        // Preserve the previous window until the scroller can name real room.
        guard cells.orderedIdentities.isEmpty || allocatedExtent > 0 else { return }
        let span = self.span ?? incoming
        let realize = incoming
        guard lastTargetViewport != target || cells.window?.span != (span ?? 0..<0)
            || cells.window?.realize != (realize ?? 0..<0)
            || cells.window?.revision != revision || cells.needsWindowUpdate
            || measuredRevision != measurementRevision || needsRowMeasurements || geometryChanged
            || cells.retained != keeping
        else { preparedViewport = nil; return }
        // Never replace native rows during a pass that cannot measure their
        // replacements. The frame clock resumes this whole update after the pass.
        guard WinUIView.arranging == 0, WinUIView.measuring == 0 else {
            retell()
            return
        }
        preparedViewport = nil
        let previous = lastTargetViewport
        lastTargetViewport = target
        if !cells.needsMeasurement, !needsRowMeasurements, !geometryChanged, !cells.animatesChanges,
           measuredRevision == measurementRevision, cells.window?.revision == revision,
           (axis == .vertical ? previous?.width == target.width : previous?.height == target.height),
           let span, let realize {
            let perRun = cells.window?.perRun ?? 1
            let wanted = grid
                ? cells.runs.places(in: realize, overscan: 0, count: (cells.orderedIdentities.count + perRun - 1) / perRun)
                : cells.places(in: realize, overscan: 0)
            let lower = min(cells.orderedIdentities.count, max(0, wanted.lowerBound - 1) * perRun)
            let upper = min(cells.orderedIdentities.count, (wanted.upperBound + 1) * perRun)
            if !wanted.isEmpty, (lower..<upper) == cells.built {
                cells.show(span, perRun: perRun, grid: grid, realize: realize, keeping: keeping,
                           prefetch: false, demand: incoming)
                return
            }
        }
        var needsArrangement = false
        defer {
            // XAML must measure the changed extent before placing the new rows.
            if needsArrangement { invalidateArrange() }
        }
        var measuredWindows: Set<Range<Int>> = []
        while true {
            let built = cells.built
            tellWindow(span ?? 0..<0, realize: realize ?? 0..<0, demand: incoming)
            // Complete only this viewport. Shorter-than-estimated rows can expose
            // further rows; those are visible work, not next-frame prefetch.
            guard WinUIView.arranging == 0, WinUIView.measuring == 0,
                  cells.element?.handler(.realizedChanged) == nil || cells.requestedItemsAreCurrent,
                  placed != nil else { return }
            if cells.built != built || measuredRevision != measurementRevision
                || needsRowMeasurements || cells.anchorShift != 0 {
                let actual = laidOutFrame
                prepareLayoutContent(in: Rect(0, 0, actual.width, actual.height), measuringNative: true)
                needsArrangement = true
            }
            let after = grid ? cells.runs.revision : cells.extents.revision
            if cells.needsMeasurement, !completingJump {
                retell()
                return
            }
            guard cells.needsMeasurement || needsRowMeasurements || cells.window?.revision != after else { return }
            // A pending native proposal or a repeated range needs a layout pass,
            // not another synchronous attempt. Reentrant viewport changes are
            // handled by the existing pendingViewport handoff above.
            guard !pendingViewport,
                  measuredWindows.insert(cells.built).inserted else {
                retell()
                return
            }
        }
    }

    private var allocatedExtent: Double {
        axis == .vertical
            ? (placed?.height ?? laidOutFrame.height) : (placed?.width ?? laidOutFrame.width)
    }

    /// The window `rect` shows of the run, clipped to its document extent.
    private func windowSpan(in rect: Rect) -> Range<Double>? {
        guard !cells.orderedIdentities.isEmpty, rect.width > 0, rect.height > 0 else { return nil }
        let start = axis == .vertical ? rect.y : rect.x
        let room = axis == .vertical ? rect.height : rect.width
        // The native scroller bounds its own offset. This run can be wholly
        // outside that viewport when several lazy containers share a document;
        // clamping to its first/last page would build offscreen rows forever.
        // XAML's window jitters by a float's worth between notices; snapped to
        // a sixty-fourth, one place stands either in or out of it, not both.
        let grain = 1.0 / 64.0
        let low = (max(0, start) / grain).rounded() * grain
        let high = (min(allocatedExtent, start + room) / grain).rounded() * grain
        guard high > low else { return nil }
        return low..<high
    }

    /// The window the run shows, clipped to its document extent.
    var span: Range<Double>? {
        viewport.flatMap { windowSpan(in: $0) }
    }

    /// Asks the tree for the children the window wants; each kind answers
    /// which places a span holds. No scroller to narrow by means all of them.
    /// One retell a pass, once the layout under way is over.
    private func retell() {
        guard !retellQueued else { return }
        retellQueued = true
        WinUIDoorbell.afterPass { [weak self] in
            guard let self else { return }
            self.retellQueued = false
            self.watchClip()
            if self.geometryChanged {
                self.geometryChanged = false
                // Extent changes have their own coalesced upward report. A
                // new visible range or internal placement only dirties this panel.
                self.invalidateArrange()
            }
            // No clip to narrow by means all of it stands in view - a lazy
            // container outside any scroller builds every child.
            guard self.watching != nil else {
                guard self.isAttached else { return }
                // Attachment can precede installation of placingLayout links.
                // A declared same-axis scroller is not an unbounded container.
                guard self.declaredScroll == nil else { return }
                self.cells.tellAll()
                return
            }
            // Layout and native anchoring may move the viewport after the notification.
            // Reconcile against its current position, not the queued notification's origin.
            guard let rect = self.currentNativeViewport() else { return }
            self.announcedRect = rect
            let revision = self is WinUILazyGridView ? self.cells.runs.revision : self.cells.extents.revision
            if self.preparedViewport != nil || self.lastTargetViewport != self.viewport || self.cells.window == nil
                || self.cells.needsMeasurement || self.cells.window?.span != (self.span ?? 0..<0)
                || self.cells.window?.revision != revision
                || self.measuredRevision != self.measurementRevision || self.needsRowMeasurements
                || self.cells.retained != self.travellingIdentities {
                if let viewport = self.viewport { self.viewportChanged(viewport, effective: false) }
            }
        }
    }

    /// The places standing in `span`, as the kind's runs count them; `realize`
    /// is the window a moving scroller can show before the next notice.
    func tellWindow(_ span: Range<Double>, realize: Range<Double>, demand: Range<Double>?) {}

    /// Update anchor bookkeeping; only native viewport reports establish the visible coordinates.
    /// Native scroll anchoring adjusts the offset after layout commits the new extent.
    func commitAnchor(perRun: Int = 1, grid: Bool = false) {
        _ = cells.correctedOrigin(perRun: perRun, grid: grid)
    }

    /// Recomputes the places when the scroller's window moved.
    private func watchClip() {
        let scroll = clip
        guard scroll !== watching else { return }
        watching = scroll
        effectiveViewport = nil
        lastTargetViewport = nil
        announcedRect = nil
        preparedViewport = nil
        pendingScrollTarget = nil
        isWaitingForViewport = false
        scrollEar = nil
        if let scroll {
            let ear = WinUIScrollEar(owner: self) { [weak self] in self?.scrollerMoved() }
            ear.announce = { [weak self] target in self?.prepareFor(target) }
            scroll.scroller.ears.append(ear)
            scrollEar = ear
        }
    }

    /// Realize the current native viewport when the scroller moves.
    private func scrollerMoved() {
        guard let rect = currentNativeViewport() else { return }
        // A native scroll notification records position only. Coalesce row
        // realization outside the ScrollPresenter's callback/layout stack.
        announcedRect = rect
        if let target = pendingScrollTarget {
            pendingScrollTarget = nil
            prepareFor(target)
        }
        retell()
    }

    private func hasMountedWindow(at rect: Rect) -> Bool {
        guard cells.requestedItemsAreCurrent, let span = windowSpan(in: rect),
              let window = cells.window else { return false }
        let perRun = window.perRun
        let wanted = self is WinUILazyGridView
            ? cells.runs.places(in: span, overscan: 0,
                                count: (cells.orderedIdentities.count + perRun - 1) / perRun)
            : cells.places(in: span, overscan: 0)
        guard !wanted.isEmpty else { return false }
        return cells.built.lowerBound <= wanted.lowerBound * perRun
            && cells.built.upperBound >= min(cells.orderedIdentities.count, wanted.upperBound * perRun)
    }

    /// A jump the program makes: realize the window it lands in before the
    /// scroller moves, so the compositor's first frame at the new offset
    /// already shows rows rather than the bare document behind them.
    func prepareFor(_ target: Point) {
        guard let scroll = watching else { return }
        guard var rect = currentNativeViewport() else {
            pendingScrollTarget = target
            return
        }
        pendingScrollTarget = nil
        let standing = scroll.scroller.standing.offset
        if axis == .vertical { rect.y += target.y - standing.y }
        else { rect.x += target.x - standing.x }
        viewportChanged(rect, effective: false, target: rect, completingJump: true)
    }

    /// Animation readiness only: a place in the air lands in the window it
    /// asks for, and a move of the scroller's brings one.
    func canArrangeRows() -> Bool {
        // Only a change still waiting for its rows is held back. A plain viewport pass places
        // what it holds; holding it would leave the mounted rows standing at the places of the
        // last arrangement until some later pass happened to resume them.
        guard cells.animatesChanges else { return true }
        // A source patch can reach Arrange before its window patch and native
        // measurements. Do not consume patchArrived/animatesChanges in that
        // intermediate pass: it would leave the real insertion with no law.
        guard cells.element?.handler(.realizedChanged) == nil || cells.requestedItemsAreCurrent else {
            retell()
            return false
        }
        // The rows the change added stand in the built window and are measured in the pass before
        // its arrangement. A row outside that window - one the window has dropped, or one kept
        // alive by its own travelling - is no part of what is waiting, and an unmeasured one of
        // those must not hold the change back for good.
        let waiting = mounted.contains { entry in
            guard !entry.value.departing, let place = cells.position(of: entry.key),
                  cells.built.contains(place) else { return false }
            return measured[entry.key] == nil
                || measuredRevisions[entry.key] != entry.value.view.measurementRevision
                || measuredContexts[entry.key] != entry.value.view.layoutContextRevision
        }
        guard !waiting else {
            retell()
            return false
        }
        return true
    }

    override func arrange(in bounds: Rect) {
        // A change's motion stands until the arrangement that can place its rows: a run that
        // holds its children by a window mounts those rows in a later patch, which names no
        // timing of its own. The first ready arrangement takes the kept motion, so none outlives
        // the change it belongs to.
        let ready = canArrangeRows()
        let motion = ready ? takeArrivalMotion() : nil
        if cells.animatesChanges, let motion { places.animation = motion }
        places.begin(width: axis == .vertical ? bounds.width : bounds.height, animating: cells.animatesChanges && ready,
                     anchorOffset: Point(axis == .horizontal ? cells.anchorShift : 0,
                                         axis == .vertical ? cells.anchorShift : 0), refining: true,
                     consumingPatch: ready, height: axis == .vertical ? bounds.height : bounds.width,
                     followingPresentation: ready ? takePresentationFrame() : false,
                     presentedLanes: ready ? takePresentedLanes() : [],
                     presentedItems: ready ? takePresentedItems() : [:])
        if ready {
            cells.animatesChanges = false
            cells.anchorShift = 0
        }
        for proposal in preparedLayoutPlan(in: bounds) {
            guard let view = proposal.view, let identity = identitiesByView[view.number],
                  var item = mounted[identity] else { continue }
            if cells.animatesChanges || cells.inserting.remove(identity) == nil { item.fadeIn = nil }
            place(item, at: proposal.place)
        }
        retell()
    }

    /// Measuring again, the window is re-asked: a new pass is a new chance
    /// for the places the run holds.
    override func measure(width: Double, height: Double) -> LayoutSize {
        for number in readyAnchors {
            guard let identity = identitiesByView[number], let item = mounted[identity], !item.departing else { continue }
            swiftomniui_winui_scroller_anchor(item.view.presentationHandle, true)
        }
        readyAnchors.removeAll(keepingCapacity: true)
        retell()
        return super.measure(width: width, height: height)
    }

    override func place(_ item: WinUILayoutItem, at place: Rect) {
        super.place(item, at: place)
        if WinUIView.arranging > 0, !item.departing, pendingAnchors.contains(item.view.number) {
            placedAnchors.insert(item.view.number)
        }
    }

    override func arrange(width: Double, height: Double) {
        super.arrange(width: width, height: height)
        readyAnchors.formUnion(placedAnchors)
        pendingAnchors.subtract(placedAnchors)
        placedAnchors.removeAll(keepingCapacity: true)
    }

    override func detach() {
        for item in mounted.values {
            swiftomniui_winui_scroller_anchor(item.view.presentationHandle, false)
        }
        pendingAnchors.removeAll()
        placedAnchors.removeAll()
        readyAnchors.removeAll()
        identitiesByView.removeAll()
        measurementRows.removeAll()
        measuredEmptyGeneration = -1
        cells.cancelPrefetch()
        super.detach()
        swiftomniui_winui_panel_watch_viewport(handle, false)
        effectiveViewport = nil
        lastTargetViewport = nil
        announcedRect = nil
        preparedViewport = nil
        pendingScrollTarget = nil
        isWaitingForViewport = false
        watching = nil
        scrollEar = nil
    }
}

/// A lazy stack: one child a place.
final class WinUILazyStackView: WinUILazyView {
    /// The room between two children.
    var spacing: Double? {
        didSet { cells.extents.spacing = spacing; if spacing != oldValue { invalidateMeasurements() } }
    }

    /// The room inside the stack's own edge.
    var padding = EdgeInsets(0) {
        didSet {
            if padding != oldValue {
                cells.extents.padding = (head: axis == .vertical ? padding.top : padding.left,
                                       tail: axis == .vertical ? padding.bottom : padding.right)
                invalidateMeasurements()
            }
        }
    }

    /// The current proposal determines wrapping; intrinsic queries read the
    /// measured extent index without substituting a previous native frame.
    override func contentSize(width: Double?) -> LayoutSize {
        let width = width.flatMap { $0.isFinite ? Double(Float($0)) : nil }
        let across = axis == .vertical
            ? width.map { max(0, $0 - padding.left - padding.right) } : nil
        if isPreparingRows {
            let revision = cells.extents.revision
            let widest = acrossWidest.maximum
            if measuredAcross != across {
                // Retain offscreen extents as estimates. Resetting them all to 44
                // changes the scroll range before any new measurement exists.
                // The proposal-keyed cache below still remeasures every mounted
                // row at the new width before committing its actual extent.
                acrossWidest = WinUILazyCrossExtents()
                measuredAcross = across
                measureMountedRows()
                forgetMeasurements()
            }
            // Empty fragments are acknowledged once per window, not per measure.
            for identity in takeEmptyRows() {
                cells.extents.measure(identity, extent: 0)
            }
            for identity in takeMeasurementRows() {
                guard let item = mounted[identity], !item.departing,
                      cells.position(of: identity) != nil else { continue }
                let margin = item.values.margin
                let proposal = across.map { Double(Float(max(0, $0 - margin.left - margin.right))) }
                let size = rowSize(identity, item: item, proposedWidth: proposal)
                let acrossSize = axis == .vertical
                    ? size.width + margin.left + margin.right : size.height + margin.top + margin.bottom
                let extent = axis == .vertical
                    ? size.height + margin.top + margin.bottom
                    : size.width + margin.left + margin.right
                cells.extents.measure(identity, extent: extent)
                acrossWidest[identity] = acrossSize
                completedMeasurement(identity)
            }
            if widest != acrossWidest.maximum { forgetMeasurements() }
            // A finite proposal fixes a vertical stack's returned width. Scanning every
            // row ever measured in this room cannot affect that answer. An intrinsic
            // cross-axis size still uses the widest measured row, including rows that
            // have scrolled out, so the document does not narrow while scrolling.
            if axis != .vertical || width == nil {
                let natural = acrossWidest.maximum ?? (cells.orderedIdentities.isEmpty ? 0 : 44)
                if naturalAcross != natural {
                    geometryChanged = true
                    commitChangedContentExtent()
                }
                naturalAcross = natural
            }
            commitAnchor()
            let total = cells.total
            if cells.extents.revision != revision || total != measuredExtent {
                geometryChanged = true
                forgetLayoutPlans()
                if total != measuredExtent { commitChangedContentExtent() }
            }
            measuredExtent = total
            if !needsRowMeasurements { measuredRevision = measurementRevision }
        }
        let total = cells.total
        return axis == .vertical
            ? LayoutSize(width: width ?? (acrossWidest.maximum ?? naturalAcross) + padding.left + padding.right, height: total)
            : LayoutSize(width: total, height: naturalAcross + padding.top + padding.bottom)
    }

    override func makeLayoutPlan(in bounds: Rect) -> [NativeProposal] {
        let across = max(0, axis == .vertical
            ? bounds.width - padding.left - padding.right
            : bounds.height - padding.top - padding.bottom)
        var proposals: [NativeProposal] = []
        for (identity, item) in mounted {
            let margin = item.values.margin
            guard let place = cells.position(of: identity) else { continue }
            let proposal = axis == .vertical
                ? Double(Float(max(0, across - margin.left - margin.right))) : nil
            let size = rowSize(identity, item: item, proposedWidth: proposal)
            let extent = cells.extents.extent(of: identity)
            let run = cells.offset(of: place)
            let frame: Rect
            if axis == .vertical {
                let open = across - margin.left - margin.right
                let expands = item.values.expandingAxes == .horizontal || item.values.expandingAxes == .both
                let width = Extent.of(
                    option: expands ? 3 : item.values.horizontal, stated: item.values.width,
                    natural: size.width,
                    available: open, minimum: item.values.minimumWidth,
                    maximum: item.values.maximumWidth)
                let x = padding.left + margin.left + Extent.start(
                    option: item.values.horizontal, extent: width, start: 0,
                    available: open,
                    guide: item.values.horizontalGuide?.slot == item.values.horizontal
                        ? item.values.horizontalGuide?.offset : nil)
                frame = Rect(x: x, y: run + margin.top, width: width,
                             height: extent - margin.top - margin.bottom)
            } else {
                let open = across - margin.top - margin.bottom
                let expands = item.values.expandingAxes == .vertical || item.values.expandingAxes == .both
                let height = Extent.of(
                    option: expands ? 3 : item.values.vertical, stated: item.values.height,
                    natural: size.height,
                    available: open, minimum: item.values.minimumHeight,
                    maximum: item.values.maximumHeight)
                let y = padding.top + margin.top + Extent.start(
                    option: item.values.vertical, extent: height, start: 0,
                    available: open,
                    guide: item.values.verticalGuide?.slot == item.values.vertical
                        ? item.values.verticalGuide?.offset : nil)
                frame = Rect(x: run + margin.left, y: y,
                             width: extent - margin.left - margin.right, height: height)
            }
            proposals.append(NativeProposal(view: item.view, place: direction.places(frame, in: bounds)))
        }
        return proposals
    }

    override func tellWindow(_ span: Range<Double>, realize: Range<Double>, demand: Range<Double>?) {
        cells.show(span, realize: realize, measureBeforeExpanding: true,
                   keeping: travellingIdentities, prefetch: false, demand: demand)
    }
}

/// A lazy grid: the cells fill the tracks across its run, a run at a time -
/// a `LazyVGrid`'s run is a row of its columns, a `LazyHGrid`'s a column of
/// its rows.
final class WinUILazyGridView: WinUILazyView {
    /// The tracks across - `flowColumns` down a grid, `flowRows` across one.
    var tracks: [GridItem] = [] {
        didSet {
            if tracks != oldValue {
                columns = []
                invalidateMeasurements()
            }
        }
    }

    /// The room between one run and the next.
    var runSpacing = 0.0 {
        didSet { if runSpacing != oldValue { cells.runs.spacing = runSpacing; invalidateMeasurements() } }
    }

    /// Where the tracks stand together across the grid.
    var trackAlignment: AxisAlignment = .center {
        didSet { if trackAlignment != oldValue { invalidateMeasurements() } }
    }
    /// The room between the tracks.
    var trackSpacing = 0.0 {
        didSet {
            if trackSpacing != oldValue {
                columns = []
                invalidateMeasurements()
            }
        }
    }

    /// The room inside the grid's own edge.
    var padding = EdgeInsets(0) {
        didSet {
            if padding != oldValue {
                cells.runs.padding = (head: axis == .vertical ? padding.top : padding.left,
                                       tail: axis == .vertical ? padding.bottom : padding.right)
                invalidateMeasurements()
            }
        }
    }

    /// The track extents at the room now, kept until the room or they change;
    /// a changed count makes new runs, and their measures go.
    private var columns: [Double] = []

    /// The room across - inside the padding, the tracks take it all.
    private var acrossRoom = 0.0

    /// The cells a run holds.
    private var perRun: Int { max(1, columns.count) }

    /// The runs the cells make.
    private var runCount: Int { (cells.orderedIdentities.count + perRun - 1) / perRun }

    override var contentSizeDependsOnHeight: Bool { axis == .horizontal }

    override func contentSize(proposal: ProposedViewSize) -> LayoutSize {
        let height = proposal.height.flatMap { $0.isFinite ? max(0, $0 - padding.top - padding.bottom) : nil }
        return gridContentSize(width: proposal.width, crossHeight: height)
    }

    override func contentSize(width: Double?) -> LayoutSize {
        gridContentSize(width: width, crossHeight: isPreparingRows ? acrossRoom : nil)
    }

    /// Both axes belong to this proposal. An unspecified cross axis resolves
    /// declared tracks at their ideal/minimum extents, not at an old frame.
    private func gridContentSize(width: Double?, crossHeight: Double?) -> LayoutSize {
        let width = width.flatMap { $0.isFinite ? Double(Float($0)) : nil }
        let room = max(0, axis == .vertical
            ? width.map { $0 - padding.left - padding.right } ?? 0
            : crossHeight ?? 0)
        let proposed = LazyGridTracks.resolve(tracks, width: room, spacing: trackSpacing)
        let widths = LazyGridTracks.extents(proposed, width: room, spacing: trackSpacing)
        if isPreparingRows {
            let revision = cells.runs.revision
            if widths != columns {
                // A different grouping invalidates run identities. A width-only
                // change keeps their previous extents as estimates until measured.
                if widths.count != columns.count { cells.runs.reset() }
                columns = widths
                // Each row is measured at its own track's width, which the proposal names: a
                // row whose track kept its width keeps its measurement, so a track count or a
                // width that returns to a former one costs no native measure.
                measureMountedRows()
                geometryChanged = true
                forgetMeasurements()
            }
            var runExtents: [Int: Double] = [:]
            var pendingRuns: Set<Int> = []
            var changedRuns: Set<Int> = []
            if !widths.isEmpty {
                let changed = takeMeasurementRows().union(takeEmptyRows())
                for identity in changed {
                    if let place = cells.position(of: identity) { changedRuns.insert(place / widths.count) }
                }
            }
            for run in changedRuns {
                runExtents[run] = 0
                let start = run * widths.count
                let end = min(cells.orderedIdentities.count, start + widths.count)
                for place in start..<end {
                    let identity = cells.orderedIdentities[place]
                    guard let item = mounted[identity] else {
                        // Retained animation cells can stand outside the requested
                        // window. Do not shrink their run using a partial row.
                        if !cells.requestedItemsAreCurrent || !cells.built.contains(place) {
                            pendingRuns.insert(run)
                        }
                        continue
                    }
                    guard !item.departing else { pendingRuns.insert(run); continue }
                    let track = place % widths.count
                    let margin = item.values.margin
                    let proposal: Double? = axis == .vertical
                        ? Double(Float(max(0, widths[track] - margin.left - margin.right))) : nil
                    let size = rowSize(identity, item: item, proposedWidth: proposal)
                    let extent = axis == .vertical
                        ? size.height + margin.top + margin.bottom
                        : size.width + margin.left + margin.right
                    runExtents[run] = max(runExtents[run] ?? 0, extent)
                    completedMeasurement(identity)
                }
            }
            for (run, extent) in runExtents where !pendingRuns.contains(run) {
                cells.runs.measure(run, extent: extent)
            }
            commitAnchor(perRun: perRun, grid: true)
            let total = cells.runs.total(count: runCount)
            if cells.runs.revision != revision || total != measuredExtent {
                geometryChanged = true
                forgetLayoutPlans()
                if total != measuredExtent { commitChangedContentExtent() }
            }
            measuredExtent = total
            if !needsRowMeasurements { measuredRevision = measurementRevision }
        }
        let count = (cells.orderedIdentities.count + max(1, proposed.count) - 1) / max(1, proposed.count)
        let total = widths.count == columns.count ? cells.runs.total(count: count)
            : cells.runs.padding.head + cells.runs.padding.tail + Double(count) * cells.runs.estimate
                + Double(max(0, count - 1)) * runSpacing
        return axis == .vertical
            ? LayoutSize(width: width ?? (widths.reduce(0, +)
                + Double(max(widths.count - 1, 0)) * trackSpacing + padding.left + padding.right), height: total)
            : LayoutSize(width: total, height: widths.reduce(0, +)
                + Double(max(widths.count - 1, 0)) * trackSpacing + padding.top + padding.bottom)
    }

    override func prepareLayoutContent(in bounds: Rect, measuringNative: Bool) {
        acrossRoom = max(0, axis == .vertical
            ? bounds.width - padding.left - padding.right
            : bounds.height - padding.top - padding.bottom)
        super.prepareLayoutContent(in: bounds, measuringNative: measuringNative)
    }

    override func makeLayoutPlan(in bounds: Rect) -> [NativeProposal] {
        let widths = columns
        guard !widths.isEmpty else { return [] }
        var proposals: [NativeProposal] = []
        var trackOrigins: [Double] = []
        let extent = widths.reduce(0, +) + Double(max(widths.count - 1, 0)) * trackSpacing
        var start = Extent.start(option: trackAlignment.rawValue, extent: extent,
                                 start: axis == .vertical ? padding.left : padding.top,
                                 available: acrossRoom)
        for width in widths {
            trackOrigins.append(start)
            start += width + trackSpacing
        }

        for (identity, item) in mounted {
            guard let place = cells.position(of: identity) else { continue }
            let run = place / widths.count, track = place % widths.count
            let margin = item.values.margin
            let proposal = axis == .vertical
                ? Double(Float(max(0, widths[track] - margin.left - margin.right))) : nil
            let size = rowSize(identity, item: item, proposedWidth: proposal)
            let origin = cells.runs.offset(of: run, count: runCount)
            let runExtent = cells.runs.extent(of: run)
            let frame: Rect
            if axis == .vertical {
                let open = widths[track] - margin.left - margin.right
                let expands = item.values.expandingAxes == .horizontal || item.values.expandingAxes == .both
                let width = Extent.of(
                    option: expands ? 3 : item.values.horizontal, stated: item.values.width,
                    natural: size.width,
                    available: max(0, open), minimum: item.values.minimumWidth,
                    maximum: item.values.maximumWidth)
                let x = trackOrigins[track] + margin.left + Extent.start(
                    option: item.values.horizontal, extent: width, start: 0,
                    available: max(0, open),
                    guide: item.values.horizontalGuide?.slot == item.values.horizontal
                        ? item.values.horizontalGuide?.offset : nil)
                frame = Rect(x: x, y: origin + margin.top, width: width,
                             height: runExtent - margin.top - margin.bottom)
            } else {
                let open = widths[track] - margin.top - margin.bottom
                let expands = item.values.expandingAxes == .vertical || item.values.expandingAxes == .both
                let height = Extent.of(
                    option: expands ? 3 : item.values.vertical, stated: item.values.height,
                    natural: size.height,
                    available: max(0, open), minimum: item.values.minimumHeight,
                    maximum: item.values.maximumHeight)
                let y = trackOrigins[track] + margin.top + Extent.start(
                    option: item.values.vertical, extent: height, start: 0,
                    available: max(0, open),
                    guide: item.values.verticalGuide?.slot == item.values.vertical
                        ? item.values.verticalGuide?.offset : nil)
                frame = Rect(x: origin + margin.left, y: y,
                             width: runExtent - margin.left - margin.right, height: height)
            }
            proposals.append(NativeProposal(view: item.view, place: direction.places(frame, in: bounds)))
        }
        return proposals
    }

    override func tellWindow(_ span: Range<Double>, realize: Range<Double>, demand: Range<Double>?) {
        cells.show(span, perRun: perRun, grid: true, realize: realize, keeping: travellingIdentities,
                   prefetch: false, demand: demand)
    }
}

private extension Axis {
    /// Whether a scroller of this axis can clip a lazy run of `axis` - a
    /// vertical run answers a vertical scroller's window, or one going both
    /// ways.
    func takes(_ axis: StackArithmetic.Axis) -> Bool {
        switch (self, axis) {
        case (.both, _), (.vertical, .vertical), (.horizontal, .horizontal): true
        default: false
        }
    }
}
