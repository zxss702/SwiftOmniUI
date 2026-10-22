// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore

/// A stack's arithmetic: its shown children one after another along one axis.
/// Design: docs/design/host/layout.md#stacks
@_spi(Host) public enum StackArithmetic {
    /// The axis a stack runs along.
    public enum Axis: Sendable {
        /// Left to right.
        case horizontal

        /// Top to bottom.
        case vertical
    }

    /// The gap between two children where a stack states none.
    public static let automaticSpacing = 8.0

    /// The gap before each child; hidden children never interrupt adjacency.
    @MainActor
    public static func gaps<Child: LayoutChild>(
        of items: [Child], axis: Axis, spacing: Double?
    ) -> [Double] {
        var shownBefore = false
        return items.map { item in
            guard item.isShown else { return 0 }
            defer { shownBefore = true }
            return shownBefore ? spacing ?? automaticSpacing : 0
        }
    }

    /// The room a stack's shown children take, each measured once for the width offered.
    @MainActor
    public static func size<Child: LayoutChild>(
        of items: [Child], axis: Axis, spacing: Double?, padding: EdgeInsets, width offered: Double?
    ) -> LayoutSize {
        let visible = items.filter(\.isShown)
        let gaps = Self.gaps(of: visible, axis: axis, spacing: spacing).reduce(0, +)
        var along = 0.0
        var across = 0.0

        switch axis {
        case .vertical:
            let childWidth = offered.map { max(0, $0 - padding.left - padding.right) }
            for item in visible {
                let margin = item.values.margin
                let available = childWidth.map { max(0, $0 - margin.left - margin.right) }
                let size = item.size(offered: available)
                along += max(size.height, item.values.flex ?? 0) + margin.top + margin.bottom
                let scrollsAcross = item.values.scrollAxes == .horizontal || item.values.scrollAxes == .both
                let viewport = scrollsAcross && item.values.width == nil
                    ? item.values.boundedWidth(available ?? size.width, available: available) : size.width
                across = max(across, viewport + margin.left + margin.right)
            }
            return LayoutSize(
                width: padding.left + padding.right + across,
                height: padding.top + padding.bottom + gaps + along)

        case .horizontal:
            let ideal = visible.map { $0.size(offered: nil) }
            let available = offered.flatMap { $0.isFinite ? max(0, $0 - padding.left - padding.right) : nil }
            let widths = available.map {
                alongs(visible, naturals: ideal, axis: axis, spacing: spacing,
                       in: Rect(0, 0, $0, 0))
            }
            for (index, item) in visible.enumerated() {
                // A row's height belongs to the widths it actually gives its
                // children. In particular, a text column beside an icon and
                // Spacer must wrap during measurement, before placement.
                let size = widths.map { item.size(offered: $0[index]) } ?? ideal[index]
                let margin = item.values.margin
                along += (widths?[index] ?? max(size.width, item.values.flex ?? 0)) + margin.left + margin.right
                across = max(across, size.height + margin.top + margin.bottom)
            }
            return LayoutSize(
                width: padding.left + padding.right + gaps + along,
                height: padding.top + padding.bottom + across)
        }
    }

    /// Where each child stands in `bounds`, in order; nil for a hidden one. Right to left, the places
    /// are turned about the middle of `bounds`.
    @MainActor
    public static func places<Child: LayoutChild>(
        of items: [Child], axis: Axis, spacing: Double?, padding: EdgeInsets, in bounds: Rect,
        direction: LayoutDirection
    ) -> [Rect?] {
        leftToRight(of: items, axis: axis, spacing: spacing, padding: padding, in: bounds)
            .map { $0.map { direction.places($0, in: bounds) } }
    }

    /// The places as a layout written left to right has them.
    @MainActor
    private static func leftToRight<Child: LayoutChild>(
        of items: [Child], axis: Axis, spacing: Double?, padding: EdgeInsets, in bounds: Rect
    ) -> [Rect?] {
        let content = bounds.inset(padding)
        var naturals = items.map { item -> LayoutSize in
            guard item.isShown else { return .zero }
            let margin = item.values.margin
            let cross = axis == .vertical ? content.width : content.height
            return item.size(offered: axis == .vertical ? max(0, cross - margin.left - margin.right) : nil)
        }
        let extents = alongs(items, naturals: naturals, axis: axis, spacing: spacing, in: content)
        if axis == .horizontal {
            for index in items.indices where items[index].isShown {
                naturals[index] = items[index].size(offered: extents[index])
            }
        }

        // A baseline is a line the row shares: its place is the deepest
        // baseline any shown child asks for, each child landing its own on it.
        // Only the cross axis of a horizontal layout answers baseline slots.
        var baseline = 0.0
        if axis == .horizontal {
            baseline = content.y + (zip(items, naturals).map { item, natural -> Double in
                guard item.isShown, item.values.vertical == 4 || item.values.vertical == 5 else { return 0 }
                return guide(item.values.verticalGuide, in: item, natural: natural.height,
                             slot: item.values.vertical)
            }.max() ?? 0)
        }
        // The row or column stands centered in the room the children do not
        // take - the way SwiftUI's stacks stand, the flexible children's
        // shares already counted in `extents`.
        let gaps = Self.gaps(of: items, axis: axis, spacing: spacing)
        var taken = gaps.reduce(0, +)
        for (item, along) in zip(items, extents) where item.isShown {
            let margin = item.values.margin
            taken += along + (axis == .vertical ? margin.top + margin.bottom : margin.left + margin.right)
        }
        let leftover = (axis == .vertical ? content.height : content.width) - taken
        var offset = (axis == .vertical ? content.y : content.x) + max(0, leftover) / 2
        var index = 0

        return zip(items, zip(naturals, extents)).map { item, pair in
            let (natural, along) = pair
            let gap = gaps[index]
            index += 1
            guard item.isShown else { return nil }
            offset += gap
            let values = item.values
            let margin = values.margin

            switch axis {
            case .vertical:
                offset += margin.top
                let available = max(0, content.width - margin.left - margin.right)
                let expands = values.expandingAxes == .horizontal || values.expandingAxes == .both
                let width = Extent.of(
                    option: expands ? 3 : values.horizontal, stated: values.width, natural: natural.width,
                    available: available, minimum: values.minimumWidth, maximum: values.maximumWidth)
                let x = Extent.start(
                    option: values.horizontal, extent: width, start: content.x + margin.left,
                    available: available,
                    guide: values.horizontalGuide?.slot == values.horizontal
                        ? values.horizontalGuide?.offset : nil)
                let place = Rect(x: x, y: offset, width: width, height: along)
                offset += along + margin.bottom
                return place

            case .horizontal:
                offset += margin.left
                let available = max(0, content.height - margin.top - margin.bottom)
                let expands = values.expandingAxes == .vertical || values.expandingAxes == .both
                let height = Extent.of(
                    option: expands ? 3 : values.vertical, stated: values.height, natural: natural.height,
                    available: available, minimum: values.minimumHeight, maximum: values.maximumHeight)
                let y: Double
                if values.vertical == 4 || values.vertical == 5 {
                    y = baseline - guide(values.verticalGuide, in: item,
                                         natural: height, slot: values.vertical)
                } else {
                    y = Extent.start(
                        option: values.vertical, extent: height, start: content.y + margin.top,
                        available: available,
                        guide: values.verticalGuide?.slot == values.vertical
                            ? values.verticalGuide?.offset : nil)
                }
                let place = Rect(x: offset, y: y, width: along, height: height)
                offset += along + margin.right
                return place
            }
        }
    }

    /// Each shown child's extent along `axis`: flexible children accept the
    /// remaining room before intrinsic siblings give up their natural sizes.
    @MainActor
    private static func alongs<Child: LayoutChild>(
        _ items: [Child], naturals: [LayoutSize], axis: Axis, spacing: Double?, in content: Rect
    ) -> [Double] {
        let minima = items.map { item in
            let minimum = axis == .vertical ? item.values.minimumHeight : item.values.minimumWidth
            return max(max(0, minimum ?? 0), item.values.flex ?? 0)
        }
        let maxima = items.indices.map { index in
            let maximum = axis == .vertical ? items[index].values.maximumHeight : items[index].values.maximumWidth
            return max(minima[index], maximum ?? .greatestFiniteMagnitude)
        }
        let flexible = items.indices.filter { index in
            let values = items[index].values
            let stated = axis == .vertical ? values.height : values.width
            let scrolls = values.scrollAxes == .both
                || (axis == .vertical ? values.scrollAxes == .vertical : values.scrollAxes == .horizontal)
            let expands = values.expandingAxes == .both
                || (axis == .vertical ? values.expandingAxes == .vertical : values.expandingAxes == .horizontal)
            return items[index].isShown && stated == nil && (values.flex != nil || scrolls || expands)
        }
        let flexibleIndices = Set(flexible)
        var extents = items.indices.map { index -> Double in
            guard items[index].isShown else { return 0 }
            let values = items[index].values
            let stated = axis == .vertical ? values.height : values.width
            let natural = axis == .vertical ? naturals[index].height : naturals[index].width
            return Extent.bounded(stated ?? natural, minimum: minima[index], maximum: maxima[index])
        }
        var taken = gaps(of: items, axis: axis, spacing: spacing).reduce(0, +)
        for (item, extent) in zip(items, extents) where item.isShown {
            let margin = item.values.margin
            taken += extent + (axis == .vertical ? margin.top + margin.bottom : margin.left + margin.right)
        }
        let room = (axis == .vertical ? content.height : content.width) - taken

        // Each iteration either reaches the requested amount or removes at
        // least one child at its bound. A saturated child gives its unused
        // share to the remaining children in the same group.
        func distribute(_ indices: [Int], amount: Double, growing: Bool) -> Double {
            func capacity(_ index: Int) -> Double {
                growing ? maxima[index] - extents[index] : extents[index] - minima[index]
            }
            var active = indices.filter { capacity($0) > 0 }
            var remaining = amount
            while remaining > 0, !active.isEmpty {
                let share = remaining / Double(active.count)
                let saturated = active.filter { capacity($0) <= share }
                if saturated.isEmpty {
                    for index in active { extents[index] += growing ? share : -share }
                    return 0
                }
                for index in saturated {
                    remaining = max(0, remaining - capacity(index))
                    extents[index] = growing ? maxima[index] : minima[index]
                }
                active.removeAll { capacity($0) <= 0 }
            }
            return remaining
        }

        // For intrinsic horizontal children, share the available width rather
        // than subtracting an equal deficit from every ideal width. A short
        // label accepts its ideal size first and returns the unused share to
        // longer siblings. Equal subtraction erases markers beside paragraphs.
        func compressIntrinsicRow(_ indices: [Int], amount: Double) -> Double {
            let minimum = indices.reduce(0) { $0 + minima[$1] }
            let total = indices.reduce(0) { $0 + extents[$1] }
            var budget = max(minimum, total - amount)
            var active = indices
            while !active.isEmpty {
                let share = budget / Double(active.count)
                let constrained = active.filter { minima[$0] >= share }
                let satisfied = constrained.isEmpty ? active.filter { extents[$0] <= share } : constrained
                if satisfied.isEmpty {
                    for index in active { extents[index] = share }
                    break
                }
                for index in satisfied {
                    let extent = minima[index] >= share ? minima[index] : extents[index]
                    extents[index] = extent
                    budget -= extent
                }
                let removed = Set(satisfied)
                active.removeAll { removed.contains($0) }
            }
            return max(0, amount - (total - indices.reduce(0) { $0 + extents[$1] }))
        }

        // Lower priorities give up room first. Within one priority, an input,
        // scroller or spacer accepts a smaller slot before an intrinsic button
        // or label does. Explicit sizes and all declared minima remain intact.
        if room < 0 {
            let shown = items.indices.filter {
                items[$0].isShown
                    && (axis == .vertical ? items[$0].values.height == nil
                                          : items[$0].values.width == nil)
            }
            var deficit = -room
            for priority in Set(shown.map { items[$0].values.priority }).sorted() {
                guard deficit > 0 else { break }
                let group = shown.filter { items[$0].values.priority == priority }
                deficit = distribute(group.filter { flexibleIndices.contains($0) }, amount: deficit, growing: false)
                let intrinsic = group.filter { !flexibleIndices.contains($0) }
                deficit = axis == .horizontal
                    ? compressIntrinsicRow(intrinsic, amount: deficit)
                    : distribute(intrinsic, amount: deficit, growing: false)
            }
            return extents
        }

        if room > 0 { _ = distribute(flexible, amount: room, growing: true) }
        return extents
    }

    /// The point a child answers `slot` with: its explicit guide where
    /// `.alignmentGuide` named one for it, its measured baseline where the
    /// host reads one, its extent's far edge for a last baseline.
    @MainActor
    private static func guide<Child: LayoutChild>(
        _ explicit: AlignmentGuide?, in child: Child, natural: Double, slot: Int32
    ) -> Double {
        if let explicit, explicit.slot == slot { return explicit.offset }
        switch slot {
        case 4: return child.firstBaseline ?? natural
        case 5: return child.lastBaseline ?? natural
        default: return natural / 2
        }
    }
}

extension LayoutDirection {
    /// Where a place worked out left to right stands in `room` laid out this way: right to left, turned
    /// about the room's middle, so a row fills from the right and padding and margins swap sides.
    /// Design: docs/design/host/layout.md#right-to-left
    @_spi(Host) public func places(_ place: Rect, in room: Rect) -> Rect {
        guard self == .rightToLeft else { return place }
        return Rect(x: room.x + room.width - (place.x - room.x) - place.width, y: place.y,
                    width: place.width, height: place.height)
    }
}

extension Rect {
    /// This rectangle with `insets` taken off each side, never below no room.
    func inset(_ insets: EdgeInsets) -> Rect {
        Rect(
            x: x + insets.left,
            y: y + insets.top,
            width: max(0, width - insets.left - insets.right),
            height: max(0, height - insets.top - insets.bottom))
    }
}
