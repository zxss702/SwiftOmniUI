// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIGTK

/// What a lazy container's view does alike: it keeps the children in view
/// mounted - and only those - telling the tree which identities the window
/// wants built, and standing each at the offset its measure says.
///
/// The run's length is the estimates' before the children exist, so the
/// scroll room answers at once; a child's own measure lands as it mounts and
/// shifts the places after it, the way a scroller of estimated rows does.
/// Design: docs/design/host/items.md#the-view-moving
@MainActor
class GTKLazyView: GTKTravellingLayout {
    /// The direction the children stack in.
    let axis: StackArithmetic.Axis

    /// The cells' bookkeeping: identities, mounted children, the runs' measures.
    let cells: LazyCells

    /// The children mounted now, by identity.
    private(set) var mounted: [String: GTKLayoutItem] = [:]

    /// The scroller whose window the run answers, and the ear it hears it by.
    private weak var watching: GTKScrollView?
    private var ear: GTKScrollEar?

    /// Natural sizes survive scrolling; content invalidation or a changed
    /// cross-axis proposal clears only the measurements that can be stale.
    var measured: [String: (proposal: Double?, size: LayoutSize)] = [:]
    var measuredRevision = -1
    var measuredAcross: Double?
    var naturalAcross = 44.0
    var anchorTarget: Double?
    var geometryChanged = false

    /// A window change under way asks the run again once, not per notice.
    private var retellQueued = false

    init(axis: StackArithmetic.Axis, cells: LazyCells) {
        self.axis = axis
        self.cells = cells
        super.init()
    }

    /// The mounted children, held by identity.
    func setItems(_ items: [(identity: String, item: GTKLayoutItem)]) {
        let now = Dictionary(items.map { ($0.0, $0.1) }, uniquingKeysWith: { first, _ in first })
        guard now.keys != mounted.keys || now.contains(where: {
            mounted[$0.key]?.view !== $0.value.view || mounted[$0.key]?.values != $0.value.values
        }) else { return }
        if now.contains(where: { identity, item in
            mounted[identity].map { $0.values != item.values } ?? false
        }) {
            cells.extents.reset()
            cells.runs.reset()
        }
        for (identity, previous) in mounted {
            if now[identity]?.view !== previous.view || now[identity]?.values != previous.values {
                measured.removeValue(forKey: identity)
            }
        }
        mounted = now
        for item in items { item.item.view.placingLayout = self }
        setChildren(items.map(\.item.view))
        invalidateMeasurements()
        measuredRevision = measurements.revision
    }

    /// The nearest scroller clipping this run on its own axis, or none: a
    /// scroller turned the other way narrows nothing of this run's window.
    private var clip: GTKScrollView? {
        var widget = gtk_widget_get_parent(widget)
        while let current = widget {
            if GTKPanel.holds(current),
               let view = GTKView.find(GTKPanel.number(of: current)) as? GTKScrollView {
                if view.orientation.takes(axis) { return view }
            }
            widget = gtk_widget_get_parent(current)
        }
        return nil
    }

    /// The window the run shows - the scroller's room brought into this view,
    /// along the run.
    var span: Range<Double>? {
        guard !cells.identities.isEmpty, let scroll = clip,
              let document = scroll.scroller.content else { return nil }
        var bounds = graphene_rect_t()
        guard gtk_widget_compute_bounds(self.widget, document.widget, &bounds) != 0 else { return nil }
        let room = axis == .vertical
            ? Double(gtk_widget_get_height(scroll.scroller.widget))
            : Double(gtk_widget_get_width(scroll.scroller.widget))
        // value-changed precedes the viewport's allocation. Document coordinates plus the
        // adjustment's current offset describe one instant; the old viewport transform does not.
        let offset = scroll.scroller.standing.offset
        let start = axis == .vertical
            ? Double(bounds.origin.y) - offset.y : Double(bounds.origin.x) - offset.x
        let own = axis == .vertical
            ? Double(gtk_widget_get_height(widget))
            : Double(gtk_widget_get_width(widget))
        let low = max(0, -start), high = min(own, room - start)
        guard high > low else { return nil }
        return low..<high
    }

    /// Asks the tree for the children the window wants; each kind answers
    /// which places a span holds. No scroller to narrow by means all of them.
    /// One retell a layout pass, after GTK has laid the frame out.
    private func retell() {
        guard !retellQueued else { return }
        retellQueued = true
        GTKDoorbell.afterLayout { [weak self] in
            guard let self else { return }
            self.retellQueued = false
            self.watchClip()
            if self.geometryChanged {
                self.geometryChanged = false
                self.invalidateMeasurements()
                self.measuredRevision = self.measurements.revision
                // GTK updates the adjustment's bounds during allocation. Applying an anchor now
                // would use the previous extent and the next allocation would clamp it again.
                // allocate schedules the next retell after the new document has been committed.
                return
            }
            // No clip to narrow by means all of it stands in view - a lazy
            // container outside any scroller builds every child.
            guard self.watching != nil else {
                self.cells.tellAll()
                return
            }
            if let origin = self.anchorTarget, let scroll = self.watching,
               let document = scroll.scroller.content as? GTKScrollDocument {
                let size = document.contentSize(width: Double(gtk_widget_get_width(document.widget)))
                let room = self.axis == .vertical
                    ? Double(gtk_widget_get_height(scroll.scroller.widget))
                    : Double(gtk_widget_get_width(scroll.scroller.widget))
                let extent = self.axis == .vertical ? size.height : size.width
                let reach = self.axis == .vertical
                    ? scroll.scroller.standing.reach.y : scroll.scroller.standing.reach.x
                // An idle callback can follow measurement but precede the frame's allocation.
                // Keep the anchor until the adjustment contains this document's current extent;
                // writing earlier loses it when GTK constrains the value to the old bounds.
                guard abs(max(room, extent) - room - reach) < 1 else { return }
                var target = scroll.scroller.standing.offset
                var bounds = graphene_rect_t()
                if gtk_widget_compute_bounds(self.widget, document.widget, &bounds) != 0 {
                    if self.axis == .vertical { target.y = Double(bounds.origin.y) + origin }
                    else { target.x = Double(bounds.origin.x) + origin }
                    self.anchorTarget = nil
                    scroll.scroller.move(to: target)
                }
            }
            self.tellWindow(self.span ?? 0..<0)
        }
    }

    /// The places standing in `span`, as the kind's runs count them.
    func tellWindow(_ span: Range<Double>) {}

    /// Recomputes the places when the scroller's window moved.
    private func watchClip() {
        let scroller = clip
        guard scroller !== watching else { return }
        ear?.owner = nil
        watching = scroller
        let ear = GTKScrollEar(owner: self) { [weak self] in
            self?.windowMoved()
        }
        self.ear = ear
        scroller?.scroller.ears.append(ear)
    }

    private func windowMoved() {
        if GTKView.allocating == 0, !geometryChanged, anchorTarget == nil {
            tellWindow(span ?? 0..<0)
        }
        retell()
    }

    /// Every allocation re-asks the window - GTK allocates the document again
    /// when the viewport moves it.
    override func allocate(width: Double, height: Double) {
        super.allocate(width: width, height: height)
        retell()
    }

    /// GTK asks the run's measure again where its places moved.
    override func measure(across: Bool, forSize: Int32) -> Double {
        retell()
        return super.measure(across: across, forSize: forSize)
    }

    override func detach() {
        super.detach()
        ear?.owner = nil
        ear = nil
        watching = nil
    }
}

/// A lazy stack: one child a place.
final class GTKLazyStackView: GTKLazyView {
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

    /// As wide as offered and as long as the run measures.
    override func contentSize(width: Double?) -> LayoutSize {
        let total = cells.total
        return axis == .vertical
            ? LayoutSize(width: width ?? 0, height: total)
            : LayoutSize(width: total, height: naturalAcross + padding.top + padding.bottom)
    }

    /// Every mounted child measures, is stood at its offset, and the window
    /// re-asks what the tree builds.
    override func arrange(in bounds: Rect) {
        let across = max(0, axis == .vertical
            ? bounds.width - padding.left - padding.right
            : bounds.height - padding.top - padding.bottom)
        let revision = cells.extents.revision
        if measuredAcross != across {
            cells.extents.reset()
            measured = [:]
            measuredAcross = across
        }
        if measuredRevision != measurements.revision { measured = [:] }
        for (identity, item) in mounted {
            guard !item.departing, cells.position(of: identity) != nil else { continue }
            let margin = item.values.margin
            let proposal: Double? = axis == .vertical
                ? max(0, across - margin.left - margin.right) : nil
            let size: LayoutSize
            if let cached = measured[identity], cached.proposal == proposal {
                size = cached.size
            } else {
                size = item.size(offered: proposal)
                measured[identity] = (proposal, size)
                cells.measurements += 1
            }
            let extent = axis == .vertical
                ? size.height + margin.top + margin.bottom
                : size.width + margin.left + margin.right
            cells.extents.measure(identity, extent: extent)
        }
        let cross = mounted.compactMap { identity, item -> Double? in
            guard !item.departing, let size = measured[identity]?.size else { return nil }
            return size.height + item.values.margin.top + item.values.margin.bottom
        }.max() ?? (cells.identities.isEmpty ? 0 : 44)
        if axis == .horizontal, naturalAcross != cross {
            naturalAcross = cross
            invalidateMeasurements()
        }
        if let origin = cells.correctedOrigin() { anchorTarget = origin }
        places.begin(width: axis == .vertical ? bounds.width : bounds.height, animating: cells.animatesChanges,
                     anchorOffset: Point(axis == .horizontal ? cells.anchorShift : 0,
                                         axis == .vertical ? cells.anchorShift : 0))
        cells.animatesChanges = false
        cells.anchorShift = 0
        if cells.extents.revision != revision {
            measurements.invalidate()
            geometryChanged = true
        }
        measuredRevision = measurements.revision
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

    override func tellWindow(_ span: Range<Double>) {
        cells.show(span)
    }
}

/// A lazy grid: the cells fill the tracks across its run, a run at a time -
/// a `LazyVGrid`'s run is a row of its columns, a `LazyHGrid`'s a column of
/// its rows.
final class GTKLazyGridView: GTKLazyView {
    /// The tracks across - `flowColumns` down a grid, `flowRows` across one.
    var tracks: [GridItem] = [] { didSet { if tracks != oldValue { columns = [] } } }

    /// The room between one run and the next.
    var runSpacing = 0.0 {
        didSet { if runSpacing != oldValue { cells.runs.spacing = runSpacing; invalidateMeasurements() } }
    }

    /// Where the tracks stand together across the grid.
    var trackAlignment: AxisAlignment = .center {
        didSet { if trackAlignment != oldValue { invalidateMeasurements() } }
    }
    /// The room between the tracks.
    var trackSpacing = 0.0 { didSet { if trackSpacing != oldValue { columns = [] } } }

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
    private var columns: [Double] = [] {
        didSet {
            if columns != oldValue {
                measured = [:]
                cells.runs.reset()
                invalidateMeasurements()
            }
        }
    }

    /// The room across - inside the padding, the tracks take it all.
    private var acrossRoom = 0.0

    /// The cells a run holds.
    private var perRun: Int { max(1, columns.count) }

    /// The runs the cells make.
    private var runCount: Int { (cells.identities.count + perRun - 1) / perRun }

    /// As wide as offered and as long as the runs measure.
    override func contentSize(width: Double?) -> LayoutSize {
        let room = max(0, axis == .vertical
            ? (width.map { $0 - padding.left - padding.right } ?? acrossRoom)
            : acrossRoom)
        let proposed = LazyGridTracks.resolve(tracks, width: room, spacing: trackSpacing)
        let count = (cells.identities.count + max(1, proposed.count) - 1) / max(1, proposed.count)
        let total = cells.runs.total(count: count)
        return axis == .vertical
            ? LayoutSize(width: width ?? 0, height: total)
            : LayoutSize(width: total, height:
                LazyGridTracks.extents(proposed, width: room, spacing: trackSpacing).reduce(0, +)
                + Double(max(0, proposed.count - 1)) * trackSpacing + padding.top + padding.bottom)
    }

    override func arrange(in bounds: Rect) {
        acrossRoom = axis == .vertical
            ? bounds.width - padding.left - padding.right
            : bounds.height - padding.top - padding.bottom
        let room = max(0, acrossRoom)
        let next = LazyGridTracks.extents(
            LazyGridTracks.resolve(tracks, width: room, spacing: trackSpacing),
            width: room, spacing: trackSpacing)
        if next != columns { columns = next }
        let widths = columns
        guard !widths.isEmpty else { return }
        let revision = cells.runs.revision
        if measuredRevision != measurements.revision { measured = [:] }
        var runExtents: [Int: Double] = [:]
        for (identity, item) in mounted {
            guard let place = cells.position(of: identity) else { continue }
            let run = place / widths.count, track = place % widths.count
            let margin = item.values.margin
            let proposal: Double? = axis == .vertical
                ? max(0, widths[track] - margin.left - margin.right) : nil
            let size: LayoutSize
            if let cached = measured[identity], cached.proposal == proposal {
                size = cached.size
            } else {
                size = item.size(offered: proposal)
                measured[identity] = (proposal, size)
                cells.measurements += 1
            }
            let extent = axis == .vertical
                ? size.height + margin.top + margin.bottom
                : size.width + margin.left + margin.right
            runExtents[run] = max(runExtents[run] ?? 0, extent)
        }
        for (run, extent) in runExtents { cells.runs.measure(run, extent: extent) }
        if let origin = cells.correctedOrigin(perRun: perRun, grid: true) { anchorTarget = origin }
        places.begin(width: axis == .vertical ? bounds.width : bounds.height, animating: cells.animatesChanges,
                     anchorOffset: Point(axis == .horizontal ? cells.anchorShift : 0,
                                         axis == .vertical ? cells.anchorShift : 0))
        cells.animatesChanges = false
        cells.anchorShift = 0
        if cells.runs.revision != revision {
            measurements.invalidate()
            geometryChanged = true
        }
        measuredRevision = measurements.revision
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
            let size = measured[identity]!.size
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

    override func tellWindow(_ span: Range<Double>) {
        cells.show(span, perRun: perRun, grid: true)
    }
}

private extension Axis {
    /// Whether a scroller of this axis can clip a lazy run of `axis`.
    func takes(_ axis: StackArithmetic.Axis) -> Bool {
        switch (self, axis) {
        case (.both, _), (.vertical, .vertical), (.horizontal, .horizontal): true
        default: false
        }
    }
}
