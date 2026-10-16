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

    /// Compatibility for hosts that need a flat table. Lazy layouts use the
    /// persistent order below, so a local source edit does not copy every ID.
    public var identities: [String] { source?.identities ?? directIdentities }

    private var directIdentities: [String] = []
    /// Every child's identity in display order, sharing unchanged source leaves.
    public private(set) var orderedIdentities = HostLazyIdentitySequence()

    private var contentRevision = -1
    private var itemsRevision = -1
    private var positions: [String: Int] = [:]
    private var source: HostLazySource?
    private var prefetchPlan: (demand: Range<Double>, target: Range<Double>, perRun: Int, grid: Bool)?
    private var prefetchForward = true
    private var prefetchInvalidated = false
    private var lastDemand: Range<Double>?
    private var lastPerRun = 1
    /// Native hosts can hold optional work until the requested rows have been
    /// measured. The callback must not keep the native layout alive.
    public var prefetchReady: (() -> Bool)?
    /// Echoed by this lazy element's own render, independently of unrelated
    /// work still waiting elsewhere in the scene.
    private var requestedGeneration: Int?

    /// Content changes waiting for arrangement. Measurement and viewport realization must
    /// not consume this; the host clears it after beginning the changed arrangement.
    public var animatesChanges = false
    /// New source identities awaiting their first placement; recycled neighbours never enter here.
    public var inserting: Set<String> = []
    /// The source positions mounted, including the fixed neighbour window.
    public private(set) var built: Range<Int> = 0..<0
    /// Existing rows retained while their presentation is still moving.
    public private(set) var retained: Set<String> = []

    /// The last viewport and geometry asked for. Identical layout notices do
    /// not perform another range lookup or send another render.
    public var window: (span: Range<Double>, revision: Int, perRun: Int, realize: Range<Double>)?

    /// An incremental host stopped at an unmeasured run. Measure it before
    /// expanding the same window; an unchanged 44-point estimate still resumes.
    public private(set) var needsMeasurement = false

    /// A repeated native viewport must still resume invalidated optional work.
    public var needsWindowUpdate: Bool { needsMeasurement || prefetchInvalidated }

    /// Requested rows have finished their render. During a patch or a held
    /// transaction, a missing native row can still be waiting for that render.
    public var requestedItemsAreCurrent: Bool {
        guard let runtime, let element, element.handler(.realizedChanged) != nil else { return false }
        if orderedIdentities.isEmpty, requestedGeneration == nil { return true }
        guard let requestedGeneration else { return false }
        return !runtime.intake.isApplying && element.lazyRequestGeneration == requestedGeneration
    }

    /// Diagnostic counts for the work a lazy window actually performs.
    public private(set) var requests = 0
    /// Viewport range lookups performed.
    public var searches = 0
    /// Native child measurements performed.
    public var measurements = 0

    /// Viewport-origin correction not yet compensated by the mounted presentation frames.
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
    /// measured sizes of surviving identities; a row's own view revision
    /// determines whether its content needs a new measurement.
    @discardableResult
    public func takeItems() -> Bool {
        guard let element else { return false }
        let revision = element.lazyContentRevision
        let sourceRevision = element.lazyItemsRevision
        guard sourceRevision != itemsRevision || revision != contentRevision else { return false }
        contentRevision = revision
        // Identities arriving or leaving change what the window mounts and
        // which measurements survive. A content revision bump alone changes
        // neither; the patched children re-measure on their next layout pass.
        if sourceRevision != itemsRevision {
            cancelPrefetch()
            requestedGeneration = nil
            let wasKnown = itemsRevision >= 0
            itemsRevision = sourceRevision
            if let next = element.lazyRows {
                let follows = source.map { next.predecessor == ObjectIdentifier($0) } ?? false
                if wasKnown {
                    if follows {
                        switch next.edit {
                        case .replace(let before, let after):
                            if !before.isEmpty || !after.isEmpty { animatesChanges = true }
                        case .move(let range, _):
                            if !range.isEmpty { animatesChanges = true }
                        }
                    } else { animatesChanges = true }
                }
                if wasKnown {
                    if follows { inserting.formUnion(next.inserted) }
                    else { inserting.formUnion(next.sequence.filter { position(of: $0) == nil }) }
                }
                inserting = inserting.filter { next.position(of: $0) != nil }
                extents.adopt(next)
                source = next
                positions = [:]
                directIdentities = []
                orderedIdentities = next.sequence
                runs.adopt(next, perRun: lastPerRun)
                built = 0..<0
                window = nil
                needsMeasurement = false
            } else {
                // Direct host SPI users can still provide the .items property.
                let now = element.value(.items)?.strings ?? []
                if now != directIdentities || source != nil {
                    if wasKnown { animatesChanges = true }
                    let next = Dictionary(now.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
                    if wasKnown { inserting.formUnion(next.keys.filter { position(of: $0) == nil }) }
                    inserting = inserting.filter { next[$0] != nil }
                    extents.keep(identities: Set(next.keys))
                    positions = next
                    extents.adopt(positions: positions)
                    directIdentities = now
                    orderedIdentities = HostLazyIdentitySequence(now)
                    source = nil
                    built = 0..<0
                    window = nil
                    needsMeasurement = false
                    runs.resetSource()
                }
            }
        }
        if orderedIdentities.isEmpty {
            anchor = nil
            anchorShift = 0
            retained = []
        }
        return true
    }

    /// The place `identity` shows at; nil where it is none of them.
    public func position(of identity: String) -> Int? {
        source?.position(of: identity) ?? positions[identity]
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
                  let place = position(of: child.lazyIdentity ?? identity) else { return nil }
            return (place, child)
        }
        .sorted { $0.0 < $1.0 }
    }

    /// Where `place`'s child begins on the run, counting the padding head.
    public func offset(of place: Int) -> Double {
        extents.offset(of: place, in: orderedIdentities)
    }

    /// The places standing in `span` - `from` to `to` on the run - widened by
    /// `overscan` at both ends.
    public func places(in span: Range<Double>, overscan: Double) -> Range<Int> {
        extents.places(in: span, overscan: overscan, in: orderedIdentities)
    }

    /// The whole run's length, both paddings in.
    public var total: Double {
        extents.total(in: orderedIdentities)
    }

    /// Reads a viewport only when it or the content geometry changed. Shared
    /// by every host's stack and grid, including empty and clipped windows.
    /// `span` describes the actual anchor. `demand` can prepare a program jump;
    /// with `prefetch`, the rest of `realize` is optional work for later frames.
    public func show(_ span: Range<Double>, perRun: Int = 1, grid: Bool = false, realize: Range<Double>? = nil,
                     measureBeforeExpanding: Bool = false, keeping: Set<String> = [],
                     prefetch: Bool = false, demand: Range<Double>? = nil) {
        let identities = orderedIdentities
        let perRun = max(1, perRun)
        lastPerRun = perRun
        if grid { runs.group(perRun: perRun, items: identities.count) }
        let revision = grid ? runs.revision : extents.revision
        let realize = realize ?? span
        let keeping = keeping.filter { position(of: $0) != nil }
        guard window?.span != span || window?.revision != revision || window?.perRun != perRun
            || window?.realize != realize || needsMeasurement || retained != keeping
            || prefetch && prefetchInvalidated else { return }
        let moved = window?.revision == revision && window?.span != span
        prefetchInvalidated = false
        let nextDemand = demand ?? span
        if let previous = lastDemand, nextDemand != previous {
            prefetchForward = nextDemand.lowerBound >= previous.lowerBound
        }
        lastDemand = nextDemand
        window = (span, revision, perRun, realize)
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
        guard let element else { return }
        var lower = min(identities.count, max(0, wanted.lowerBound - 1) * perRun)
        var upper = min(identities.count, (wanted.upperBound + 1) * perRun)
        let requestedUpper = upper
        needsMeasurement = false
        if measureBeforeExpanding, !wanted.isEmpty {
            // The estimate describes scroll room, not permission to build an
            // entire set of potentially tall cards. Include one unknown run,
            // let its native measurement correct the range, then continue.
            for run in (lower / perRun)..<((upper + perRun - 1) / perRun) {
                let known = grid ? runs.hasMeasurement(for: run)
                    : extents.hasMeasurement(for: identities[run])
                if !known {
                    let end = min(identities.count, (run + 1) * perRun)
                    needsMeasurement = end < upper
                    upper = end
                    break
                }
            }
            // Keep surviving native seats within this window attached while
            // learning an inserted row's size. A partial fill must not briefly
            // evict a focused control and recreate it on the following fill.
            for child in element.children {
                guard case .manual(let identity) = child.id,
                      let place = position(of: child.lazyIdentity ?? identity),
                      place >= lower, place < requestedUpper else { continue }
                upper = max(upper, min(requestedUpper, (place / perRun + 1) * perRun))
            }
            needsMeasurement = upper < requestedUpper
        }
        if prefetch, !measureBeforeExpanding {
            let visible = requestedRange(in: demand ?? span, perRun: perRun, grid: grid)
            let target = !wanted.isEmpty && lower < upper ? lower..<upper : 0..<0
            var within = visible
            let start = max(built.lowerBound, target.lowerBound)
            let held = start..<max(start, min(built.upperBound, target.upperBound))
            // Keep only contiguous, bounded neighbours, never the intervening
            // document after a jump to a distant viewport.
            if !held.isEmpty, !visible.isEmpty,
               held.lowerBound <= visible.upperBound, visible.lowerBound <= held.upperBound {
                within = min(held.lowerBound, visible.lowerBound)..<max(held.upperBound, visible.upperBound)
            }
            // A window the mounted rows do not cover is the window the next frame
            // stands in - a jump, or a fling past what is built. Every place of it
            // is asked for now: a place left to the optional work paints a gap for
            // as long as that work takes, and a frame on a moving scroller has not
            // the time. Only a window already covered is narrowed to the demand,
            // with the rows around it left standing where they are.
            if !target.isEmpty, target.lowerBound < built.lowerBound || target.upperBound > built.upperBound {
                within = target
            }
            lower = within.lowerBound
            upper = within.upperBound
            if !visible.isEmpty, within != target, element.handler(.realizedChanged) != nil {
                prefetchPlan = (demand ?? span, realize, perRun, grid)
            } else { cancelPrefetch(invalidate: false) }
        } else { cancelPrefetch(invalidate: false) }
        let within = lower < upper && !wanted.isEmpty ? lower..<upper : 0..<0
        if !needsMeasurement { inserting.formIntersection(identities[within]) }
        request(within, keeping: keeping)
        // The visible request is always dispatched before optional neighbours.
        if prefetchPlan != nil {
            runtime?.lazyPrefetch.schedule(owner: self, ready: { [weak self] in
                guard let self, self.requestedItemsAreCurrent else { return false }
                return self.prefetchReady?() ?? true
            }) { [weak self] in self?.prefetchOne() ?? false }
        }
    }

    private func requestedRange(in span: Range<Double>, perRun: Int, grid: Bool) -> Range<Int> {
        let identities = orderedIdentities
        let count = (identities.count + perRun - 1) / perRun
        let places = grid ? runs.places(in: span, overscan: 0, count: count)
            : extents.places(in: span, overscan: 0, in: identities)
        guard !places.isEmpty else { return 0..<0 }
        let lower = min(identities.count, max(0, places.lowerBound - 1) * perRun)
        return lower..<min(identities.count, (places.upperBound + 1) * perRun)
    }

    /// Stops optional work when the source or the native presentation disappears.
    public func cancelPrefetch(invalidate: Bool = true) {
        prefetchPlan = nil
        if invalidate { prefetchInvalidated = true }
        runtime?.lazyPrefetch.cancel(owner: self)
    }

    private func prefetchOne() -> Bool {
        guard let plan = prefetchPlan, !built.isEmpty else { return false }
        guard requestedItemsAreCurrent else { return true }
        let target = requestedRange(in: plan.target, perRun: plan.perRun, grid: plan.grid)
        guard !target.isEmpty else { prefetchPlan = nil; return false }
        var lower = max(built.lowerBound, target.lowerBound)
        var upper = min(built.upperBound, target.upperBound)
        guard lower < upper else { prefetchPlan = nil; return false }
        // One indivisible run, not one run per frame: the queue checks its
        // deadline and native readiness again before adding the next run.
        let batch = plan.perRun
        if prefetchForward, upper < target.upperBound || lower == target.lowerBound {
            upper = min(target.upperBound, upper + batch)
        } else if lower > target.lowerBound {
            lower = max(target.lowerBound, lower - batch)
        } else {
            upper = min(target.upperBound, upper + batch)
        }
        let within = lower..<upper
        request(within, keeping: retained)
        let more = within != target
        if !more { prefetchPlan = nil }
        return more
    }

    private func request(_ within: Range<Int>, keeping: Set<String>) {
        let identities = orderedIdentities
        guard let element, let runtime, within != built || retained != keeping else { return }
        if !inserting.isDisjoint(with: identities[within]) { animatesChanges = true }
        built = within
        retained = keeping
        requests += 1
        Self.realizing = true
        // Retain actual moving rows, not all unbuilt rows between their old
        // and new positions. This keeps the window lazy during a large insertion.
        let extra = keeping.compactMap { position(of: $0) }.filter { !within.contains($0) }
        let requested = (Array(within) + extra).sorted().map { identities[$0] }
        let generation = nextRequestGeneration(for: element)
        element.send(.realizedChanged, [.strings(requested), .number(Double(generation))], in: runtime)
    }

    private func nextRequestGeneration(for element: MountedElement) -> Int {
        let previous = max(requestedGeneration ?? 0, element.lazyRequestGeneration)
        // The transport carries this lane as Double, so keep every generation exact.
        let generation = previous >= 9_007_199_254_740_991 ? 1 : previous + 1
        requestedGeneration = generation
        return generation
    }

    /// The corrected viewport origin after measurements or data move its anchor.
    /// A viewport at the end stays at the end. Hosts apply this absolute origin
    /// because their native scroller may already have clamped a shrinking document.
    public func correctedOrigin(perRun: Int = 1, grid: Bool = false) -> Double? {
        let identities = orderedIdentities
        guard let held = anchor, !identities.isEmpty else { return nil }
        let place = position(of: held.identity) ?? min(held.place, identities.count - 1)
        let start = grid
            ? runs.offset(of: place / perRun, count: (identities.count + perRun - 1) / perRun)
            : extents.offset(of: place, in: identities)
        let total = grid
            ? runs.total(count: (identities.count + perRun - 1) / perRun)
            : extents.total(in: identities)
        // Deleting the anchor or shortening the document can put the requested
        // origin beyond the native scroll reach. Compensate only the offset
        // the scroller can actually apply, not an unreachable presentation shift.
        let reach = max(0, total - held.viewport)
        let origin = min(reach, max(0, held.trailing ? reach : start + held.inset))
        anchorShift += origin - held.origin
        anchor = (identities[place], place, held.inset, origin, held.viewport, held.trailing)
        return abs(origin - held.origin) > 0.0001 ? origin : nil
    }

    /// Without a scroller there is no viewport to narrow by.
    public func tellAll() {
        cancelPrefetch()
        let identities = orderedIdentities
        guard let element, let runtime, built != 0..<identities.count else { return }
        if !inserting.isEmpty { animatesChanges = true }
        built = 0..<identities.count
        retained = []
        needsMeasurement = false
        // The window is re-asked, not kept: a run that told the tree to build every row
        // because no scroller clipped it - a first mount, a re-parenting - narrows back to
        // the window its scroller names the moment one does. A kept window standing for the
        // same span would leave every row of the source built for good, and every later
        // patch, hover and row measure costing what the whole source costs.
        window = nil
        requests += 1
        let generation = nextRequestGeneration(for: element)
        element.send(.realizedChanged, [.strings(Array(identities)), .number(Double(generation))], in: runtime)
    }

}

/// Measured child extents; each place not yet measured stands at 44.
/// The host invalidates measurements when the source or its cross-axis size changes.
@_spi(Host) public struct LazyExtents: Sendable {
    /// The spacing between adjacent children or runs.
    public var spacing: Double? = nil {
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
    private var sums = LazyExtentTree()
    private var source: HostLazySource?

    // Internal structural checks used by regression tests, without runtime logging.
    var storageNodes: Int { sums.storageNodes }

    /// Starts with a provisional extent until the first window is measured.
    public init() {}

    /// A complete child measurement. Zero is a valid size.
    public mutating func measure(_ identity: String, extent: Double) {
        guard extent.isFinite, extent >= 0, measured[identity] != extent else { return }
        let before = measured[identity]
        let previous = before ?? estimate
        measured[identity] = extent
        if let place = source?.position(of: identity) ?? index[identity] { sums.measure(place, extent: extent) }
        if extent != previous { revision += 1 }
    }

    /// Reordering invalidates positions even when every identity survives; `adopt` follows.
    public mutating func keep(identities: Set<String>) {
        measured = measured.filter { identities.contains($0.key) }
        index = [:]
        source = nil
        sums = LazyExtentTree()
        revision += 1
    }

    /// Takes the places the identities stand at, summing what is measured over them.
    public mutating func adopt(positions: [String: Int]) {
        source = nil
        index = positions
        var ordered = Array(repeating: Optional<Double>.none, count: positions.count)
        for (identity, extent) in measured {
            if let place = positions[identity] { ordered[place] = extent }
        }
        sums = LazyExtentTree(ordered) { $0 }
    }

    /// Applies the source's local edit without re-summing surviving measurements.
    /// A skipped snapshot or a raw SPI source has no applicable edit: rebuild once.
    public mutating func adopt(_ next: HostLazySource) {
        guard source !== next else { return }
        if let source, next.predecessor == ObjectIdentifier(source) {
            switch next.edit {
            case .replace(let before, let after):
                let allNew = after.count == next.inserted.count
                    && next.inserted.allSatisfy { measured[$0] == nil }
                let replacement = allNew ? LazyExtentTree(count: after.count)
                    : LazyExtentTree(next.sequence[after], measurement: { measured[$0] })
                sums.replace(before, with: replacement)
            case .move(let range, let destination):
                sums.move(range, to: destination)
            }
            for identity in next.removed { measured[identity] = nil }
        } else {
            measured = measured.filter { next.position(of: $0.key) != nil }
            sums = measured.isEmpty ? LazyExtentTree(count: next.sequence.count)
                : LazyExtentTree(next.sequence, measurement: { measured[$0] })
        }
        source = next
        index = [:]
        revision += 1
    }

    /// Forget sizes that were measured under a different layout proposal.
    public mutating func reset() {
        measured = [:]
        sums = LazyExtentTree(count: source?.sequence.count ?? index.count)
        revision += 1
    }

    /// The measured child extent, or the current estimate.
    public func extent(of identity: String) -> Double {
        measured[identity] ?? estimate
    }

    /// Whether this child's estimate has been replaced by a native measurement.
    public func hasMeasurement(for identity: String) -> Bool { measured[identity] != nil }

    private var gap: Double { spacing ?? StackArithmetic.automaticSpacing }

    private mutating func sync<Identities: RandomAccessCollection>(_ identities: Identities)
        where Identities.Element == String, Identities.Index == Int {
        if let source, source.sequence.count == identities.count { return }
        guard index.count != identities.count else { return }
        adopt(positions: Dictionary(identities.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first }))
    }

    /// Where `place` begins: the extents before it, measured or estimated, and a gap after each. O(log n).
    public mutating func offset<Identities: RandomAccessCollection>(of place: Int, in identities: Identities) -> Double
        where Identities.Element == String, Identities.Index == Int {
        sync(identities)
        let count = identities.count, place = max(0, min(place, count))
        let known = sums.before(place)
        let gaps = count == 0 ? 0 : (place == count ? count - 1 : place)
        return padding.head + known.extent + estimate * Double(place - known.count) + Double(gaps) * gap
    }

    /// Estimated length of the entire data source, including both paddings.
    public mutating func total<Identities: RandomAccessCollection>(in identities: Identities) -> Double
        where Identities.Element == String, Identities.Index == Int {
        guard identities.count > 0 else { return padding.head + padding.tail }
        return offset(of: identities.count, in: identities) + padding.tail
    }

    /// Only actual intersections count as visible; spacing is not a child. O(log² n).
    public mutating func places<Identities: RandomAccessCollection>(
        in span: Range<Double>, overscan: Double, in identities: Identities
    ) -> Range<Int> where Identities.Element == String, Identities.Index == Int {
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
    private var sums = LazyExtentTree()
    private var source: HostLazySource?
    private var sourcePerRun = 1

    /// Starts with a provisional extent until the first window is measured.
    public init() {}

    /// A complete run, measured as the largest of its current cells. Zero is a valid size.
    public mutating func measure(_ run: Int, extent: Double) {
        guard run >= 0, extent.isFinite, extent >= 0, sums.extent(at: run) != extent else { return }
        let previous = sums.extent(at: run) ?? estimate
        if run >= sums.count {
            sums.replace(sums.count..<sums.count, with: LazyExtentTree(count: run + 1 - sums.count))
        }
        sums.measure(run, extent: extent)
        if extent != previous { revision += 1 }
    }

    /// Forget sizes that were measured under a different layout proposal.
    public mutating func reset() {
        sums = LazyExtentTree(count: sums.count)
        revision += 1
    }

    mutating func resetSource() {
        source = nil
        reset()
    }

    /// The measured run extent, or the current estimate.
    public func extent(of run: Int) -> Double { sums.extent(at: run) ?? estimate }

    /// Whether this complete grid run has been measured.
    public func hasMeasurement(for run: Int) -> Bool { sums.extent(at: run) != nil }

    mutating func group(perRun: Int, items: Int) {
        guard perRun != sourcePerRun else { return }
        sourcePerRun = perRun
        sums = LazyExtentTree(count: (items + perRun - 1) / perRun)
        revision += 1
    }

    /// Aligned edits preserve unaffected grid runs. An edit changing how cells
    /// group invalidates only the suffix starting at its first affected run.
    public mutating func adopt(_ next: HostLazySource, perRun: Int) {
        let perRun = max(1, perRun)
        let count = (next.sequence.count + perRun - 1) / perRun
        if let source, next.predecessor == ObjectIdentifier(source), sourcePerRun == perRun {
            switch next.edit {
            case .replace(let before, let after):
                let first = before.lowerBound / perRun
                if (after.count - before.count).isMultiple(of: perRun) {
                    let end = min(sums.count, (before.upperBound + perRun - 1) / perRun)
                    let newEnd = min(count, (after.upperBound + perRun - 1) / perRun)
                    sums.replace(first..<end, with: LazyExtentTree(count: newEnd - first))
                } else {
                    sums.replace(first..<sums.count, with: LazyExtentTree(count: count - first))
                }
            case .move(let range, let destination):
                if range.lowerBound.isMultiple(of: perRun), range.upperBound.isMultiple(of: perRun),
                   destination.isMultiple(of: perRun) {
                    sums.move((range.lowerBound / perRun)..<(range.upperBound / perRun), to: destination / perRun)
                } else {
                    let first = min(range.lowerBound, destination) / perRun
                    sums.replace(first..<sums.count, with: LazyExtentTree(count: count - first))
                }
            }
        } else { sums = LazyExtentTree(count: count) }
        source = next
        sourcePerRun = perRun
        revision += 1
    }

    /// Where run `place` begins: the extents before it and a gap after each. O(log n).
    public mutating func offset(of place: Int, count: Int) -> Double {
        // Speculative track counts must not truncate committed measurements.
        // Places beyond the stored sequence are already covered by the estimate.
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
