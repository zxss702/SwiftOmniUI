// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIAndroid

/// What a lazy container's view does alike: it keeps the children in view
/// mounted - and only those - telling the tree which identities the window
/// wants built, and standing each at the offset its measure says.
///
/// Where GTK's run finds its scroller by walking the widgets, an Android view
/// has no parent to ask: the scroller pushes the window down instead
/// (`AndroidScrollView.scrolled` and the document's `onArranged`), and a run no
/// scroller ever reaches builds all of its children from the frame report
/// after each layout pass.
/// Design: docs/design/host/items.md#the-view-moving
@MainActor
class AndroidLazyView: AndroidTravellingLayout {
    /// The direction the children stack in.
    let axis: StackArithmetic.Axis

    /// The cells' bookkeeping: identities, mounted children, the runs' measures.
    let cells: LazyCells

    /// The children mounted now, by identity.
    private(set) var mounted: [String: AndroidLayoutItem] = [:]

    /// Where the frame reports come from: a run outside every scroller builds
    /// all of its children, said once a layout pass is over.
    private weak var runtime: HostRuntime?

    var measured: [String: (proposal: Double?, size: LayoutSize)] = [:]
    var measuredRevision = -1
    var measuredAcross: Double?
    var naturalAcross = 44.0
    var anchorTarget: Double?

    /// Whether a scroller has told this run's window; until one does it stands
    /// as though fully in view.
    private var windowed = false

    init(axis: StackArithmetic.Axis, cells: LazyCells, runtime: HostRuntime) {
        self.axis = axis
        self.cells = cells
        self.runtime = runtime
        super.init()
        runtime.frames.follow(self, order: number, reads: true)
    }

    /// The mounted children, held by identity.
    func setItems(_ items: [(identity: String, item: AndroidLayoutItem)]) {
        if !windowed { runtime?.frames.follow(self, order: number, reads: true) }
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
        setChildren(items.map(\.item.view))
        invalidateMeasurements()
        measuredRevision = measurements.revision
    }

    /// The scroller clipping this run on its own axis pushed the window's span
    /// - the part of the run in view, along the run; nil where it shows none,
    /// which asks nothing new of the tree.
    func windowMoved(to span: Range<Double>?) {
        if !windowed {
            windowed = true
            runtime?.frames.follow(self, order: number, reads: false)
        }
        tellWindow(span ?? 0..<0)
    }

    /// The places standing in `span`, as the kind's runs count them.
    func tellWindow(_ span: Range<Double>) {}

    override func detach() {
        super.detach()
        runtime?.frames.follow(self, order: number, reads: false)
        runtime = nil
    }
}

extension AndroidLazyView: FrameReporter {
    /// A layout pass ended: a run no scroller narrows stands wholly in view.
    func reportFrame() {
        if !windowed { cells.tellAll() }
        runtime?.frames.follow(self, order: number, reads: false)
    }
}

/// A lazy stack: one child a place.
final class AndroidLazyStackView: AndroidLazyView {
    /// The room between two children.
    var spacing = 0.0 {
        didSet { if spacing != oldValue { cells.extents.spacing = spacing; invalidateMeasurements() } }
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
        places.begin(width: bounds.width, animating: cells.animatesChanges)
        let across = max(0, axis == .vertical
            ? bounds.width - padding.left - padding.right
            : bounds.height - padding.top - padding.bottom)
        let revision = cells.extents.revision
        if measuredAcross != across {
            cells.extents.reset()
            // Each row's own measure is kept: it names the proposal it was taken at, and the loop
            // below measures again exactly the rows whose proposal is no longer that one. A room
            // that returns costs no measure at all.
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
        if cells.extents.revision != revision { invalidateMeasurements() }
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
            self.place(item, at: direction.places(frame, in: bounds))
        }
    }

    override func tellWindow(_ span: Range<Double>) {
        cells.show(span)
    }
}

/// A lazy grid: the cells fill the tracks across its run, a run at a time -
/// a `LazyVGrid`'s run is a row of its columns, a `LazyHGrid`'s a column of
/// its rows.
final class AndroidLazyGridView: AndroidLazyView {
    /// The tracks across - `flowColumns` down a grid, `flowRows` across one.
    var tracks: [GridItem] = [] { didSet { if tracks != oldValue { columns = [] } } }

    /// The room between one run and the next.
    var runSpacing = 0.0 {
        didSet { if runSpacing != oldValue { cells.runs.spacing = runSpacing; invalidateMeasurements() } }
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
                // The rows' own measures are kept: each names the track width it was taken at,
                // and only the rows whose proposal changed are measured again.
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
        places.begin(width: bounds.width, animating: cells.animatesChanges)
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
        if cells.runs.revision != revision { invalidateMeasurements() }
        measuredRevision = measurements.revision
        var trackOrigins: [Double] = []
        var start = axis == .vertical ? padding.left : padding.top
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
            self.place(item, at: direction.places(frame, in: bounds))
        }
    }

    override func tellWindow(_ span: Range<Double>) {
        cells.show(span, perRun: perRun, grid: true)
    }
}

extension Axis {
    /// Whether a scroller of this axis can clip a lazy run of `axis`.
    func takes(_ axis: StackArithmetic.Axis) -> Bool {
        switch (self, axis) {
        case (.both, _), (.vertical, .vertical), (.horizontal, .horizontal): true
        default: false
        }
    }
}
