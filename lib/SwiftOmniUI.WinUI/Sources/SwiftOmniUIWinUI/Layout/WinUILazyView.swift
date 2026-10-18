// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

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
    var measuredRevision = -1
    var measuredAcross: Double?
    var naturalAcross = 44.0
    /// The across size of every row measured in the room `measuredAcross` names: the
    /// widest row the document was told about, and not the widest row now mounted.
    var acrossWidest: [String: Double] = [:]
    var geometryChanged = false
    var measuredExtent = 0.0

    /// A window change under way asks the run again once, not per notice.
    private var retellQueued = false
    /// How many passes an arrival has stood waiting for its own rows' measurements: the
    /// change's arrangement, and with it the change's law and retention, is not held
    /// past a bound (`canArrangeRows`).
    private var arrivalHeld = 0
    /// WinUI's effective viewport is the compositor's window in this panel's coordinates.
    private var effectiveViewport: Rect?
    private var lastTargetViewport: Rect?

    /// The viewport the scroller's own notices last named - newer than the
    /// effective viewport while a move stands between them.
    private var announcedRect: Rect?
    /// A program jump deferred by native layout still owes its requested window.
    private var preparedViewport: Rect?
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
        let sourceID = cells.element?.lazyRows.map(ObjectIdentifier.init)
        let sourceChanged = !hasMountedSource || mountedSourceID != sourceID
        mountedSourceID = sourceID
        hasMountedSource = true
        // A content revision can be only a drawing change. The row's own measurement
        // revision is the layout signal; an unchanged revision needs no native pass.
        // Structural changes still need a pass to place their new window.
        let rowSizeChanged = contentChanged && mounted.contains { identity, item in
            measured[identity] == nil
                || measuredRevisions[identity] != item.view.measurementRevision
        }
        if sourceChanged || rowSizeChanged {
            invalidateMeasure()
            invalidateArrange()
        }
        if sourceChanged {
            // A width kept for a row the run no longer shows would widen the document for
            // good; a row the run shows anew is measured in this pass.
            acrossWidest = [:]
            arrivalHeld = 0
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
                swiftomniui_winui_scroller_anchor(previous.view.presentationHandle, false)
            }
            if now[identity]?.view !== previous.view || now[identity]?.values != previous.values {
                measured.removeValue(forKey: identity)
                measuredRevisions.removeValue(forKey: identity)
            }
        }
        if !cells.inserting.isDisjoint(with: now.keys) { cells.animatesChanges = true }
        for item in items {
            if cells.inserting.contains(item.identity),
               item.item.element?.transition?.insertion.blur != nil {
                item.item.view.prepareBlur()
            }
            item.item.view.placingLayout = self
            if mounted[item.identity]?.view !== item.item.view
                || mounted[item.identity]?.departing != item.item.departing {
                swiftomniui_winui_scroller_anchor(item.item.view.presentationHandle, !item.item.departing)
            }
        }
        mounted = now
        refreshContent(contentChanged: contentChanged)
        setChildren(items.map(\.item.view))
        // Recycling and row patches only change this panel's arrangement.
        // The document is invalidated when measured content extent actually
        // changes, never for a paint-only update or an overscan row swap.
        forgetMeasurements()
        invalidateMeasure()
        invalidateArrange()
        if sourceChanged, cells.total != measuredExtent { commitChangedContentExtent() }
        measuredRevision = measurementRevision
    }

    func commitChangedContentExtent() {
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

    /// EffectiveViewportChanged runs after native Arrange. Request its rows now
    /// so their layout invalidation participates in this XAML layout cycle,
    /// rather than waiting for another dispatcher turn after the frame commits.
    /// `override` is the freshest window a scroller's own notice can name - where its
    /// pending move already stands - while `rect` is the effective viewport reported.
    func viewportChanged(_ rect: Rect, effective: Bool = true, target override: Rect? = nil,
                         bring: Point = .zero) {
        guard clip != nil else { return }
        // WinUI names "no viewport at all" with (+Inf, +Inf, -Inf, -Inf) while a
        // view stands outside every viewport - a swap under way, a run not yet
        // placed. No window stands in such a rect: the notice is no news, and
        // the last real viewport stands.
        guard rect.x.isFinite, rect.y.isFinite, rect.width.isFinite, rect.height.isFinite,
              rect.width > 0, rect.height > 0 else { return }
        watchClip()
        if let override { preparedViewport = override }
        if effective {
            effectiveViewport = rect
            if announcedRect != nil, let scroll = watching {
                // A late notice must not restore an old offset. Read the native
                // position now, also picking up a descendant moved by layout.
                var raw = [Double](repeating: 0, count: 6)
                swiftomniui_winui_scroller_viewport(scroll.scroller.handle, handle, &raw)
                announcedRect = Rect(raw[0], raw[1], rect.width, rect.height)
            }
        }
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
        guard cells.orderedIdentities.isEmpty || incoming != nil else { return }
        let span = self.span ?? incoming
        let realize = incoming
        guard lastTargetViewport != target || cells.window?.span != (span ?? 0..<0)
            || cells.window?.realize != (realize ?? 0..<0)
            || cells.window?.revision != revision || cells.needsWindowUpdate
            || measuredRevision != measurementRevision || geometryChanged
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
        if !cells.needsMeasurement, !geometryChanged, !cells.animatesChanges,
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
        let built = cells.built
        tellWindow(span ?? 0..<0, realize: realize ?? 0..<0, demand: incoming)
        // One request and, if its own patch has landed, one measurement pass.
        // Further extent corrections continue on the next layout turn rather
        // than monopolizing the UI thread inside this viewport callback.
        guard WinUIView.arranging == 0, WinUIView.measuring == 0,
              cells.element?.handler(.realizedChanged) == nil || cells.requestedItemsAreCurrent,
              let placed else { return }
        if cells.built != built || measuredRevision != measurementRevision || cells.anchorShift != 0 {
            _ = contentSize(width: standsAt ?? placed.width)
            needsArrangement = true
        }
        let after = grid ? cells.runs.revision : cells.extents.revision
        if cells.needsMeasurement || cells.window?.revision != after { retell() }
    }

    /// The window `rect` shows of the run, clipped to its document extent.
    private func windowSpan(in rect: Rect) -> Range<Double>? {
        guard !cells.orderedIdentities.isEmpty else { return nil }
        let start = axis == .vertical ? rect.y : rect.x
        let room = axis == .vertical ? rect.height : rect.width
        let own = axis == .vertical
            ? (placed?.height ?? laidOutFrame.height) : (placed?.width ?? laidOutFrame.width)
        // A move announced past either end lands where the scroller clamps it:
        // the far end's window, not no window - or every mounted row falls away
        // until the effective viewport reports the clamp.
        let origin = min(max(0, start), max(0, own - room))
        // XAML's window jitters by a float's worth between notices; snapped to
        // a sixty-fourth, one place stands either in or out of it, not both.
        let grain = 1.0 / 64.0
        let low = (origin / grain).rounded() * grain
        let high = (min(own, origin + room) / grain).rounded() * grain
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
            if self.isAttached, let scroll = self.watching {
                var raw = [Double](repeating: 0, count: 6)
                swiftomniui_winui_scroller_viewport(scroll.scroller.handle, self.handle, &raw)
                // A newly attached ScrollViewer can report a zero effective
                // viewport before its presenter runs. Its own allocated room
                // is already known; realize that first window without waiting
                // for a resize or a second native viewport event.
                let nativeRoom = scroll.scroller.laidOutFrame
                let rect = Rect(raw[0], raw[1], raw[2] > 0 ? raw[2] : nativeRoom.width,
                                raw[3] > 0 ? raw[3] : nativeRoom.height)
                if rect.width > 0, rect.height > 0,
                   rect.x.isFinite, rect.y.isFinite, rect.width.isFinite, rect.height.isFinite {
                    self.announcedRect = rect
                }
            }
            let revision = self is WinUILazyGridView ? self.cells.runs.revision : self.cells.extents.revision
            if self.preparedViewport != nil || self.lastTargetViewport != self.viewport || self.cells.window == nil
                || self.cells.needsMeasurement || self.cells.window?.span != (self.span ?? 0..<0)
                || self.cells.window?.revision != revision
                || self.measuredRevision != self.measurementRevision
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
        cells.correctedOrigin(perRun: perRun, grid: grid)
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
        guard let scroll = watching else { return }
        var raw = [Double](repeating: 0, count: 6)
        swiftomniui_winui_scroller_viewport(scroll.scroller.handle, handle, &raw)
        var rect = Rect(x: raw[0], y: raw[1], width: raw[2], height: raw[3])
        // Preserve precise viewport dimensions without changing its native origin.
        rect.width = effectiveViewport?.width ?? raw[2]
        rect.height = effectiveViewport?.height ?? raw[3]
        // A native scroll notification records position only. Coalesce row
        // realization outside the ScrollPresenter's callback/layout stack.
        if rect.width > 0, rect.height > 0,
           rect.x.isFinite, rect.y.isFinite, rect.width.isFinite, rect.height.isFinite {
            announcedRect = rect
            retell()
        } else { retell() }
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
        var raw = [Double](repeating: 0, count: 6)
        swiftomniui_winui_scroller_viewport(scroll.scroller.handle, handle, &raw)
        var rect = Rect(x: raw[0], y: raw[1], width: effectiveViewport?.width ?? raw[2],
                        height: effectiveViewport?.height ?? raw[3])
        let standing = scroll.scroller.standing.offset
        if axis == .vertical { rect.y += target.y - standing.y }
        else { rect.x += target.x - standing.x }
        viewportChanged(rect, effective: false, target: rect)
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
        }
        guard !waiting else {
            // The rows of a change are measured in the pass before its arrangement. A row
            // whose own measure never lands - a view that left the room of a native pass, a
            // row kept alive by a window of its own - must not hold the change's
            // arrangement, and with it the change's law and the retention it stands, for
            // good: past the bound its place is the one the arithmetic holds for it.
            guard arrivalHeld < 2 else {
                arrivalHeld = 0
                return true
            }
            arrivalHeld += 1
            retell()
            return false
        }
        arrivalHeld = 0
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
                                         axis == .vertical ? cells.anchorShift : 0), refining: true)
        if ready { cells.animatesChanges = false }
        cells.anchorShift = 0
        retell()
    }

    /// Measuring again, the window is re-asked: a new pass is a new chance
    /// for the places the run holds.
    override func measure(width: Double, height: Double) -> LayoutSize {
        retell()
        return super.measure(width: width, height: height)
    }

    override func detach() {
        cells.cancelPrefetch()
        super.detach()
        swiftomniui_winui_panel_watch_viewport(handle, false)
        effectiveViewport = nil
        lastTargetViewport = nil
        announcedRect = nil
        preparedViewport = nil
        watching = nil
        scrollEar = nil
        arrivalHeld = 0
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

    /// The current finite proposal determines row wrapping. A previous
    /// allocation is only a fallback for an unspecified proposal, never a
    /// replacement for the new width during initialization or resize.
    override func contentSize(width: Double?) -> LayoutSize {
        let width = width.flatMap { $0.isFinite ? Double(Float($0)) : nil }
        let across = axis == .vertical
            ? (width ?? standsAt).map { max(0, Double(Float($0)) - padding.left - padding.right) } : nil
        if WinUIView.arranging == 0, WinUILayoutView.queryingSize == 0 {
            let revision = cells.extents.revision
            if measuredAcross != across {
                cells.extents.reset()
                // Row measurements stand across a room change: each carries the proposal it
                // was measured at, and the loop below measures again exactly the rows whose
                // proposal differs. Dropping them all charged one native measure per mounted
                // row every time the query flipped - a finite proposal beside the last
                // allocation is the same room twice - and charged it again on every scroll
                // back over a row the window had left. A width measured in another room is
                // no width of this one.
                acrossWidest = [:]
                measuredAcross = across
            }
            if cells.requestedItemsAreCurrent {
                // An empty builder fragment produces no native child at all.
                // Once its render is committed, it is a measured zero, not a
                // permanently unmeasured row that blocks incremental filling.
                for identity in cells.orderedIdentities[cells.built] where mounted[identity] == nil {
                    cells.extents.measure(identity, extent: 0)
                }
            }
            for (identity, item) in mounted {
                guard !item.departing, cells.position(of: identity) != nil else { continue }
                let margin = item.values.margin
                let proposal = across.map { Double(Float(max(0, $0 - margin.left - margin.right))) }
                let size: LayoutSize
                if let kept = measured[identity], kept.proposal == proposal,
                   measuredRevisions[identity] == item.view.measurementRevision {
                    size = kept.size
                } else {
                    let startedAt = WinUIView.provisionalMeasureRevision
                    size = item.size(offered: proposal)
                    cells.measurements += 1
                    guard startedAt == WinUIView.provisionalMeasureRevision else { continue }
                    measured[identity] = (proposal, size)
                    measuredRevisions[identity] = item.view.measurementRevision
                }
                let acrossSize = axis == .vertical
                    ? size.width + margin.left + margin.right : size.height + margin.top + margin.bottom
                let extent = axis == .vertical
                    ? size.height + margin.top + margin.bottom
                    : size.width + margin.left + margin.right
                cells.extents.measure(identity, extent: extent)
                acrossWidest[identity] = acrossSize
            }
            // A finite proposal fixes a vertical stack's returned width. Scanning every
            // row ever measured in this room cannot affect that answer. An intrinsic
            // cross-axis size still uses the widest measured row, including rows that
            // have scrolled out, so the document does not narrow while scrolling.
            if axis != .vertical || width == nil {
                let natural = acrossWidest.values.max() ?? (cells.orderedIdentities.isEmpty ? 0 : 44)
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
                if total != measuredExtent { commitChangedContentExtent() }
            }
            measuredExtent = total
            measuredRevision = measurementRevision
        }
        let total = cells.total
        return axis == .vertical
            ? LayoutSize(width: width ?? naturalAcross + padding.left + padding.right, height: total)
            : LayoutSize(width: total, height: naturalAcross + padding.top + padding.bottom)
    }

    /// Place only measurements completed before this arrangement. Native subtrees are never measured here.
    override func arrange(in bounds: Rect) {
        let across = max(0, axis == .vertical
            ? bounds.width - padding.left - padding.right
            : bounds.height - padding.top - padding.bottom)
        super.arrange(in: bounds)
        for (identity, item) in mounted {
            let margin = item.values.margin
            guard let place = cells.position(of: identity) else { continue }
            // A row mounted in this pass is measured in it, and one mounted after it in the
            // next. Placing only what is measured leaves the frame a heavy row stands in with
            // a hole where it takes longest, which is the document showing through a scroll.
            // Its place is known - the arithmetic holds 44 for every place it has not
            // measured - so it stands at its own last width and the estimate, and the
            // measurement corrects it on the pass that follows.
            let size = measured[identity]?.size
            let extent = cells.extents.extent(of: identity)
            let run = cells.offset(of: place)
            let frame: Rect
            if axis == .vertical {
                let open = across - margin.left - margin.right
                let expands = item.values.expandingAxes == .horizontal || item.values.expandingAxes == .both
                let width = Extent.of(
                    option: expands ? 3 : item.values.horizontal, stated: item.values.width,
                    natural: size?.width
                        ?? acrossWidest[identity].map { $0 - margin.left - margin.right } ?? open,
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
                    natural: size?.height
                        ?? acrossWidest[identity].map { $0 - margin.top - margin.bottom } ?? open,
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
            var placed = item
            if cells.animatesChanges || cells.inserting.remove(identity) == nil { placed.fadeIn = nil }
            self.place(placed, at: direction.places(frame, in: bounds))
        }
    }

    override func tellWindow(_ span: Range<Double>, realize: Range<Double>, demand: Range<Double>?) {
        cells.show(span, realize: realize, keeping: travellingIdentities, prefetch: false, demand: demand)
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

    /// Tracks and row heights use the current finite proposal. A previous
    /// allocation only answers when the parent left that proposal unspecified.
    override func contentSize(width: Double?) -> LayoutSize {
        let width = width.flatMap { $0.isFinite ? Double(Float($0)) : nil }
        let room = max(0, axis == .vertical
            ? ((width ?? standsAt).map { Double(Float($0)) - padding.left - padding.right } ?? acrossRoom)
            : acrossRoom)
        let proposed = LazyGridTracks.resolve(tracks, width: room, spacing: trackSpacing)
        let widths = LazyGridTracks.extents(proposed, width: room, spacing: trackSpacing)
        if WinUIView.arranging == 0, WinUILayoutView.queryingSize == 0 {
            let revision = cells.runs.revision
            if widths != columns {
                columns = widths
                // Each row is measured at its own track's width, which the proposal names: a
                // row whose track kept its width keeps its measurement, so a track count or a
                // width that returns to a former one costs no native measure.
                cells.runs.reset()
                geometryChanged = true
            }
            var runExtents: [Int: Double] = [:]
            var pendingRuns: Set<Int> = []
            if cells.requestedItemsAreCurrent, !widths.isEmpty {
                for identity in cells.orderedIdentities[cells.built] where mounted[identity] == nil {
                    if let place = cells.position(of: identity) { runExtents[place / widths.count] = 0 }
                }
            }
            for (identity, item) in mounted {
                guard !item.departing, let place = cells.position(of: identity), !widths.isEmpty else { continue }
                let run = place / widths.count, track = place % widths.count
                let margin = item.values.margin
                let proposal: Double? = axis == .vertical
                    ? Double(Float(max(0, widths[track] - margin.left - margin.right))) : nil
                let size: LayoutSize
                if let kept = measured[identity], kept.proposal == proposal,
                   measuredRevisions[identity] == item.view.measurementRevision {
                    size = kept.size
                } else {
                    let startedAt = WinUIView.provisionalMeasureRevision
                    size = item.size(offered: proposal)
                    cells.measurements += 1
                    guard startedAt == WinUIView.provisionalMeasureRevision else {
                        pendingRuns.insert(run)
                        continue
                    }
                    measured[identity] = (proposal, size)
                    measuredRevisions[identity] = item.view.measurementRevision
                }
                let extent = axis == .vertical
                    ? size.height + margin.top + margin.bottom
                    : size.width + margin.left + margin.right
                runExtents[run] = max(runExtents[run] ?? 0, extent)
            }
            for (run, extent) in runExtents where !pendingRuns.contains(run) {
                cells.runs.measure(run, extent: extent)
            }
            commitAnchor(perRun: perRun, grid: true)
            let total = cells.runs.total(count: runCount)
            if cells.runs.revision != revision || total != measuredExtent {
                geometryChanged = true
                if total != measuredExtent { commitChangedContentExtent() }
            }
            measuredExtent = total
            measuredRevision = measurementRevision
        }
        let count = (cells.orderedIdentities.count + max(1, proposed.count) - 1) / max(1, proposed.count)
        let total = widths == columns ? cells.runs.total(count: count)
            : cells.runs.padding.head + cells.runs.padding.tail + Double(count) * cells.runs.estimate
                + Double(max(0, count - 1)) * runSpacing
        return axis == .vertical
            ? LayoutSize(width: width ?? 0, height: total)
            : LayoutSize(width: total, height: widths.reduce(0, +)
                + Double(max(widths.count - 1, 0)) * trackSpacing + padding.top + padding.bottom)
    }

    override func arrange(in bounds: Rect) {
        acrossRoom = max(0, axis == .vertical
            ? bounds.width - padding.left - padding.right
            : bounds.height - padding.top - padding.bottom)
        let widths = columns
        guard !widths.isEmpty else { return }
        super.arrange(in: bounds)
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
            guard let size = measured[identity]?.size else { continue }
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
            var placed = item
            if cells.animatesChanges || cells.inserting.remove(identity) == nil { placed.fadeIn = nil }
            self.place(placed, at: direction.places(frame, in: bounds))
        }
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
