// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore

/// A width and a height, in points.
@_spi(Host) public struct LayoutSize: Equatable, Sendable {
    /// How wide.
    public var width: Double

    /// How tall.
    public var height: Double

    /// A size `width` wide and `height` tall.
    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    /// No room at all.
    public static let zero = LayoutSize(width: 0, height: 0)
}

/// What a layout reads of one child: its margin, alignments, stated sizes and place in a grid or a ZStack.
/// Design: docs/design/host/layout.md#the-layout-arithmetic
@_spi(Host) public struct LayoutValues: Equatable, Sendable {
    /// The space kept around the child, outside it.
    public var margin = EdgeInsets(0)

    /// The least extent a flexible child takes along its stack's axis, sharing the room left over;
    /// nil for a child that takes its natural size.
    public var flex: Double?

    /// A scroller takes a viewport along these axes; its document's natural
    /// extent is not a minimum size for the enclosing layout.
    public var scrollAxes = Axis.neither

    /// Axes on which this child or its content accepts the remaining proposal.
    public var expandingAxes = Axis.neither

    /// The sole child of a frame, measured with the frame's proposal.
    public var isFrameContent = false

    /// A background or overlay draws in the base's room without sizing it.
    public var isLayoutDecoration = false

    /// Across its slot: 0 start, 1 centre, 2 end, 3 fill.
    public var horizontal: Int32 = 3

    /// Down its slot: 0 start, 1 centre, 2 end, 3 fill.
    public var vertical: Int32 = 3

    /// The width the child states for itself.
    public var width: Double?

    /// The height the child states for itself.
    public var height: Double?

    /// The least width the child takes.
    public var minimumWidth: Double?

    /// The least height the child takes.
    public var minimumHeight: Double?

    /// The most width the child takes.
    public var maximumWidth: Double?

    /// The most height the child takes.
    public var maximumHeight: Double?

    /// The grid row the child starts in.
    public var row = 0

    /// The grid column the child starts in.
    public var column = 0

    /// How many grid rows the child spans.
    public var rowSpan = 1

    /// How many grid columns the child spans.
    public var columnSpan = 1

    /// The part of a ZStack's room the child stands in; the whole room where it names none.
    public var area: Area?

    /// How loudly the child asks for its natural size when the room runs
    /// short - a higher one keeps its size while lower ones give theirs up.
    public var priority: Double = 0

    /// The horizontal alignment slot the child overrides, and the point in
    /// its own frame it aligns by where that alignment is asked for.
    public var horizontalGuide: AlignmentGuide?

    /// The vertical alignment slot the child overrides, and the point in
    /// its own frame it aligns by where that alignment is asked for.
    public var verticalGuide: AlignmentGuide?

    /// Values with every part at its default.
    public init() {}

    /// The width a child is measured at for the width its layout offers: its stated width, within its bounds and the
    /// offer - the width it is placed at, so its words wrap to it - else the smaller of the offer and its most width.
    /// A frame's content keeps an explicit width even when it exceeds the outer frame.
    /// Design: docs/design/host/layout.md#a-child-measured
    public func offer(_ width: Double?) -> Double? {
        if let stated = self.width { return boundedWidth(stated, available: isFrameContent ? nil : width) }
        return [width, maximumWidth].compactMap { $0 }.min()
    }

    /// A child's size from what it measured: a stated width or height before the measured one, each within its
    /// bounds. A bound without a stated size makes the child take what it is offered up to the bound - the way a
    /// SwiftUI `frame(maxWidth:)` fills its proposal - the measured size answering where nothing was offered.
    public func sized(_ measured: LayoutSize, offered width: Double? = nil) -> LayoutSize {
        LayoutSize(
            width: boundedWidth(extent(self.width, measured: measured.width, offered: width,
                                       bound: (minimumWidth != nil || maximumWidth != nil),
                                       scrolled: scrollAxes == .horizontal || scrollAxes == .both)),
            height: boundedHeight(extent(self.height, measured: measured.height, offered: nil,
                                         bound: (minimumHeight != nil || maximumHeight != nil),
                                         scrolled: scrollAxes == .vertical || scrollAxes == .both)))
    }

    /// `proposed`, held within the child's least and most width and the room `available`.
    public func boundedWidth(_ proposed: Double, available: Double? = nil) -> Double {
        Extent.bounded(proposed, minimum: minimumWidth, maximum: maximumWidth, available: available)
    }

    /// `proposed`, held within the child's least and most height and the room `available`.
    public func boundedHeight(_ proposed: Double, available: Double? = nil) -> Double {
        Extent.bounded(proposed, minimum: minimumHeight, maximum: maximumHeight, available: available)
    }

    /// One axis of `sized`: a stated size wins. A scroller accepts a finite
    /// viewport proposal, but its document supplies no ideal extent along
    /// that axis when the proposal is unbounded.
    private func extent(
        _ stated: Double?, measured: Double, offered: Double?, bound: Bool, scrolled: Bool
    ) -> Double {
        if let stated { return stated }
        if scrolled {
            guard let offered, offered.isFinite else { return 0 }
            return max(0, offered)
        }
        guard bound, let offered, offered.isFinite else { return measured }
        return offered
    }
}

/// One alignment's answer a child overrides: the slot it answers for and the
/// point in its own frame that lands on the alignment's place - what
/// `.alignmentGuide` writes.
@_spi(Host) public struct AlignmentGuide: Equatable, Sendable {
    /// The alignment's axis case - 0 start, 1 centre, 2 end, 4 and 5 the baselines.
    public var slot: Int32

    /// The point in the child's own frame, from its near edge.
    public var offset: Double

    /// A guide for `slot` standing `offset` into the child.
    public init(slot: Int32, offset: Double) {
        self.slot = slot
        self.offset = offset
    }
}

/// A child as the layout arithmetic sees it; a toolkit's child measures its own view.
@_spi(Host) @MainActor public protocol LayoutChild {
    /// What the layout reads of the child.
    var values: LayoutValues { get }

    /// Whether the child is shown; a hidden child takes no room.
    var isShown: Bool { get }

    /// The child's own size for the width offered to it, its margin already taken out - the layout owns the
    /// margin, both ways; its stated sizes and bounds applied.
    func size(offered width: Double?) -> LayoutSize

    /// The child's first text baseline measured from its top, where it has one;
    /// nil for a child with no text to stand on.
    var firstBaseline: Double? { get }

    /// The child's last text baseline measured from its top, where it has one.
    var lastBaseline: Double? { get }
}

extension LayoutChild {
    /// No baseline: a child that keeps silent about one aligns by its edges.
    public var firstBaseline: Double? { nil }

    /// No baseline.
    public var lastBaseline: Double? { nil }
}

/// The arithmetic of one child's extent and place along one axis of its slot.
/// Design: docs/design/host/layout.md#one-axis-of-a-slot
@_spi(Host) public enum Extent {
    /// `proposed` within `minimum`, `maximum` and the room `available`; the minimum wins a contradiction.
    public static func bounded(_ proposed: Double, minimum: Double?, maximum: Double?, available: Double? = nil) -> Double {
        let lower = max(0, minimum ?? 0)
        let upper = max(lower, maximum ?? .greatestFiniteMagnitude)
        let finite = proposed.isFinite ? proposed : lower
        var result = max(min(max(0, finite), upper), lower)
        if let available, available.isFinite { result = min(result, max(0, available)) }
        return result
    }

    /// A child's extent in its slot: a stated size wins; then a bound child takes the slot within its bounds - a
    /// `frame(maxWidth:)` fills up to the bound, the child's own size only centring its content - a filling child
    /// takes the slot, any other its natural size.
    public static func of(
        option: Int32,
        stated: Double?,
        natural: Double,
        available: Double,
        minimum: Double? = nil,
        maximum: Double? = nil,
        allowsOverflow: Bool = false
    ) -> Double {
        if let stated {
            return bounded(stated, minimum: minimum, maximum: maximum,
                           available: allowsOverflow ? nil : available)
        }

        if (minimum != nil || maximum != nil) && available.isFinite {
            return bounded(available, minimum: minimum, maximum: maximum)
        }

        return bounded(option == 3 ? available : natural, minimum: minimum, maximum: maximum, available: available)
    }

    /// Where a child of `extent` starts in its slot; a filling child that stops short stands in the middle.
    public static func start(
        option: Int32, extent: Double, start: Double, available: Double, allowsOverflow: Bool = false
    ) -> Double {
        let remaining = allowsOverflow ? available - extent : max(0, available - extent)
        switch option {
        case 1, 3: return start + remaining / 2
        case 2: return start + remaining
        default: return start
        }
    }

    /// Where a child's alignment point stands in its slot: the alignment's
    /// place on the child - 0 at its near edge, its middle, its far edge - or
    /// `guide` where `.alignmentGuide` named one, landed on the point the
    /// alignment means in the slot.
    public static func start(
        option: Int32, extent: Double, start: Double, available: Double, guide: Double?
    ) -> Double {
        guard let guide else { return Self.start(option: option, extent: extent, start: start, available: available) }
        let point: Double
        switch option {
        case 1, 3: point = start + available / 2
        case 2: point = start + available
        default: point = start
        }
        return point - guide
    }
}

/// The sizes one view measured, by the width its parent offered, kept until something changes them.
/// Design: docs/design/host/layout.md#measured-once
@_spi(Host) @MainActor public final class MeasurementCache {
    private var sizes: [(width: Double?, size: LayoutSize)] = []
    /// Changes when a native or content update invalidates the cached sizes.
    public private(set) var revision = 0

    /// A cache holding nothing yet.
    public init() {}

    public func cachedSize(offering width: Double?) -> LayoutSize? {
        sizes.first { $0.width == width }?.size
    }

    /// The size measured for `width`, measuring only when none is kept.
    public func size(offering width: Double?, measure: () -> LayoutSize) -> LayoutSize {
        if let kept = sizes.first(where: { $0.width == width }) { return kept.size }

        let startedAt = revision
        let measured = measure()
        // Native feedback can invalidate this cache during the query. Do not
        // retain a result produced from the previous layout revision.
        guard revision == startedAt else { return measured }
        if sizes.count == Self.capacity { sizes.removeFirst() }
        sizes.append((width, measured))
        return measured
    }

    /// Forgets every kept size.
    public func invalidate() {
        sizes.removeAll(keepingCapacity: true)
        revision += 1
    }

    /// Publish a completed native preparation without recomputing its arithmetic.
    /// A changed answer invalidates speculative answers at other proposals.
    @discardableResult
    public func store(_ size: LayoutSize, offering width: Double?) -> Bool {
        let changed = sizes.contains { $0.width == width && $0.size != size }
        if changed { invalidate() }
        sizes.removeAll { $0.width == width }
        if sizes.count == Self.capacity { sizes.removeFirst() }
        sizes.append((width, size))
        return changed
    }

    /// A parent offers a view one or two widths in a pass: its natural width and the width it lays it out in.
    private static let capacity = 4
}
