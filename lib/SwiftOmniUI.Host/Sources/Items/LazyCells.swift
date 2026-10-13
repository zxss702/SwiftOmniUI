// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore

/// What a host's lazy container holds of one lazy layout, and what it tells
/// the tree - alike on every host: the children's identities in order, the
/// ones standing in view, the mounted subtree each builds, and the run's
/// arithmetic.
///
/// Where a collection (`ItemsCells`) is asked for entries by the cells its
/// toolkit reuses, a lazy container asks itself: it measures the room on
/// screen, names the children in it by `tell`, and the tree mounts those -
/// and only those - under it.
/// Design: docs/design/host/items.md#the-view-moving
@_spi(Host) @MainActor public final class LazyCells {
    /// Whether a lazy window's realization is waiting for its render: moving a window's cells moves no window's
    /// bounds. The host that presents the render clears it.
    public nonisolated(unsafe) static var realizing = false

    /// The lazy element, while it stands in the tree.
    public private(set) weak var element: MountedElement?

    private weak var runtime: HostRuntime?

    /// Every child's identity in the order it shows, as last taken.
    public private(set) var identities: [String] = []

    private var contentRevision = -1
    private var positions: [String: Int] = [:]

    /// Content changes waiting for arrangement. Measurement and viewport realization must
    /// not consume this; the host clears it after beginning the changed arrangement.
    public var animatesChanges = false
    /// New source identities awaiting their first placement; recycled neighbours never enter here.
    public var inserting: Set<String> = []
    /// The source positions mounted, including the fixed neighbour window.
    public private(set) var built: Range<Int> = 0..<0

    /// The last viewport and geometry asked for. Identical layout notices do
    /// not perform another range lookup or send another render.
    public var window: (span: Range<Double>, revision: Int, perRun: Int, realize: Range<Double>)?

    /// A host's realization-density version, independent of the document's
    /// measured extents. Learning an actual 44-point row changes the plan
    /// even though its document coordinates stay exactly as estimated.
    public private(set) var windowPlanningRevision = 0

    /// An incremental host has requested unmeasured runs. Measure them before
    /// expanding the same window; an unchanged 44-point estimate still resumes.
    public private(set) var needsMeasurement = false

    /// Requested rows have finished their render. During a patch or a held
    /// transaction, a missing native row can still be waiting for that render.
    public var requestedItemsAreCurrent: Bool {
        guard let runtime, element?.handler(.realizedChanged) != nil else { return false }
        return !runtime.intake.isApplying && !runtime.pump.handlers.inTransaction
            && !runtime.pump.handlers.hasQueued && !runtime.core.needsRender
    }

    /// Diagnostic counts for the work a lazy window actually performs.
    public private(set) var requests = 0
    /// Viewport range lookups performed.
    public var searches = 0
    /// Native child measurements performed.
    public var measurements = 0

    /// Document-coordinate correction not yet applied to the mounted presentation frames.
    public var anchorShift = 0.0

    private var anchor: (identity: String, place: Int, inset: Double, origin: Double, viewport: Double, trailing: Bool)?

    /// The run's arithmetic: measured extents by identity, the rest at 44.
    public var extents = LazyExtents()

    /// A grid's arithmetic: one extent a row, measured of the tallest cell
    /// it holds; forgotten where the column count changes the runs.
    public var runs = LazyRunExtents()

    /// The cells of `element`, telling `runtime`.
    public init(_ element: MountedElement, in runtime: HostRuntime) {
        self.element = element
        self.runtime = runtime
    }

    /// Takes a fresh content source. Insertions, removals and moves preserve the
    /// measured sizes of surviving identities; changed content invalidates them.
    @discardableResult
    public func takeItems() -> Bool {
        let now = element?.value(.items)?.strings ?? []
        let revision = element?.lazyContentRevision ?? 0
        guard now != identities || revision != contentRevision else { return false }
        if contentRevision >= 0 {
            animatesChanges = true
            inserting.formUnion(Set(now).subtracting(identities))
        }
        contentRevision = revision
        inserting.formIntersection(now)
        // Identities arriving or leaving change what the window mounts and
        // which measurements survive. A content revision bump alone changes
        // neither; the patched children re-measure on their next layout pass.
        if now != identities {
            extents.keep(identities: Set(now))
            positions = Dictionary(now.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
            extents.adopt(positions: positions)
            built = 0..<0
            window = nil
            needsMeasurement = false
            runs.reset()
        }
        identities = now
        if now.isEmpty {
            anchor = nil
            anchorShift = 0
        }
        return true
    }

    /// The place `identity` shows at; nil where it is none of them.
    public func position(of identity: String) -> Int? {
        positions[identity]
    }

    /// The mounted subtree of `identity`, where there is one.
    public func item(_ identity: String) -> MountedElement? {
        element?.children.first {
            if let source = $0.lazyIdentity { return source == identity }
            return $0.id == .manual(identity)
        }
    }

    /// The mounted children, each with the place its identity stands at, in
    /// the order they show.
    public var mounted: [(place: Int, item: MountedElement)] {
        guard let element else { return [] }
        return element.children.compactMap { child in
            guard case .manual(let identity) = child.id,
                  let place = positions[child.lazyIdentity ?? identity] else { return nil }
            return (place, child)
        }
        .sorted { $0.0 < $1.0 }
    }

    /// Where `place`'s child begins on the run, counting the padding head.
    public func offset(of place: Int) -> Double {
        extents.offset(of: place, in: identities)
    }

    /// The places standing in `span` - `from` to `to` on the run - widened by
    /// `overscan` at both ends.
    public func places(in span: Range<Double>, overscan: Double) -> Range<Int> {
        extents.places(in: span, overscan: overscan, in: identities)
    }

    /// The whole run's length, both paddings in.
    public var total: Double {
        extents.total(in: identities)
    }

    /// Reads a viewport only when it or the content geometry changed. Shared
    /// by every host's stack and grid, including empty and clipped windows.
    /// `realize`, where it differs from `span`, is the window a scroller moving
    /// under its own power can show before the next notice: the cells it covers
    /// are mounted while `span`'s own arithmetic - shown places, the anchor -
    /// keeps reading the true viewport.
    /// `estimatedUnknownRunExtent` plans how many unknown runs fit after the
    /// host measured its first complete run. It never changes the 44-point
    /// document estimates, offsets or anchor; hosts omitting it keep their
    /// existing window policy.
    public func show(_ span: Range<Double>, perRun: Int = 1, grid: Bool = false, realize: Range<Double>? = nil,
                     measureBeforeExpanding: Bool = false, estimatedUnknownRunExtent: Double? = nil,
                     planningRevision: Int = 0) {
        let revision = grid ? runs.revision : extents.revision
        let realize = realize ?? span
        guard window?.span != span || window?.revision != revision || window?.perRun != perRun
            || window?.realize != realize || windowPlanningRevision != planningRevision
            || needsMeasurement else { return }
        let moved = window?.revision == revision && window?.span != span
        window = (span, revision, perRun, realize)
        windowPlanningRevision = planningRevision
        searches += 1
        let runCount = (identities.count + perRun - 1) / perRun
        let wanted = grid
            ? runs.places(in: realize, overscan: 0, count: runCount)
            : extents.places(in: realize, overscan: 0, in: identities)
        let shown = realize == span ? wanted : grid
            ? runs.places(in: span, overscan: 0, count: runCount)
            : extents.places(in: span, overscan: 0, in: identities)
        if !shown.isEmpty, anchor == nil || moved {
            let place = shown.lowerBound * perRun
            let origin = grid
                ? runs.offset(of: shown.lowerBound, count: (identities.count + perRun - 1) / perRun)
                : extents.offset(of: place, in: identities)
            let total = grid
                ? runs.total(count: (identities.count + perRun - 1) / perRun)
                : extents.total(in: identities)
            anchor = (identities[place], place, span.lowerBound - origin, span.lowerBound,
                      span.upperBound - span.lowerBound, span.lowerBound > 0 && abs(span.upperBound - total) < 1)
        }
        guard let element, let runtime else { return }
        let lower = min(identities.count, max(0, wanted.lowerBound - 1) * perRun)
        var upper = min(identities.count, (wanted.upperBound + 1) * perRun)
        let requestedUpper = upper
        needsMeasurement = false
        if measureBeforeExpanding, !wanted.isEmpty {
            let first = lower / perRun
            let estimate = estimatedUnknownRunExtent.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            if let estimate {
                // Select a batch by its predicted physical coverage, rather
                // than rendering every unknown row in a separate tree turn.
                // Only this request uses the host's sampled density. All
                // document coordinates continue to use their own arithmetic.
                let gap = grid ? runs.spacing : extents.spacing ?? StackArithmetic.automaticSpacing
                var origin = grid ? runs.offset(of: first, count: runCount)
                    : extents.offset(of: first, in: identities)
                var end = first
                while end < runCount, origin < realize.upperBound {
                    let known = grid ? runs.hasMeasurement(for: end)
                        : extents.hasMeasurement(for: identities[end])
                    let extent = known ? (grid ? runs.extent(of: end) : extents.extent(of: identities[end])) : estimate
                    origin += extent + gap
                    end += 1
                }
                // Keep the same complete neighbour run at the trailing edge
                // as the ordinary window, also when its last row is partial.
                upper = min(identities.count, min(runCount, end + 1) * perRun)
            } else {
                // The first complete unknown run probes the selected native
                // proposal before a page of potentially tall cards is built.
                for run in first..<((upper + perRun - 1) / perRun) {
                    let known = grid ? runs.hasMeasurement(for: run)
                        : extents.hasMeasurement(for: identities[run])
                    if !known {
                        upper = min(identities.count, (run + 1) * perRun)
                        break
                    }
                }
            }
            // Keep surviving native seats within this window attached while
            // learning an inserted row's size. A partial fill must not briefly
            // evict a focused control and recreate it on the following fill.
            for child in element.children {
                guard case .manual(let identity) = child.id,
                      let place = positions[child.lazyIdentity ?? identity],
                      place >= lower, place < requestedUpper else { continue }
                upper = max(upper, min(requestedUpper, (place / perRun + 1) * perRun))
            }
            // A measured row equal to 44 does not advance geometry.revision.
            // Request completion therefore follows measurement presence, not
            // a changed length or whether this batch stopped short of 44's window.
            needsMeasurement = (first..<((upper + perRun - 1) / perRun)).contains { run in
                grid ? !runs.hasMeasurement(for: run) : !extents.hasMeasurement(for: identities[run])
            }
        }
        let within = !wanted.isEmpty && lower < upper ? lower..<upper : 0..<0
        if !needsMeasurement { inserting.formIntersection(identities[within]) }
        guard within != built else { return }
        if !inserting.isDisjoint(with: identities[within]) { animatesChanges = true }
        built = within
        requests += 1
        Self.realizing = true
        element.send(.realizedChanged, [.strings(Array(identities[within]))], in: runtime)
    }

    /// The corrected viewport origin after measurements or data move its anchor.
    /// A viewport at the end stays at the end. Hosts apply this absolute origin
    /// because their native scroller may already have clamped a shrinking document.
    public func correctedOrigin(perRun: Int = 1, grid: Bool = false) -> Double? {
        guard let held = anchor, !identities.isEmpty else { return nil }
        let place = positions[held.identity] ?? min(held.place, identities.count - 1)
        let start = grid
            ? runs.offset(of: place / perRun, count: (identities.count + perRun - 1) / perRun)
            : extents.offset(of: place, in: identities)
        let total = grid
            ? runs.total(count: (identities.count + perRun - 1) / perRun)
            : extents.total(in: identities)
        let origin = max(0, held.trailing ? total - held.viewport : start + held.inset)
        anchorShift += origin - held.origin
        anchor = (identities[place], place, held.inset, origin, held.viewport, held.trailing)
        return abs(origin - held.origin) > 0.0001 ? origin : nil
    }

    /// Without a scroller there is no viewport to narrow by.
    public func tellAll() {
        guard let element, let runtime, built != 0..<identities.count else { return }
        if !inserting.isEmpty { animatesChanges = true }
        built = 0..<identities.count
        needsMeasurement = false
        requests += 1
        element.send(.realizedChanged, [.strings(identities)], in: runtime)
    }

}

/// Fenwick sums over a run's places: the extents measured so far and how many places they are, so the
/// offset of any place is found in O(log n) however many places stand unmeasured.
private struct MeasuredSums: Sendable {
    private var extents: [Double]
    private var counts: [Int]

    init(places: Int = 0) {
        extents = Array(repeating: 0, count: places + 1)
        counts = Array(repeating: 0, count: places + 1)
    }

    mutating func add(_ place: Int, extent: Double, count: Int) {
        var node = place + 1
        while node < extents.count {
            extents[node] += extent
            counts[node] += count
            node += node & -node
        }
    }

    /// The sums over the places before `place`.
    func before(_ place: Int) -> (extent: Double, count: Int) {
        var node = min(place, extents.count - 1), extent = 0.0, count = 0
        while node > 0 {
            extent += extents[node]
            count += counts[node]
            node -= node & -node
        }
        return (extent, count)
    }
}

/// Measured child extents; each place not yet measured stands at 44.
/// The host invalidates measurements when the source or its cross-axis size changes.
@_spi(Host) public struct LazyExtents: Sendable {
    /// The spacing between adjacent children or runs.
    public var spacing: Double? = 0 {
        didSet { if spacing != oldValue { revision += 1 } }
    }
    /// Space before the first and after the last child or run.
    public var padding: (head: Double, tail: Double) = (0, 0) {
        didSet { if padding != oldValue { revision += 1 } }
    }
    /// The provisional extent of each unseen child, independent of measured neighbours.
    public let estimate: Double = 44
    /// Geometry version used to reuse viewport searches.
    public private(set) var revision = 0
    private var measured: [String: Double] = [:]
    private var index: [String: Int] = [:]
    private var sums = MeasuredSums()

    /// Starts with a provisional extent until the first window is measured.
    public init() {}

    /// A complete child measurement. Zero is a valid size.
    public mutating func measure(_ identity: String, extent: Double) {
        guard extent.isFinite, extent >= 0, measured[identity] != extent else { return }
        let before = measured[identity]
        let previous = before ?? estimate
        measured[identity] = extent
        if let place = index[identity] { sums.add(place, extent: extent - (before ?? 0), count: before == nil ? 1 : 0) }
        if extent != previous { revision += 1 }
    }

    /// Reordering invalidates positions even when every identity survives; `adopt` follows.
    public mutating func keep(identities: Set<String>) {
        measured = measured.filter { identities.contains($0.key) }
        index = [:]
        sums = MeasuredSums()
        revision += 1
    }

    /// Takes the places the identities stand at, summing what is measured over them.
    public mutating func adopt(positions: [String: Int]) {
        index = positions
        sums = MeasuredSums(places: positions.count)
        for (identity, extent) in measured {
            if let place = index[identity] { sums.add(place, extent: extent, count: 1) }
        }
    }

    /// Forget sizes that were measured under a different layout proposal.
    public mutating func reset() {
        measured = [:]
        sums = MeasuredSums(places: index.count)
        revision += 1
    }

    /// The measured child extent, or the current estimate.
    public func extent(of identity: String) -> Double {
        measured[identity] ?? estimate
    }

    /// Whether this child's estimate has been replaced by a native measurement.
    public func hasMeasurement(for identity: String) -> Bool { measured[identity] != nil }

    private var gap: Double { spacing ?? StackArithmetic.automaticSpacing }

    private mutating func sync(_ identities: [String]) {
        guard index.count != identities.count else { return }
        adopt(positions: Dictionary(identities.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first }))
    }

    /// Where `place` begins: the extents before it, measured or estimated, and a gap after each. O(log n).
    public mutating func offset(of place: Int, in identities: [String]) -> Double {
        sync(identities)
        let count = identities.count, place = max(0, min(place, count))
        let known = sums.before(place)
        let gaps = count == 0 ? 0 : (place == count ? count - 1 : place)
        return padding.head + known.extent + estimate * Double(place - known.count) + Double(gaps) * gap
    }

    /// Estimated length of the entire data source, including both paddings.
    public mutating func total(in identities: [String]) -> Double {
        guard identities.count > 0 else { return padding.head + padding.tail }
        return offset(of: identities.count, in: identities) + padding.tail
    }

    /// Only actual intersections count as visible; spacing is not a child. O(log² n).
    public mutating func places(in span: Range<Double>, overscan: Double, in identities: [String]) -> Range<Int> {
        guard identities.count > 0, !span.isEmpty else { return 0..<0 }
        let lo = span.lowerBound - overscan, hi = span.upperBound + overscan
        var lower = 0, upper = identities.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            let end = offset(of: middle + 1, in: identities) - (middle + 1 < identities.count ? gap : 0)
            if end <= lo { lower = middle + 1 }
            else { upper = middle }
        }
        let first = lower
        upper = identities.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if offset(of: middle, in: identities) < hi { lower = middle + 1 }
            else { upper = middle }
        }
        return first < lower ? first..<lower : 0..<0
    }
}

/// Measured row or column extents; each run not yet measured stands at 44.
/// The host invalidates measurements when the source or its cross-axis size changes.
@_spi(Host) public struct LazyRunExtents: Sendable {
    /// The spacing between adjacent children or runs.
    public var spacing: Double = 0 {
        didSet { if spacing != oldValue { revision += 1 } }
    }
    /// Space before the first and after the last child or run.
    public var padding: (head: Double, tail: Double) = (0, 0) {
        didSet { if padding != oldValue { revision += 1 } }
    }
    /// The provisional extent of each unseen run, independent of measured neighbours.
    public let estimate: Double = 44
    /// Geometry version used to reuse viewport searches.
    public private(set) var revision = 0
    private var measured: [Int: Double] = [:]
    private var runs = 0
    private var sums = MeasuredSums()

    /// Starts with a provisional extent until the first window is measured.
    public init() {}

    /// A complete run, measured as the largest of its current cells. Zero is a valid size.
    public mutating func measure(_ run: Int, extent: Double) {
        guard extent.isFinite, extent >= 0, measured[run] != extent else { return }
        let before = measured[run]
        let previous = before ?? estimate
        measured[run] = extent
        if run < runs { sums.add(run, extent: extent - (before ?? 0), count: before == nil ? 1 : 0) }
        if extent != previous { revision += 1 }
    }

    /// Forget sizes that were measured under a different layout proposal.
    public mutating func reset() {
        measured = [:]
        sums = MeasuredSums(places: runs)
        revision += 1
    }

    /// The measured run extent, or the current estimate.
    public func extent(of run: Int) -> Double {
        measured[run] ?? estimate
    }

    /// Whether this complete grid run has been measured.
    public func hasMeasurement(for run: Int) -> Bool { measured[run] != nil }

    private mutating func sync(_ count: Int) {
        guard runs != count else { return }
        runs = count
        sums = MeasuredSums(places: count)
        for (run, extent) in measured where run < count { sums.add(run, extent: extent, count: 1) }
    }

    /// Where run `place` begins: the extents before it and a gap after each. O(log n).
    public mutating func offset(of place: Int, count: Int) -> Double {
        sync(count)
        let place = max(0, min(place, count))
        let known = sums.before(place)
        return padding.head + known.extent + estimate * Double(place - known.count) + Double(place) * spacing
    }

    /// Estimated length of the entire data source, including both paddings.
    public mutating func total(count: Int) -> Double {
        guard count > 0 else { return padding.head + padding.tail }
        return offset(of: count, count: count) + padding.tail - spacing
    }

    /// Only actual intersections count as visible; spacing is not a child. O(log² n).
    public mutating func places(in span: Range<Double>, overscan: Double, count: Int) -> Range<Int> {
        guard count > 0, !span.isEmpty else { return 0..<0 }
        let lo = span.lowerBound - overscan, hi = span.upperBound + overscan
        var lower = 0, upper = count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if offset(of: middle + 1, count: count) - spacing <= lo { lower = middle + 1 }
            else { upper = middle }
        }
        let first = lower
        upper = count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if offset(of: middle, count: count) < hi { lower = middle + 1 }
            else { upper = middle }
        }
        return first < lower ? first..<lower : 0..<0
    }
}

/// A lazy grid's tracks across its run: the columns a `LazyVGrid` fills, or
/// the rows a `LazyHGrid` fills, resolved for the room the host gives.
@_spi(Host) public enum LazyGridTracks {
    /// The sizes `items` stand for at `width`: stated tracks as they stand,
    /// an `.adaptive` one as many `.flexible` copies as the room fits.
    public static func resolve(_ items: [GridItem], width: Double?, spacing: Double) -> [GridItem.Size] {
        GridArithmetic.resolvedFlow(items, width: width, spacing: spacing)
    }

    /// How wide each resolved track stands: fixed as stated, the rest
    /// sharing what is left within their bounds.
    public static func extents(_ tracks: [GridItem.Size], width: Double, spacing: Double) -> [Double] {
        var taken = spacing * Double(max(tracks.count - 1, 0))
        var shares = 0
        for track in tracks {
            switch track {
            case .fixed(let width): taken += width
            case .flexible, .adaptive: shares += 1
            }
        }
        let share = max(0, width - taken) / Double(max(shares, 1))
        return tracks.map { track in
            switch track {
            case .fixed(let width): return width
            case .flexible(let minimum, let maximum), .adaptive(let minimum, let maximum):
                return min(max(share, minimum), max(minimum, maximum))
            }
        }
    }
}
