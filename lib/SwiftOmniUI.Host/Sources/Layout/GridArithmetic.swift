// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore

/// A grid's arithmetic: fixed, automatic and proportional tracks, and each shown child in its cells.
/// Design: docs/design/host/layout.md#grids
@_spi(Host) public enum GridArithmetic {
    /// The room the grid takes at its tracks' natural sizes. Where that is wider than the width offered, the
    /// columns share the offer as a placement would, and each row is as tall as its children at those widths.
    /// `flow` fills its columns with the items row first, an `.adaptive` one standing for as many as fit -
    /// the rows and columns it makes count themselves.
    @MainActor
    public static func size<Child: LayoutChild>(
        of items: [Child], rows: [GridLength], columns: [GridLength],
        rowSpacing: Double, columnSpacing: Double, padding: EdgeInsets, width offered: Double? = nil,
        flow: [GridItem] = []
    ) -> LayoutSize {
        if items.count == 1, let item = items.first, item.values.isFrameContent {
            return SingleChildArithmetic.size(of: item, padding: padding, width: offered)
        }
        let flowing = !flow.isEmpty
        let flowColumns = flowing ? resolvedFlow(flow, width: offered, spacing: columnSpacing) : []
        let columnCount = flowing ? max(flowColumns.count, 1)
            : counts(items, rows: rows, columns: columns).columns
        let rowCount = flowing ? max((items.count + columnCount - 1) / columnCount, rows.count)
            : counts(items, rows: rows, columns: columns).rows
        let cells = flowing ? flowCells(items.count, columns: columnCount) : nil
        let columnDefinitions = flowing ? flowColumns.map(\.track) : completed(columns, count: columnCount)
        let rowDefinitions = flowing
            ? completed(rows, count: rowCount, padding: .auto)
            : completed(rows, count: rowCount)
        var columnSizes = trackSizes(
            items, definitions: columnDefinitions, count: columnCount,
            available: nil, spacing: columnSpacing, vertical: false, cells: cells,
            limits: cells == nil ? nil : flowColumns.map(\.limits))
        let naturalWidth = padding.left + padding.right + columnSizes.reduce(0, +)
            + columnSpacing * Double(max(columnCount - 1, 0))

        let expandsAcross = items.contains { $0.isShown && !$0.values.isLayoutDecoration
            && ($0.values.flex != nil || $0.values.expandingAxes == .horizontal || $0.values.expandingAxes == .both) }
        if let offered, offered.isFinite, naturalWidth > offered || expandsAcross {
            columnSizes = trackSizes(
                items, definitions: columnDefinitions, count: columnCount,
                available: max(0, offered - padding.left - padding.right), spacing: columnSpacing,
                vertical: false, cells: cells,
                limits: cells == nil ? nil : flowColumns.map(\.limits))
        }
        let rowSizes = trackSizes(
            items, definitions: rowDefinitions, count: rowCount,
            available: nil, spacing: rowSpacing, vertical: true, columns: (columnSizes, columnSpacing),
            cells: cells)

        return LayoutSize(
            width: padding.left + padding.right + columnSizes.reduce(0, +)
                + columnSpacing * Double(max(columnCount - 1, 0)),
            height: padding.top + padding.bottom + rowSizes.reduce(0, +)
                + rowSpacing * Double(max(rowCount - 1, 0)))
    }

    /// Where each child stands in `bounds`, in order; nil for a hidden one. Right to left, column 0 is
    /// the rightmost. `flow` fills its columns with the items row first, an `.adaptive` one standing
    /// for as many as fit - the rows and columns it makes count themselves.
    @MainActor
    public static func places<Child: LayoutChild>(
        of items: [Child], rows: [GridLength], columns: [GridLength],
        rowSpacing: Double, columnSpacing: Double, padding: EdgeInsets, in bounds: Rect,
        direction: LayoutDirection, flow: [GridItem] = []
    ) -> [Rect?] {
        leftToRight(
            of: items, rows: rows, columns: columns, rowSpacing: rowSpacing,
            columnSpacing: columnSpacing, padding: padding, in: bounds, flow: flow)
            .map { $0.map { direction.places($0, in: bounds) } }
    }

    /// The places as a grid written left to right has them.
    @MainActor
    private static func leftToRight<Child: LayoutChild>(
        of items: [Child], rows: [GridLength], columns: [GridLength],
        rowSpacing: Double, columnSpacing: Double, padding: EdgeInsets, in bounds: Rect,
        flow: [GridItem] = []
    ) -> [Rect?] {
        let content = bounds.inset(padding)
        let flowing = !flow.isEmpty
        let flowColumns = flowing ? resolvedFlow(flow, width: content.width, spacing: columnSpacing) : []
        let columnCount = flowing ? max(flowColumns.count, 1)
            : counts(items, rows: rows, columns: columns).columns
        let rowCount = flowing ? max((items.count + columnCount - 1) / columnCount, rows.count)
            : counts(items, rows: rows, columns: columns).rows
        let cells = flowing ? flowCells(items.count, columns: columnCount) : nil
        let columnSizes = trackSizes(
            items,
            definitions: flowing ? flowColumns.map(\.track) : completed(columns, count: columnCount),
            count: columnCount, available: content.width, spacing: columnSpacing, vertical: false,
            cells: cells, limits: cells == nil ? nil : flowColumns.map(\.limits))
        let rowSizes = trackSizes(
            items,
            definitions: flowing
                ? completed(rows, count: rowCount, padding: .auto)
                : completed(rows, count: rowCount),
            count: rowCount, available: content.height, spacing: rowSpacing, vertical: true,
            columns: (columnSizes, columnSpacing), cells: cells)
        let rowOrigins = origins(of: rowSizes, start: content.y, spacing: rowSpacing)
        let columnOrigins = origins(of: columnSizes, start: content.x, spacing: columnSpacing)

        return items.enumerated().map { index, item in
            guard item.isShown else { return nil }
            let values = item.values
            let margin = values.margin
            let row = min(max(cells?[index].row ?? values.row, 0), rowCount - 1)
            let column = min(max(cells?[index].column ?? values.column, 0), columnCount - 1)
            let rowEnd = min(row + (cells != nil ? 1 : max(values.rowSpan, 1)), rowCount)
            let columnEnd = min(column + (cells != nil ? 1 : max(values.columnSpan, 1)), columnCount)
            let cellWidth = columnSizes[column..<columnEnd].reduce(0, +)
                + columnSpacing * Double(max(columnEnd - column - 1, 0))
            let cellHeight = rowSizes[row..<rowEnd].reduce(0, +)
                + rowSpacing * Double(max(rowEnd - row - 1, 0))
            let availableWidth = max(0, cellWidth - margin.left - margin.right)
            let availableHeight = max(0, cellHeight - margin.top - margin.bottom)
            let natural = item.size(offered: availableWidth)
            let expandsAcross = values.flex != nil || values.expandingAxes == .horizontal || values.expandingAxes == .both
            let expandsDown = values.flex != nil || values.expandingAxes == .vertical || values.expandingAxes == .both
            let width = Extent.of(
                option: expandsAcross ? 3 : values.horizontal, stated: values.width, natural: natural.width,
                available: availableWidth, minimum: values.minimumWidth, maximum: values.maximumWidth)
            let height = Extent.of(
                option: expandsDown ? 3 : values.vertical, stated: values.height, natural: natural.height,
                available: availableHeight, minimum: values.minimumHeight, maximum: values.maximumHeight)

            return Rect(
                x: Extent.start(
                    option: values.horizontal, extent: width,
                    start: columnOrigins[column] + margin.left, available: availableWidth),
                y: Extent.start(
                    option: values.vertical, extent: height,
                    start: rowOrigins[row] + margin.top, available: availableHeight),
                width: width,
                height: height)
        }
    }

    /// How many rows and columns the grid has: its definitions, or as many as its children reach.
    @MainActor
    private static func counts<Child: LayoutChild>(
        _ items: [Child], rows: [GridLength], columns: [GridLength]
    ) -> (rows: Int, columns: Int) {
        (max(rows.count, items.map { $0.values.row + $0.values.rowSpan }.max() ?? 1),
         max(columns.count, items.map { $0.values.column + $0.values.columnSpan }.max() ?? 1))
    }

    /// `definitions`, with a track of `padding` for every track they do not define - a
    /// proportional track of one share where nothing says otherwise.
    private static func completed(
        _ definitions: [GridLength], count: Int, padding: GridLength = .proportional(1)
    ) -> [GridLength] {
        definitions + Array(repeating: padding, count: max(0, count - definitions.count))
    }

    /// The cell each item takes in a flow: row first, `columns` to a row.
    private static func flowCells(_ count: Int, columns: Int) -> [(row: Int, column: Int)] {
        (0 ..< count).map { (row: $0 / columns, column: $0 % columns) }
    }

    /// The column sizes a `flow` resolves to at `width`: stated items as they stand, an
    /// `.adaptive` one as many `.flexible` copies of it as the room fits. An unbounded `width`
    /// stands each adaptive for one column.
    public static func resolvedFlow(_ flow: [GridItem], width: Double?, spacing: Double) -> [GridItem.Size] {
        var columns: [GridItem.Size] = []
        var rest = width.flatMap { $0.isFinite ? $0 : nil }

        for item in flow {
            guard case .adaptive(let minimum, let maximum) = item.size else {
                columns.append(item.size)
                if case .fixed(let width) = item.size { rest? -= width }
                rest? -= item.spacing ?? spacing
                continue
            }
            let gap = item.spacing ?? spacing
            let count = rest.map {
                max(1, Int(($0 + gap) / (max(minimum, 1) + gap)))
            } ?? 1
            for _ in 0 ..< count {
                columns.append(.flexible(minimum: minimum, maximum: maximum))
            }
            rest = nil
        }

        return columns
    }

    /// Each track's size: fixed as stated, automatic as its largest one-track child, proportional by share.
    /// A row measures each child at the width of the `columns` it stands in, where they are known.
    /// `cells`, where a flow placed the items, stand in for each item's stated row and column, and
    /// `limits` bound the track they name, a share's size inside its minimum and maximum.
    /// Design: docs/design/host/layout.md#tracks
    @MainActor
    private static func trackSizes<Child: LayoutChild>(
        _ items: [Child], definitions: [GridLength], count: Int,
        available: Double?, spacing: Double, vertical: Bool,
        columns: (sizes: [Double], spacing: Double)? = nil,
        cells: [(row: Int, column: Int)]? = nil,
        limits: [(minimum: Double, maximum: Double)?]? = nil
    ) -> [Double] {
        var sizes = Array(repeating: 0.0, count: count)

        for index in 0..<count {
            if case .fixed(let length) = definitions[index] { sizes[index] = max(0, length) }
        }

        func extent(at index: Int) -> Double {
            let item = items[index]
            let margin = item.values.margin
            let measured = item.size(offered: columns.map { columns in
                let first = min(max(cells?[index].column ?? item.values.column, 0), columns.sizes.count - 1)
                let span = cells != nil ? 1 : max(item.values.columnSpan, 1)
                let last = min(first + span, columns.sizes.count)
                let cell = columns.sizes[first..<last].reduce(0, +)
                    + columns.spacing * Double(max(last - first - 1, 0))
                return max(0, cell - margin.left - margin.right)
            })
            return vertical
                ? measured.height + margin.top + margin.bottom
                : measured.width + margin.left + margin.right
        }

        func track(at index: Int) -> (index: Int, span: Int) {
            if let cells { return vertical ? (cells[index].row, 1) : (cells[index].column, 1) }
            let values = items[index].values
            return vertical ? (values.row, values.rowSpan) : (values.column, values.columnSpan)
        }

        for index in items.indices where items[index].isShown {
            let (trackIndex, span) = track(at: index)
            guard span == 1, trackIndex >= 0, trackIndex < count, definitions[trackIndex] == .auto else { continue }
            sizes[trackIndex] = max(sizes[trackIndex], extent(at: index))
        }

        let fixed = sizes.reduce(0, +) + spacing * Double(max(count - 1, 0))
        let starWeight = definitions.reduce(0.0) { weight, definition in
            if case .proportional(let share) = definition { return weight + max(share, 0.000_001) }
            return weight
        }
        let remainder = max(0, (available ?? fixed) - fixed)

        for index in 0..<count {
            guard case .proportional(let share) = definitions[index] else { continue }
            if available == nil {
                sizes[index] = items.indices
                    .filter { track(at: $0) == (index, 1) && items[$0].isShown }
                    .map(extent)
                    .max() ?? 0
            } else {
                sizes[index] = remainder * max(share, 0.000_001) / starWeight
            }
        }

        if let limits {
            for index in 0..<min(count, limits.count) {
                guard let limit = limits[index] else { continue }
                sizes[index] = min(max(sizes[index], limit.minimum), limit.maximum)
            }
        }

        return sizes
    }

    /// Where each track starts, from `start`, with `spacing` between them.
    private static func origins(of sizes: [Double], start: Double, spacing: Double) -> [Double] {
        var answer: [Double] = []
        var cursor = start

        for size in sizes {
            answer.append(cursor)
            cursor += size + spacing
        }

        return answer
    }
}
