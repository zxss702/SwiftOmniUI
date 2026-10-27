// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// A Grid: the core's grid arithmetic over the relay's panel.
@MainActor
final class WinUIGridView: WinUITravellingLayout {
    var contentSizedTracks = false {
        didSet { if contentSizedTracks != oldValue { invalidateMeasurements() } }
    }
    private var implicitRows: [GridLength] {
        guard contentSizedTracks, rows.isEmpty else { return rows }
        let count = max(1, items.map { $0.values.row + $0.values.rowSpan }.max() ?? 1)
        return Array(repeating: .auto, count: count)
    }
    private var implicitColumns: [GridLength] {
        guard contentSizedTracks, columns.isEmpty else { return columns }
        let count = max(1, items.map { $0.values.column + $0.values.columnSpan }.max() ?? 1)
        return Array(repeating: .auto, count: count)
    }

    var rows: [GridLength] = [] {
        didSet { if rows != oldValue { invalidateMeasurements() } }
    }

    var columns: [GridLength] = [] {
        didSet { if columns != oldValue { invalidateMeasurements() } }
    }

    /// The room between two rows, and between two columns, in DIPs.
    var rowSpacing = 0.0 {
        didSet { if rowSpacing != oldValue { invalidateMeasurements() } }
    }

    var columnSpacing = 0.0 {
        didSet { if columnSpacing != oldValue { invalidateMeasurements() } }
    }

    /// A `LazyVGrid`'s columns: a flow fills them row first, an adaptive one
    /// as many times as the room fits.
    var flowColumns: [GridItem] = [] {
        didSet { if flowColumns != oldValue { invalidateMeasurements() } }
    }

    /// The room inside the grid's own edge, in DIPs.
    var padding = EdgeInsets(0) {
        didSet { if padding != oldValue { invalidateMeasurements() } }
    }

    /// Draws the shade a placed layout lays over its card - the grid's second child - `opacity` opaque.
    /// Design: docs/design/platforms/winui/drawing.md#a-placed-child
    func setShadeOpacity(_ opacity: Double) {
        guard items.count > 1 else { return }
        items[1].view.setOpacity(opacity)
    }

    override func contentSize(width: Double?) -> LayoutSize {
        Self.querySize { queriedSize(width: width) }
    }

    override var hasNativeProposals: Bool { true }
    override func nativeProposals(width: Double?, size: LayoutSize) -> [NativeProposal] {
        let bounds = Rect(0, 0, width ?? size.width, size.height)
        let places = childPlaces(in: bounds)
        return zip(items, places).compactMap { item, place in
            place.map { NativeProposal(view: item.view, place: $0) }
        }
    }

    private func queriedSize(width: Double?) -> LayoutSize {
        if sourceElement?.isGeometryReader == true { return GeometryReaderArithmetic.size(width: width) }
        let barPadding = sourceElement?.safeAreaPadding != nil && sourceElement?.safeBarSizingAxes != .neither
            ? sourceElement?.safeAreaPadding ?? EdgeInsets(0) : EdgeInsets(0)
        return GridArithmetic.size(of: items, rows: implicitRows, columns: implicitColumns,
                                   rowSpacing: rowSpacing, columnSpacing: columnSpacing,
                                   padding: padding + barPadding, width: width, flow: flowColumns)
    }

    override func arrange(in bounds: Rect) {
        beginArrangement(in: bounds)
        if items.count == 1, let item = items.first {
            for proposal in preparedLayoutPlan(in: bounds) where proposal.view === item.view {
                place(item, at: proposal.place)
            }
            return
        }
        let byView = Dictionary(uniqueKeysWithValues: items.map { ($0.view.number, $0) })
        for proposal in preparedLayoutPlan(in: bounds) {
            guard let view = proposal.view, let item = byView[view.number] else { continue }
            place(item, at: proposal.place)
        }
    }

    /// Preparation and arrangement must select the same native child proposals,
    /// including children of a reader whose size is independent of its content.
    private func childPlaces(in bounds: Rect) -> [Rect?] {
        let context = layoutSafeArea(in: bounds)
        if let element = sourceElement, element.isSafeAreaBoundary, let item = items.first(where: { !$0.departing }) {
            let next = context.padding(SafeAreaArithmetic.physicalInsets(element.safeAreaPadding ?? EdgeInsets(0), direction: direction))
            let place = SafeAreaArithmetic.base(of: item, boundary: item.element?.preservesSafeAreaProposal == true,
                                               ignores: item.element?.ignoresSafeArea,
                                               in: next, direction: direction)
            return items.map { $0.view === item.view ? place : nil }
        }
        if sourceElement?.isGeometryReader == true {
            return GeometryReaderArithmetic.places(of: items, in: bounds, direction: direction, safeArea: context) {
                $0.element?.preservesSafeAreaProposal == true
            }
        }
        // A frame's single implicit proportional cell is exactly its padded
        // bounds. Dense lazy file rows contain several such wrappers per row;
        // allocating track definitions, sizes and origins adds no information.
        if !contentSizedTracks, rows.isEmpty, columns.isEmpty, flowColumns.isEmpty,
           items.count == 1, let item = items.first, item.values.isFrameContent,
           item.values.row == 0, item.values.column == 0,
           item.values.rowSpan == 1, item.values.columnSpan == 1 {
            return [item.isShown ? framePlace(item, in: bounds) : nil]
        }
        return GridArithmetic.places(
            of: items, rows: implicitRows, columns: implicitColumns,
            rowSpacing: rowSpacing, columnSpacing: columnSpacing, padding: padding, in: bounds,
            direction: direction, flow: flowColumns)
    }

    /// The one-cell case of GridArithmetic, including a fixed inner frame
    /// overflowing its outer frame. Ordinary grids retain track arithmetic.
    private func framePlace(_ item: WinUILayoutItem, in bounds: Rect) -> Rect {
        let content = Rect(bounds.x + padding.left, bounds.y + padding.top,
                           max(0, bounds.width - padding.left - padding.right),
                           max(0, bounds.height - padding.top - padding.bottom))
        let values = item.values
        let margin = values.margin
        let across = max(0, content.width - margin.left - margin.right)
        let down = max(0, content.height - margin.top - margin.bottom)
        let natural = item.size(offered: across)
        let fillsAcross = values.flex != nil || values.expandingAxes == .horizontal || values.expandingAxes == .both
        let fillsDown = values.flex != nil || values.expandingAxes == .vertical || values.expandingAxes == .both
        let width = Extent.of(option: fillsAcross ? 3 : values.horizontal, stated: values.width,
                              natural: natural.width, available: across,
                              minimum: values.minimumWidth, maximum: values.maximumWidth, allowsOverflow: true)
        let height = Extent.of(option: fillsDown ? 3 : values.vertical, stated: values.height,
                               natural: natural.height, available: down,
                               minimum: values.minimumHeight, maximum: values.maximumHeight, allowsOverflow: true)
        return direction.places(Rect(
            x: Extent.start(option: values.horizontal, extent: width,
                            start: content.x + margin.left, available: across, allowsOverflow: true),
            y: Extent.start(option: values.vertical, extent: height,
                            start: content.y + margin.top, available: down, allowsOverflow: true),
            width: width, height: height), in: bounds)
    }
    override func context(for child: WinUIView, at place: Rect) -> SafeAreaContext {
        let context = layoutSafeArea(in: contextBounds)
            .padding(SafeAreaArithmetic.physicalInsets(sourceElement?.safeAreaPadding ?? EdgeInsets(0), direction: direction))
        return context.child(in: place, preservingOutsets: child.sourceElement?.observesSafeArea == true)
    }

}
