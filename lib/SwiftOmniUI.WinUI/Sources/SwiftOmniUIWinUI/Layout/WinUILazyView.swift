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
    /// A reader can name a row outside the native window. Keep that destination
    /// requested until its real layout has satisfied the scroll operation.
    var readerTarget: String?
    private var readerAnchor: Double?

    func requestReaderTarget(_ identity: String, anchor: Double?) {
        readerTarget = identity
        readerAnchor = anchor
        guard let place = cells.position(of: identity) else { return }
        let perRun = self is WinUILazyGridView ? max(1, cells.window?.perRun ?? 1) : 1
        let grid = self is WinUILazyGridView
        let run = place / perRun
        let count = (cells.orderedIdentities.count + perRun - 1) / perRun
        let start = grid ? cells.runs.offset(of: run, count: count) : cells.offset(of: place)
        let extent = grid ? cells.runs.extent(of: run) : cells.extents.extent(of: identity)
        let target = start..<(start + max(1, extent))
        cells.show(cells.window?.span ?? target, perRun: perRun, grid: grid, realize: target)
    }
    private var identitiesByView: [Int64: String] = [:]
    private var measurementRows: Set<String> = []
    private var measuredEmptyGeneration = -1
    var isPreparingRows = false

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
        // Row geometry selects the final native proposal; it must not prepare
        // the same subtree first at an unspecified height. prepareChildren
        // measures the completed plan and retries it if native sizes change.
        let size = Self.querySize { item.size(offered: proposedWidth) }
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
        Self.queryingSize = 0
        isPreparingRows = true
        defer {
            Self.queryingSize = previousQuery
            isPreparingRows = previousPreparation
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
    private var previousPreparationDuration = 0.0
    private var latestPreparationDuration = 0.0
    private var preparedRowCosts = WinUILazyCrossExtents()
    private var preparingIdentities: Set<String> = []
    private(set) var scrollVelocity = 0.0
    private(set) var scrollAcceleration = 0.0
    private(set) var scrollInterval = 0.0
    var preparationDuration: Double { max(latestPreparationDuration, preparedRowCosts.maximum ?? 0) }
    private(set) var scrollObservationLead = 0.0
    private var preparationStarted: Double?
    private var arrangedPreparation: (started: Double, rendered: Double, identities: Set<String>)?
    private var displayInterval: Double {
        let refresh = WinUIFrameClock.current?.refreshInterval ?? 0
        return refresh > 0 ? refresh : scrollInterval
    }

    /// The viewport the scroller's own notices last named - newer than the
    /// effective viewport while a move stands between them.
    private var announcedRect: Rect?
    /// A program jump deferred by native layout still owes its requested window.
    private var preparedViewport: Rect?
    /// ScrollTo without animation is still asynchronous. Keep its prepared
    /// window until that native operation completes or is cancelled.
    private var jumpViewport: Rect?
    /// ScrollTo is asynchronous. Keep already placed rows covering the old
    /// viewport until the native request completes; never build the gap between
    /// that viewport and a distant destination.
    private var jumpRetained: Set<String> = []
    private var pendingScrollTarget: Point?
    private(set) var isWaitingForViewport = false
    /// The ear the run hears its scroller's moves by, ahead of the effective viewport's notice.
    private var scrollEar: WinUIScrollEar?
    /// A notice realizing rows is under way; one it raises itself is heard
    /// after it, its viewport already taken.
    private var inViewportChange = false
    private var pendingViewport = false
    private var fillingWindow = false
    private var pendingContentExtent = false
    private(set) var expansionRuns = 1

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
        var kept = jumpRetained
        if let destination = jumpViewport.flatMap({ windowSpan(in: $0) }) {
            let perRun = cells.window?.perRun ?? 1
            let count = cells.orderedIdentities.count
            let places = self is WinUILazyGridView
                ? cells.runs.places(in: destination, overscan: 0, count: (count + perRun - 1) / perRun)
                : cells.places(in: destination, overscan: 0)
            let lower = min(count, max(0, places.lowerBound - 1) * perRun)
            let upper = min(count, (places.upperBound + 1) * perRun)
            // Rows already selected by the destination need no extra retention
            // request. Tiny moves within one mounted window must remain no-ops.
            kept = Set(kept.filter { identity in
                guard let position = cells.position(of: identity) else { return false }
                return !(lower..<upper).contains(position)
            })
        }
        return Set(moving.union(kept).filter { cells.position(of: $0) != nil })
    }

    init(axis: StackArithmetic.Axis, cells: LazyCells) {
        self.axis = axis
        self.cells = cells
        cells.extents.usesMeasuredEstimate = true
        cells.runs.usesMeasuredEstimate = true
        super.init()
        cells.onRowsRequested = { [weak self] in
            // Opening a page measures the whole first viewport, often with cold
            // templates/fonts. It is not the latency of one incoming scroll
            // batch and must not inflate the first fling's prediction.
            guard let self, self.watching?.held == true else { return }
            let next = Set(self.cells.orderedIdentities[self.cells.built])
            let continues = !self.preparingIdentities.isDisjoint(with: next)
            self.preparingIdentities.formIntersection(next)
            self.preparingIdentities.formUnion(next.filter { self.mounted[$0] == nil })
            // Expanding the same unarranged window must not restart the timer:
            // a cheap neighbour after a table used to hide that table's entire
            // construction time. A disjoint request does supersede the old work.
            if !continues { self.preparationStarted = WinUIFrameClock.monotonic() }
        }
        cells.prefetchReady = { [weak self] in
            guard let self else { return false }
            guard !self.isDetached, !self.cells.animatesChanges,
                  WinUIView.arranging == 0, WinUIView.measuring == 0,
                  self.placed != nil else { return false }
            // Native layout completes the previous request. Do not synchronously
            // measure image-heavy rows to permit another prefetch in this turn.
            return !self.needsRowMeasurements && !self.hasUnplacedRows()
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
        // A retained row may grow without changing the source identities.
        // Its later siblings still need the patch's placement law.
        if rowSizeChanged { cells.animatesChanges = true }
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
                preparedRowCosts[identity] = nil
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
        if fillingWindow { pendingContentExtent = true; return }
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
        // EffectiveViewportChanged can arrive inside XAML's own layout. Fill
        // visible demand from the coalesced turn, never mutate children there.
        watchClip()
        guard let current = currentNativeViewport() else { return }
        effectiveViewport = current
        announcedRect = current
        retell()
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
                         completingJump: Bool = false, fillingVisible: Bool = false) {
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
        if override == nil, jumpViewport != nil {
            if watching.map({ swiftomniui_winui_scroller_jump_pending($0.scroller.handle) }) == true {
                return
            }
            jumpViewport = nil
            jumpRetained.removeAll(keepingCapacity: true)
        }
        guard var target = override ?? preparedViewport ?? jumpViewport ?? announcedRect ?? viewport else { return }
        if let identity = readerTarget, let place = cells.position(of: identity) {
            let perRun = self is WinUILazyGridView ? max(1, cells.window?.perRun ?? 1) : 1
            let run = place / perRun
            let count = (cells.orderedIdentities.count + perRun - 1) / perRun
            let start = self is WinUILazyGridView
                ? cells.runs.offset(of: run, count: count) : cells.offset(of: place)
            let extent = self is WinUILazyGridView ? cells.runs.extent(of: run) : cells.extents.extent(of: identity)
            let room = axis == .vertical ? target.height : target.width
            let origin = axis == .vertical ? target.y : target.x
            let destination: Double
            if let anchor = readerAnchor {
                destination = start + anchor * (extent - room)
            } else if extent > room || start + extent > origin + room {
                // Match the native reader: an oversized row stays aligned to
                // its trailing edge instead of alternating on every notice.
                destination = start + extent - room
            } else {
                destination = min(origin, start)
            }
            // Prepare the real viewport around the row, not the row's entire
            // height. A tall message must not expand the realization window.
            if axis == .vertical { target.y = max(0, destination) }
            else { target.x = max(0, destination) }
        }
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
        let realize = realizationSpan(in: target)
        // An outer lazy row may itself be a lazy document. Its native panel
        // exists before entering the viewport, but previously its empty visible
        // intersection discarded all look-ahead, leaving that entire row blank
        // until it became visible. Prepare only the predicted intersection,
        // through the same optional frame queue as ordinary ahead work.
        if incoming == nil {
            cells.cancelPrefetch(invalidate: false)
            if realize != nil {
                scheduleOffscreenWindow()
                return
            }
            let start = axis == .vertical ? target.y : target.x
            let room = axis == .vertical ? target.height : target.width
            let approaching = scrollVelocity > 0 ? start + room <= 0
                : scrollVelocity < 0 && start >= allocatedExtent
            if approaching, !cells.built.isEmpty {
                // A slightly slower velocity sample can shrink the prediction
                // just after this incoming panel prepared its first rows. Keep
                // that bounded batch until it enters, motion stops/reverses, or
                // the outer lazy window releases the panel. Otherwise each
                // sample destroys and rebuilds the same expensive Markdown.
                WinUIRenderer.shared?.runtime.lazyPrefetch.cancel(owner: self)
                return
            }
        }
        WinUIRenderer.shared?.runtime.lazyPrefetch.cancel(owner: self)
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
                           prefetch: true, demand: incoming)
                return
            }
        }
        var needsArrangement = false
        fillingWindow = completingJump || fillingVisible
        defer {
            fillingWindow = false
            expansionRuns = 1
            if pendingContentExtent {
                pendingContentExtent = false
                commitChangedContentExtent()
            }
            // XAML must measure the changed extent before placing the new rows.
            if needsArrangement { invalidateArrange() }
        }
        var measuredWindows: Set<Range<Int>> = []
        while true {
            let built = cells.built
            if fillingWindow, let incoming, cells.requestedItemsAreCurrent, !needsRowMeasurements,
               !built.isEmpty {
                let perRun = cells.window?.perRun ?? 1
                let count = (cells.orderedIdentities.count + perRun - 1) / perRun
                let first = built.lowerBound / perRun, last = (built.upperBound - 1) / perRun
                var known = 0
                for run in first...last {
                    let measured = grid ? cells.runs.hasMeasurement(for: run)
                        : cells.extents.hasMeasurement(for: cells.orderedIdentities[run])
                    if measured { known += 1 }
                }
                let head = grid ? cells.runs.offset(of: first, count: count) : cells.offset(of: first)
                let tail = grid ? cells.runs.offset(of: last + 1, count: count) : cells.offset(of: last + 1)
                let missingBefore = max(0, head - incoming.lowerBound)
                let missingAfter = max(0, incoming.upperBound - tail)
                let remaining = missingBefore + missingAfter
                let observed = cells.measuredRunExtent(perRun: perRun, grid: grid,
                                                       forward: missingAfter >= missingBefore)
                // Start with one measured run, then grow only as far as both
                // nearby measured density and the still-unfilled viewport justify.
                // This avoids one render/patch per tiny file row without
                // constructing a provisional screenful of tall unknown cards.
                expansionRuns = max(1, min(known, Int((remaining / observed).rounded(.up))))
            }
            tellWindow(span ?? 0..<0, realize: realize ?? 0..<0, demand: incoming)
            // The coalesced turn completes visible demand before the next
            // composition. Optional ahead work never enters this loop. Native
            // callbacks only enqueue the turn, so scroll input can return first.
            if !completingJump && !fillingVisible { return }
            // Complete only this viewport. Shorter-than-estimated rows can expose
            // further rows; those are visible work, not next-frame prefetch.
            guard WinUIView.arranging == 0, WinUIView.measuring == 0,
                  cells.element?.handler(.realizedChanged) == nil || cells.requestedItemsAreCurrent,
                  placed != nil else { return }
            if cells.built != built || measuredRevision != measurementRevision
                || needsRowMeasurements || cells.anchorShift != 0 {
                let actual = laidOutFrame
                // Query geometry while filling. Preparing every nested native
                // allocation here and again in XAML Measure repeats the whole
                // incoming subtree's work. The normal native pass prepares the
                // completed visible window once before Arrange.
                prepareLayoutContent(in: Rect(0, 0, actual.width, actual.height), measuringNative: completingJump)
                needsArrangement = true
            }
            let after = grid ? cells.runs.revision : cells.extents.revision
            guard cells.needsMeasurement || needsRowMeasurements || cells.window?.revision != after else {
                // Filling demand cancels the old optional job. Resume the new
                // predicted window now, before this frame drains prefetch;
                // waiting for another Arrange lets a fling outrun every batch.
                if cells.window?.realize != (realize ?? 0..<0),
                   hasMountedWindow(in: incoming ?? 0..<0) {
                    tellWindow(span ?? 0..<0, realize: realize ?? 0..<0, demand: incoming)
                }
                return
            }
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

    /// Predict the physical coverage first, then remove exactly the run which
    /// LazyCells' normal neighbour will add back to the request.
    func realizationSpan(in rect: Rect) -> Range<Double>? {
        let span = windowSpan(in: rect)
        guard scrollVelocity != 0 else { return span }
        let grid = self is WinUILazyGridView
        let perRun = cells.window?.perRun ?? 1
        let runCount = (cells.orderedIdentities.count + perRun - 1) / perRun
        // Preparation already includes time spent waiting on UI work. Adding
        // the same blocked observation interval again creates positive feedback:
        // a slow batch widens the next batch, which blocks the following one.
        let leadInterval = displayInterval
        let readiness = preparationDuration > 0 ? preparationDuration : (watching?.preparationTime(on: axis) ?? 0)
        // Rendered completes XAML's work, not presentation on the monitor.
        // Its surface can wait until the next refresh while native scrolling
        // continues. Include that display period separately from the next
        // observation period; neither is a fixed millisecond work budget.
        let extra = WinUILazyPrefetch.distance(velocity: scrollVelocity, interval: leadInterval,
                                              readiness: readiness + displayInterval, neighbour: 0,
                                              observationLead: scrollObservationLead, acceleration: scrollAcceleration)
        var expanded = rect
        if axis == .vertical {
            expanded.y += min(0, extra)
            expanded.height += abs(extra)
        } else {
            expanded.x += min(0, extra)
            expanded.width += abs(extra)
        }
        guard let predicted = windowSpan(in: expanded) else { return nil }
        guard let span else { return predicted }
        let runs = grid ? cells.runs.places(in: predicted, overscan: 0, count: runCount)
            : cells.places(in: predicted, overscan: 0)
        guard !runs.isEmpty else { return span }
        func offset(_ run: Int) -> Double {
            grid ? cells.runs.offset(of: run, count: runCount) : cells.offset(of: run)
        }
        let firstBuilt = cells.built.lowerBound / perRun
        let afterBuilt = (cells.built.upperBound + perRun - 1) / perRun
        let overlapsBuilt = !cells.built.isEmpty && offset(firstBuilt) < span.upperBound
            && offset(afterBuilt) > span.lowerBound
        // Subtracting the current neighbour's distance before rounding to rows
        // can lose part of a run. The neighbour at the *predicted* edge may
        // also have a completely different height (for example a Markdown table).
        // A shorter prediction must not destroy already prepared incoming rows
        // only to rebuild them on the next speed sample. Keep that existing
        // edge during continuous motion, without allocating any extra rows.
        // The trailing edge, direction reversal, idle, and disjoint jumps still
        // retire their obsolete rows normally.
        if scrollVelocity > 0 {
            let last = max(runs.upperBound - 1, overlapsBuilt ? afterBuilt - 1 : 0)
            let start = offset(last)
            return span.lowerBound..<max(span.upperBound, start)
        }
        let first = min(runs.lowerBound, overlapsBuilt ? firstBuilt : runCount)
        let afterFirst = offset(first + 1)
        return min(span.lowerBound, afterFirst)..<span.upperBound
    }

    private func scheduleOffscreenWindow() {
        WinUIRenderer.shared?.runtime.lazyPrefetch.schedule(owner: self, ready: { [weak self] in
            guard let self, !self.isDetached, self.placed != nil,
                  !self.cells.animatesChanges,
                  self.cells.built.isEmpty || self.cells.requestedItemsAreCurrent,
                  WinUIView.arranging == 0, WinUIView.measuring == 0 else { return false }
            // A never-requested panel has no acknowledgement to wait for.
            // Once a row is requested, its render and native placement gate
            // subsequent work just like an ordinary prefetch batch.
            return self.cells.built.isEmpty || (!self.needsRowMeasurements && !self.hasUnplacedRows())
        }) { [weak self] in
            guard let self, self.scrollVelocity != 0,
                  let rect = self.currentNativeViewport(), self.windowSpan(in: rect) == nil,
                  let target = self.realizationSpan(in: rect) else { return false }
            let grid = self is WinUILazyGridView
            self.cells.show(0..<0, perRun: self.cells.window?.perRun ?? 1,
                            grid: grid, realize: target, measureBeforeExpanding: true,
                            unknownRuns: 1)
            return self.cells.needsMeasurement
        }
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
                || self.cells.needsWindowUpdate || self.cells.window?.span != (self.span ?? 0..<0)
                || self.cells.window?.realize != (self.realizationSpan(in: rect) ?? 0..<0)
                || self.cells.window?.revision != revision
                || self.measuredRevision != self.measurementRevision || self.needsRowMeasurements
                || self.cells.retained != self.travellingIdentities {
                if let viewport = self.viewport { self.viewportChanged(viewport, effective: false, fillingVisible: true) }
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
        jumpViewport = nil
        jumpRetained.removeAll()
        scrollVelocity = 0
        scrollAcceleration = 0
        scrollInterval = 0
        scrollObservationLead = 0
        isWaitingForViewport = false
        scrollEar = nil
        if let scroll {
            let motion = scroll.lazyMotion(on: axis)
            scrollVelocity = scroll.held ? motion.velocity : 0
            scrollAcceleration = scroll.held ? motion.acceleration : 0
            scrollInterval = motion.interval
            let ear = WinUIScrollEar(owner: self) { [weak self] in self?.scrollerMoved() }
            ear.frame = { [weak self] in self?.scrollerMoved(onFrame: true) }
            ear.announce = { [weak self] target in self?.prepareFor(target) }
            scroll.scroller.ears.append(ear)
            scrollEar = ear
        }
    }

    /// Retain the larger of adjacent samples so a cheap batch cannot immediately
    /// discard the preparation latency measured by the preceding batch.
    private func recordPreparationDuration(_ duration: Double, identities: Set<String>) {
        latestPreparationDuration = max(duration, previousPreparationDuration)
        previousPreparationDuration = duration
        // Two cheap paragraph batches must not erase the cost of a table still
        // in this window. The indexed maximum follows mounted rows only; it
        // neither scans all rows per frame nor keeps a historic worst case.
        for identity in identities where mounted[identity] != nil {
            preparedRowCosts[identity] = duration
        }
        watching?.recordLazyPreparation(duration, on: axis)
    }

    private func observeScroll() {
        guard let scroll = watching, scroll.held else { return }
        let sample = scroll.lazyMotion(on: axis)
        scrollVelocity = sample.velocity
        scrollAcceleration = sample.acceleration
        scrollInterval = sample.interval
    }

    private func scrollerMoved(onFrame: Bool = false) {
        if watching?.held != true {
            // An idle pause is not rendering latency for the next gesture.
            preparationStarted = nil
            preparingIdentities.removeAll(keepingCapacity: true)
            arrangedPreparation = nil
        } else if onFrame, let prepared = arrangedPreparation,
           swiftomniui_winui_last_rendered_time() > prepared.rendered {
            // Rendering announces an upcoming frame and can fire more than
            // once per refresh. Only Rendered confirms that XAML completed a
            // frame after these rows received their native arrangement.
            recordPreparationDuration(swiftomniui_winui_last_rendered_time() - prepared.started,
                                      identities: prepared.identities)
            arrangedPreparation = nil
        }
        guard let rect = currentNativeViewport() else { return }
        if let scroll = watching {
            if !scroll.held {
                scrollVelocity = 0
                scrollAcceleration = 0
                scrollObservationLead = 0
            } else if onFrame {
                observeScroll()
                scrollObservationLead = scroll.observationLead(on: axis)
            } else {
                observeScroll()
            }
        }
        // Replenish one physical frame's travel. A missed callback or a slow
        // row changes the lead time, not permission to burst-build all of the
        // distance consumed while that work blocked the dispatcher.
        cells.prefetchStepDistance = abs(scrollVelocity) * displayInterval
        // A native scroll notification records position only. Coalesce row
        // realization outside the ScrollPresenter's callback/layout stack.
        announcedRect = rect
        if let target = pendingScrollTarget {
            pendingScrollTarget = nil
            prepareFor(target)
        }
        retell()
    }

    private func hasUnplacedRows(in range: Range<Int>? = nil) -> Bool {
        for number in pendingAnchors {
            guard let identity = identitiesByView[number], let item = mounted[identity],
                  item.isShown, !item.departing else { continue }
            if let range {
                guard let position = cells.position(of: identity), range.contains(position) else { continue }
            }
            return true
        }
        return false
    }

    func hasMountedWindow(in span: Range<Double>) -> Bool {
        guard cells.requestedItemsAreCurrent, let window = cells.window else { return false }
        let perRun = window.perRun
        let wanted = self is WinUILazyGridView
            ? cells.runs.places(in: span, overscan: 0,
                                count: (cells.orderedIdentities.count + perRun - 1) / perRun)
            : cells.places(in: span, overscan: 0)
        guard !wanted.isEmpty else { return false }
        let lower = wanted.lowerBound * perRun
        let upper = min(cells.orderedIdentities.count, wanted.upperBound * perRun)
        guard cells.built.lowerBound <= lower, cells.built.upperBound >= upper else { return false }
        // Querying row geometry does not mean that XAML has arranged the
        // incoming native subtree. Do not cancel/follow up a batch while its
        // demanded rows still have no first native placement.
        guard !hasUnplacedRows(in: lower..<upper) else { return false }
        if !needsRowMeasurements, !cells.needsMeasurement { return true }
        // Readiness belongs to the demanded viewport. An incoming offscreen
        // batch can still need measurement without making the visible rows
        // unready; otherwise the next viewport pass cancels that batch and
        // removes it before XAML ever measures or paints it.
        for place in lower..<upper {
            let identity = cells.orderedIdentities[place]
            guard let item = mounted[identity] else {
                guard measuredEmptyGeneration == cells.element?.lazyRequestGeneration else { return false }
                continue
            }
            guard measured[identity] != nil,
                  measuredRevisions[identity] == item.view.measurementRevision,
                  measuredContexts[identity] == item.view.layoutContextRevision else { return false }
        }
        return true
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
        // Use actual placed frames, not estimated source offsets: learning a
        // short destination row can already have shifted the extent index.
        let leading = axis == .vertical ? rect.y : rect.x
        let trailing = leading + (axis == .vertical ? rect.height : rect.width)
        jumpRetained = Set(mounted.compactMap { identity, item in
            guard item.isShown, !item.departing, let frame = item.view.placed else { return nil }
            let start = axis == .vertical ? frame.y : frame.x
            let end = start + (axis == .vertical ? frame.height : frame.width)
            return start < trailing && end > leading ? identity : nil
        })
        let standing = scroll.scroller.standing.offset
        if axis == .vertical { rect.y += target.y - standing.y }
        else { rect.x += target.x - standing.x }
        jumpViewport = rect
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
                     // The scroll-axis extent changes when rows grow, arrive or
                     // leave. It is a result of the edit, not an external resize;
                     // treating it as one suppresses every surviving row's
                     // displacement animation. Only the cross-axis proposal
                     // determines whether the layout was resized.
                     consumingPatch: ready,
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
        if let started = preparationStarted, cells.requestedItemsAreCurrent,
           !needsRowMeasurements, !hasUnplacedRows() {
            if var prepared = arrangedPreparation {
                prepared.started = min(prepared.started, started)
                prepared.rendered = swiftomniui_winui_last_rendered_time()
                prepared.identities.formUnion(preparingIdentities)
                arrangedPreparation = prepared
            } else {
                arrangedPreparation = (started, swiftomniui_winui_last_rendered_time(), preparingIdentities)
            }
            preparingIdentities.removeAll(keepingCapacity: true)
            preparationStarted = nil
        }
    }

    override func detach() {
        WinUIRenderer.shared?.runtime.lazyPrefetch.cancel(owner: self)
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
        preparationStarted = nil
        arrangedPreparation = nil
        preparingIdentities.removeAll()
        preparedRowCosts = WinUILazyCrossExtents()
        super.detach()
        swiftomniui_winui_panel_watch_viewport(handle, false)
        effectiveViewport = nil
        lastTargetViewport = nil
        announcedRect = nil
        preparedViewport = nil
        pendingScrollTarget = nil
        jumpViewport = nil
        jumpRetained.removeAll()
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
        let prefetch = hasMountedWindow(in: demand ?? span)
        cells.show(span, realize: prefetch ? realize : (demand ?? span), measureBeforeExpanding: !prefetch,
                   keeping: travellingIdentities, prefetch: prefetch, demand: demand, unknownRuns: expansionRuns,
                   retaining: realize)
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
        let prefetch = hasMountedWindow(in: demand ?? span)
        cells.show(span, perRun: perRun, grid: true, realize: prefetch ? realize : (demand ?? span),
                   measureBeforeExpanding: !prefetch, keeping: travellingIdentities,
                   prefetch: prefetch, demand: demand, unknownRuns: expansionRuns, retaining: realize)
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
