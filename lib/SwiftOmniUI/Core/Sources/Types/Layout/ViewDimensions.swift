// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// View dimensions: the sizes an alignment guide's closure may read. The
// closure runs as the view describes, before the host has measured it, so a
// guide that reads them sees a view of no size - one that names a constant,
/// the ordinary case, places exactly.
// Design: docs/design/types/placement.md#alignment-guides

/// The dimensions an `.alignmentGuide` closure may read.
///
/// The closure runs as the view describes, ahead of the host's measurement:
/// `width` and `height` read 0 here, and a guide read off them answers the
/// view's own. A guide that wants the measured size is better written as a
/// constant the view knows, or recomputed from a state a frame report feeds.
public struct ViewDimensions: Equatable, Sendable {
    /// The view's width; 0 while it is undescribed and unmeasured.
    public var width: Double

    /// The view's height; 0 while it is undescribed and unmeasured.
    public var height: Double

    /// Measured answers a host populated - an explicit `.alignmentGuide`
    /// value or a baseline, by the alignment's axis slot; empty while the
    /// view is undescribed or the host has none for it.
    var guides: [Int32: Double] = [:]

    /// Which of `guides` came from `.alignmentGuide` writes rather than the
    /// host's own measure - what `subscript(explicit:)` answers for.
    var explicitSlots: Set<Int32> = []

    /// Dimensions of the given size.
    public init(width: Double = 0, height: Double = 0) {
        self.width = width
        self.height = height
    }

    /// Dimensions of the size and guide answers measured - what
    /// `LayoutSubview.dimensions(in:)` answers with.
    @_spi(Host) public init(
        width: Double, height: Double,
        guides: [Int32: Double], explicitSlots: Set<Int32> = []
    ) {
        self.width = width
        self.height = height
        self.guides = guides
        self.explicitSlots = explicitSlots
    }

    /// The guide's place in a view this size: an explicit value where one was
    /// written, else the leading edge, the middle, or the trailing edge.
    public subscript(guide: HorizontalAlignment) -> Double {
        if let answer = guides[guide.axis.rawValue] { return answer }
        switch guide.axis {
        case .start: return 0
        case .center: return width / 2
        default: return width
        }
    }

    /// The guide's place in a view this size: an explicit value or a measured
    /// baseline where the host answered one, else the top edge, the middle,
    /// or the bottom edge.
    public subscript(guide: VerticalAlignment) -> Double {
        if let answer = guides[guide.axis.rawValue] { return answer }
        switch guide.axis {
        case .start: return 0
        case .center: return height / 2
        default: return height
        }
    }

    /// An explicit guide written with `.alignmentGuide`; nil where none was.
    public subscript(explicit guide: HorizontalAlignment) -> Double? {
        explicitSlots.contains(guide.axis.rawValue) ? guides[guide.axis.rawValue] : nil
    }

    /// An explicit guide written with `.alignmentGuide`; nil where none was.
    public subscript(explicit guide: VerticalAlignment) -> Double? {
        explicitSlots.contains(guide.axis.rawValue) ? guides[guide.axis.rawValue] : nil
    }
}
