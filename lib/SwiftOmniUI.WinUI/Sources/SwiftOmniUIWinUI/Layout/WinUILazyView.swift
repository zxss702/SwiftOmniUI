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
    var geometryChanged = false
    var measuredExtent = 0.0

    /// A window change under way asks the run again once, not per notice.
    private var retellQueued = false
    /// WinUI's effective viewport is the compositor's window in this panel's coordinates.
    private var effectiveViewport: Rect?
    private var lastTargetViewport: Rect?

    /// The window the scroller's own notice last announced it would show;
    /// realized work its view still stands to cross is kept until it arrives.
    private var lastAnnounced: Range<Double>?
    /// The viewport the scroller's own notices last named - newer than the
    /// effective viewport while a move stands between them.
    private var announcedRect: Rect?
    /// The ear the run hears its scroller's moves by, ahead of the effective viewport's notice.
    private var scrollEar: WinUIScrollEar?
    /// A notice realizing rows is under way; one it raises itself is heard
    /// after it, its viewport already taken.
    private var inViewportChange = false
    private var pendingViewport = false

    init(axis: StackArithmetic.Axis, cells: LazyCells) {
        self.axis = axis
        self.cells = cells
        super.init()
        swiftomniui_winui_panel_watch_viewport(handle, true)
    }

    /// The mounted children, held by identity.
    func setItems(_ items: [(identity: String, item: WinUILayoutItem)]) {
        let now = Dictionary(items.map { ($0.0, $0.1) }, uniquingKeysWith: { first, _ in first })
        guard now.keys != mounted.keys || now.contains(where: {
            mounted[$0.key]?.arranges(like: $0.value) != true
        }) else { return }
        for (identity, previous) in mounted {
            if now[identity]?.view !== previous.view {
                swiftomniui_winui_scroller_anchor(previous.view.handle, false)
            }
            if now[identity]?.view !== previous.view || now[identity]?.values != previous.values {
                measured.removeValue(forKey: identity)
                measuredRevisions.removeValue(forKey: identity)
            }
        }
        if !cells.inserting.isDisjoint(with: now.keys) { cells.animatesChanges = true }
        for item in items {
            item.item.view.placingLayout = self
            if mounted[item.identity]?.view !== item.item.view
                || mounted[item.identity]?.departing != item.item.departing {
                swiftomniui_winui_scroller_anchor(item.item.view.handle, !item.item.departing)
            }
        }
        mounted = now
        setChildren(items.map(\.item.view))
        invalidateMeasurements()
        measuredRevision = measurementRevision
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

    /// Only the compositor's effective viewport selects the realized window.
    private var viewport: Rect? {
        effectiveViewport
    }

    /// Native viewport changes realize the required rows before XAML measures and arranges the new window.
    /// `override` is the freshest window a scroller's own notice can name - where its
    /// pending move already stands - while `rect` is the effective viewport reported.
    func viewportChanged(_ rect: Rect, effective: Bool = true, target override: Rect? = nil,
                         bring: Point = .zero) {
        guard clip != nil else { return }
        // WinUI names "no viewport at all" with (+Inf, +Inf, -Inf, -Inf) while a
        // view stands outside every viewport - a swap under way, a run not yet
        // placed. No window stands in such a rect: the notice is no news, and
        // the last real viewport stands.
        guard rect.x.isFinite, rect.y.isFinite, rect.width.isFinite, rect.height.isFinite else { return }
        watchClip()
        if effective {
            effectiveViewport = rect
            // The screen has reached the announced window: the announced rect's
            // coarser read gives way to the effective viewport's exact fractions,
            // or a boundary row flips between their two spellings of one spot.
            if let announced = announcedRect,
               abs(announced.x - rect.x) < 1, abs(announced.y - rect.y) < 1 {
                announcedRect = rect
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
                    guard let self, !self.isDetached, let viewport = self.viewport else { return }
                    self.viewportChanged(viewport, effective: false)
                }
            }
        }
        guard let target = override ?? announcedRect ?? viewport else { return }
        let grid = self is WinUILazyGridView
        let revision = grid ? cells.runs.revision : cells.extents.revision
        // `span` is the window the screen shows. While the user holds the
        // scroller its view sweeps under the compositor's own power toward
        // every window a notice names - the realized window keeps them all
        // until the screen arrives. A move nobody holds snaps to where it
        // lands, so only the window it lands in stands built.
        let span = self.span
        let held = watching?.held == true
        let incoming = windowSpan(in: target)
        var realize = held ? span : incoming
        for window in [incoming, held ? lastAnnounced : nil] {
            guard let window else { continue }
            realize = realize.map {
                min($0.lowerBound, window.lowerBound)..<max($0.upperBound, window.upperBound)
            } ?? window
        }
        // The compositor moves ahead of these notices, held or not: keep a viewport
        // of run past either end mounted, so a move that starts before the next
        // notice - a resumed wheel, a drag's first frames - sweeps into rows already
        // painted. While the scroller is held the window only widens, built a stretch
        // at a time; at rest it follows the viewport, a look-ahead either way.
        if let realized = realize {
            // The look-ahead must stand on the same sixty-fourth grid the
            // window's own bounds snap to, or a float's worth of room lands a
            // boundary row on one side of the window and not the other.
            let raw = axis == .vertical ? rect.height : rect.width
            let room = (raw * 64).rounded() / 64
            if held, let kept = cells.window?.realize, kept.lowerBound <= max(0, realized.lowerBound - room / 2),
               kept.upperBound >= realized.upperBound + room / 2 {
                realize = kept
            } else {
                realize = max(0, realized.lowerBound - room)..<(realized.upperBound + room)
            }
        }
        if override != nil { lastAnnounced = incoming }
        guard lastTargetViewport != target || cells.window?.span != (span ?? 0..<0)
            || cells.window?.realize != (realize ?? 0..<0)
            || cells.window?.revision != revision || cells.needsMeasurement
            || measuredRevision != measurementRevision || geometryChanged
        else { return }
        let previous = lastTargetViewport
        lastTargetViewport = target
        if !cells.needsMeasurement, !geometryChanged, !cells.animatesChanges,
           measuredRevision == measurementRevision, cells.window?.revision == revision,
           (axis == .vertical ? previous?.width == target.width : previous?.height == target.height),
           let span, let realize {
            let perRun = cells.window?.perRun ?? 1
            let wanted = grid
                ? cells.runs.places(in: realize, overscan: 0, count: (cells.identities.count + perRun - 1) / perRun)
                : cells.places(in: realize, overscan: 0)
            let lower = min(cells.identities.count, max(0, wanted.lowerBound - 1) * perRun)
            let upper = min(cells.identities.count, (wanted.upperBound + 1) * perRun)
            if !wanted.isEmpty, (lower..<upper) == cells.built {
                cells.show(span, perRun: perRun, grid: grid, realize: realize)
                return
            }
        }
        invalidateMeasure()
        while true {
            let built = cells.built
            let before = grid ? cells.runs.revision : cells.extents.revision
            tellWindow(span ?? 0..<0, realize: realize ?? 0..<0)
            // Complete native measurement before asking for further unknown
            // rows. Keep 44 as the initial scroll estimate, and replace it with
            // actual extents before it can request a whole page of tall cards.
            guard WinUIView.arranging == 0, WinUIView.measuring == 0,
                  !cells.needsMeasurement || cells.requestedItemsAreCurrent,
                  let placed else {
                retell()
                break
            }
            if cells.built != built || measuredRevision != measurementRevision || cells.anchorShift != 0 {
                prepareMeasure(width: placed.width)
                arrange(width: placed.width, height: placed.height)
            }
            let after = grid ? cells.runs.revision : cells.extents.revision
            guard cells.needsMeasurement || cells.window?.revision != after else { break }
            // A handler deferred by a patch cannot mount this run yet. Its
            // next layout resumes; never spin on rows that are not available.
            guard cells.built != built || after != before else { break }
        }
    }

    /// The window `rect` shows of the run, clipped to its document extent.
    private func windowSpan(in rect: Rect) -> Range<Double>? {
        guard !cells.identities.isEmpty else { return nil }
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
            guard !self.isDetached else { return }
            self.watchClip()
            if self.geometryChanged {
                self.geometryChanged = false
                self.invalidateMeasurements()
                self.measuredRevision = self.measurementRevision
            }
            // No clip to narrow by means all of it stands in view - a lazy
            // container outside any scroller builds every child.
            guard self.watching != nil else {
                self.cells.tellAll()
                return
            }
            let revision = self is WinUILazyGridView ? self.cells.runs.revision : self.cells.extents.revision
            if self.cells.needsMeasurement || self.cells.window?.span != (self.span ?? 0..<0)
                || self.cells.window?.revision != revision
                || self.measuredRevision != self.measurementRevision {
                if let viewport = self.viewport { self.viewportChanged(viewport, effective: false) }
            }
        }
    }

    /// The places standing in `span`, as the kind's runs count them; `realize`
    /// is the window a moving scroller can show before the next notice.
    func tellWindow(_ span: Range<Double>, realize: Range<Double>) {}

    /// Only the proposal selected for native preparation measures a mounted row.
    /// Ideal-size queries must not prepare the row at a second, speculative width.
    func preparedSize(of item: WinUILayoutItem, offered proposal: Double?) -> LayoutSize {
        let size = item.size(offered: proposal)
        prepare(item, offered: proposal, size: size)
        return item.size(offered: proposal)
    }

    /// Restore native proposals from a kept row without discarding its size.
    func prepare(_ item: WinUILayoutItem, offered proposal: Double?, size: LayoutSize) {
        let expands = item.values.flex != nil
            || item.values.expandingAxes == .horizontal || item.values.expandingAxes == .both
        let width = Extent.of(option: expands ? 3 : item.values.horizontal, stated: item.values.width,
                              natural: size.width, available: proposal ?? size.width,
                              minimum: item.values.minimumWidth, maximum: item.values.maximumWidth)
        prepareChild(item, at: Rect(0, 0, width, size.height))
    }

    /// Adopt the anchor's coordinates when committed measurements change the document.
    /// The ScrollViewer owns the physical scroll adjustment through its native anchor.
    func commitAnchor(perRun: Int = 1, grid: Bool = false) {
        guard let origin = cells.correctedOrigin(perRun: perRun, grid: grid) else { return }
        if axis == .vertical { effectiveViewport?.y = origin }
        else { effectiveViewport?.x = origin }
    }

    /// Recomputes the places when the scroller's window moved.
    private func watchClip() {
        let scroll = clip
        guard scroll !== watching else { return }
        watching = scroll
        effectiveViewport = nil
        lastTargetViewport = nil
        lastAnnounced = nil
        announcedRect = nil
        scrollEar = nil
        if let scroll {
            let ear = WinUIScrollEar(owner: self) { [weak self] in self?.scrollerMoved() }
            ear.announce = { [weak self] target in self?.prepareFor(target) }
            scroll.scroller.ears.append(ear)
            scrollEar = ear
        }
    }

    /// The scroller's view is moving: `nextOffset` says where the change about to
    /// compose stands, ahead of the effective viewport's after-the-fact notice.
    private func scrollerMoved() {
        guard let scroll = watching else { return }
        var raw = [Double](repeating: 0, count: 6)
        swiftomniui_winui_scroller_viewport(scroll.scroller.handle, handle, &raw)
        var rect = Rect(x: raw[0], y: raw[1], width: raw[2], height: raw[3])
        let standing = scroll.scroller.standing.offset
        // The announced target is the change's landing - inertia's predicted final
        // offset when one is named, else the next step: where the view will be,
        // ahead of where it stands, is what an incoming window realizes for.
        let next = scroll.scroller.finalOffset ?? scroll.scroller.nextOffset ?? standing
        // The announced window: the scroller's own read says where the view
        // stands now; the effective viewport lends its size, whose fractions
        // the direct read rounds away, and the notice's next offset moves it.
        rect.width = effectiveViewport?.width ?? raw[2]
        rect.height = effectiveViewport?.height ?? raw[3]
        if axis == .vertical { rect.y += next.y - standing.y } else { rect.x += next.x - standing.x }
        announcedRect = rect
        viewportChanged(rect, effective: effectiveViewport == nil, target: rect)
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
        if axis == .vertical { rect.y = target.y } else { rect.x = target.x }
        announcedRect = rect
        viewportChanged(rect, effective: false, target: rect)
    }

    /// Every pass re-asks the window: a place in the air lands in the one it
    /// asks for, and a move of the scroller's brings one.
    override func arrange(in bounds: Rect) {
        places.begin(width: axis == .vertical ? bounds.width : bounds.height, animating: cells.animatesChanges)
        cells.animatesChanges = false
        if cells.anchorShift != 0 {
            places.layoutMotion?.shift(mounts: mounted.values.map(\.mount),
                                       by: Point(axis == .horizontal ? cells.anchorShift : 0,
                                                 axis == .vertical ? cells.anchorShift : 0))
            cells.anchorShift = 0
        }
        retell()
    }

    /// Measuring again, the window is re-asked: a new pass is a new chance
    /// for the places the run holds.
    override func measure(width: Double, height: Double) -> LayoutSize {
        retell()
        return super.measure(width: width, height: height)
    }

    override func detach() {
        super.detach()
        swiftomniui_winui_panel_watch_viewport(handle, false)
        effectiveViewport = nil
        lastTargetViewport = nil
        lastAnnounced = nil
        announcedRect = nil
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

    /// A selected native proposal commits row wrapping and scroll geometry.
    /// Other arithmetic proposals only read the estimates below.
    override func prepareChildren(width: Double) {
        guard WinUIView.arranging == 0 else { return }
        let width = width.isFinite ? Double(Float(width)) : standsAt
        let across = axis == .vertical
            ? (width ?? standsAt).map { max(0, $0 - padding.left - padding.right) } : nil
        if WinUIView.arranging == 0 {
            let revision = cells.extents.revision
            if measuredAcross != across {
                cells.extents.reset()
                measured = [:]
                measuredRevisions = [:]
                measuredAcross = across
            }
            if cells.requestedItemsAreCurrent {
                // An empty builder fragment produces no native child at all.
                // Once its render is committed, it is a measured zero, not a
                // permanently unmeasured row that blocks incremental filling.
                for identity in cells.identities[cells.built] where mounted[identity] == nil {
                    cells.extents.measure(identity, extent: 0)
                }
            }
            for (identity, item) in mounted {
                guard !item.departing, cells.position(of: identity) != nil else { continue }
                let margin = item.values.margin
                let proposal = across.map { Double(Float(max(0, $0 - margin.left - margin.right))) }
                var size: LayoutSize
                if let kept = measured[identity], kept.proposal == proposal,
                   measuredRevisions[identity] == item.view.measurementRevision {
                    size = kept.size
                    prepare(item, offered: proposal, size: size)
                    if measuredRevisions[identity] != item.view.measurementRevision {
                        size = item.size(offered: proposal)
                        cells.measurements += 1
                        measured[identity] = (proposal, size)
                        measuredRevisions[identity] = item.view.measurementRevision
                    }
                } else {
                    size = preparedSize(of: item, offered: proposal)
                    cells.measurements += 1
                    measured[identity] = (proposal, size)
                    measuredRevisions[identity] = item.view.measurementRevision
                }
                let extent = axis == .vertical
                    ? size.height + margin.top + margin.bottom
                    : size.width + margin.left + margin.right
                cells.extents.measure(identity, extent: extent)
            }
            let natural = mounted.compactMap { identity, item -> Double? in
                guard !item.departing, let size = measured[identity]?.size else { return nil }
                let margin = item.values.margin
                return axis == .vertical
                    ? size.width + margin.left + margin.right : size.height + margin.top + margin.bottom
            }.max() ?? (cells.identities.isEmpty ? 0 : 44)
            let changedAcross = naturalAcross != natural
            if changedAcross { geometryChanged = true }
            naturalAcross = natural
            commitAnchor()
            if changedAcross || cells.extents.revision != revision || cells.total != measuredExtent {
                geometryChanged = true
                forgetMeasurements()
            }
            measuredExtent = cells.total
            measuredRevision = measurementRevision
        }
    }

    /// A lazy run answers alternative proposals from its current document
    /// estimates. It neither mounts more rows nor replaces committed extents.
    override func contentSize(width: Double?) -> LayoutSize {
        let width = width.flatMap { $0.isFinite ? Double(Float($0)) : nil }
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
            guard let place = cells.position(of: identity), let size = measured[identity]?.size else { continue }
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
            var placed = item
            if cells.inserting.remove(identity) == nil { placed.fadeIn = nil }
            self.place(placed, at: direction.places(frame, in: bounds))
        }
    }

    override func tellWindow(_ span: Range<Double>, realize: Range<Double>) {
        cells.show(span, realize: realize,
                   measureBeforeExpanding: cells.element?.handler(.realizedChanged) != nil)
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
    private var runCount: Int { (cells.identities.count + perRun - 1) / perRun }

    /// Only the selected native width commits tracks, row heights and anchors.
    override func prepareChildren(width: Double) {
        guard WinUIView.arranging == 0 else { return }
        let width = width.isFinite ? Double(Float(width)) : standsAt
        let room = max(0, axis == .vertical
            ? ((width ?? standsAt).map { $0 - padding.left - padding.right } ?? acrossRoom)
            : acrossRoom)
        let proposed = LazyGridTracks.resolve(tracks, width: room, spacing: trackSpacing)
        let widths = LazyGridTracks.extents(proposed, width: room, spacing: trackSpacing)
        if WinUIView.arranging == 0 {
            let revision = cells.runs.revision
            if widths != columns {
                columns = widths
                measured = [:]
                measuredRevisions = [:]
                cells.runs.reset()
                geometryChanged = true
            }
            var runExtents: [Int: Double] = [:]
            if cells.requestedItemsAreCurrent, !widths.isEmpty {
                for identity in cells.identities[cells.built] where mounted[identity] == nil {
                    if let place = cells.position(of: identity) { runExtents[place / widths.count] = 0 }
                }
            }
            for (identity, item) in mounted {
                guard !item.departing, let place = cells.position(of: identity), !widths.isEmpty else { continue }
                let run = place / widths.count, track = place % widths.count
                let margin = item.values.margin
                let proposal: Double? = axis == .vertical
                    ? Double(Float(max(0, widths[track] - margin.left - margin.right))) : nil
                var size: LayoutSize
                if let kept = measured[identity], kept.proposal == proposal,
                   measuredRevisions[identity] == item.view.measurementRevision {
                    size = kept.size
                    prepare(item, offered: proposal, size: size)
                    if measuredRevisions[identity] != item.view.measurementRevision {
                        size = item.size(offered: proposal)
                        cells.measurements += 1
                        measured[identity] = (proposal, size)
                        measuredRevisions[identity] = item.view.measurementRevision
                    }
                } else {
                    size = preparedSize(of: item, offered: proposal)
                    cells.measurements += 1
                    measured[identity] = (proposal, size)
                    measuredRevisions[identity] = item.view.measurementRevision
                }
                let extent = axis == .vertical
                    ? size.height + margin.top + margin.bottom
                    : size.width + margin.left + margin.right
                runExtents[run] = max(runExtents[run] ?? 0, extent)
            }
            for (run, extent) in runExtents { cells.runs.measure(run, extent: extent) }
            commitAnchor(perRun: perRun, grid: true)
            if cells.runs.revision != revision || cells.runs.total(count: runCount) != measuredExtent {
                geometryChanged = true
                forgetMeasurements()
            }
            measuredExtent = cells.runs.total(count: runCount)
            measuredRevision = measurementRevision
        }
    }

    /// A speculative track count has its own estimates; it never resets the
    /// realized grid's tracks or the measured runs used by its viewport.
    override func contentSize(width: Double?) -> LayoutSize {
        let width = width.flatMap { $0.isFinite ? Double(Float($0)) : nil }
        let room = max(0, axis == .vertical
            ? ((width ?? standsAt).map { $0 - padding.left - padding.right } ?? acrossRoom)
            : acrossRoom)
        let proposed = LazyGridTracks.resolve(tracks, width: room, spacing: trackSpacing)
        let widths = LazyGridTracks.extents(proposed, width: room, spacing: trackSpacing)
        let count = (cells.identities.count + max(1, proposed.count) - 1) / max(1, proposed.count)
        let total: Double
        if widths == columns {
            total = cells.runs.total(count: count)
        } else {
            let padding = cells.runs.padding
            total = padding.head + padding.tail + Double(count) * cells.runs.estimate
                + Double(max(0, count - 1)) * runSpacing
        }
        return axis == .vertical
            ? LayoutSize(width: width ?? 0, height: total)
            : LayoutSize(width: total, height: widths.reduce(0, +)
                + Double(max(widths.count - 1, 0)) * trackSpacing + padding.top + padding.bottom)
    }

    override func arrange(in bounds: Rect) {
        acrossRoom = max(0, axis == .vertical
            ? bounds.width - padding.left - padding.right
            : bounds.height - padding.top - padding.bottom)
        super.arrange(in: bounds)
        let widths = columns
        guard !widths.isEmpty else { return }
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
            if cells.inserting.remove(identity) == nil { placed.fadeIn = nil }
            self.place(placed, at: direction.places(frame, in: bounds))
        }
    }

    override func tellWindow(_ span: Range<Double>, realize: Range<Double>) {
        cells.show(span, perRun: perRun, grid: true, realize: realize,
                   measureBeforeExpanding: cells.element?.handler(.realizedChanged) != nil)
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
