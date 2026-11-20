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
        contentSize(proposal: ProposedViewSize(width: width))
    }

    override var contentSizeDependsOnHeight: Bool {
        items.count == 1 && items[0].values.isFrameContent
    }

    override var keepsDestinationWidth: Bool { contentSizeDependsOnHeight }

    override func firstTextBaseline(in size: LayoutSize) -> Double? {
        let places = Self.querySize { childPlaces(in: Rect(0, 0, size.width, size.height)) }
        for (item, place) in zip(items, places) {
            guard let place, item.isShown, !item.departing else { continue }
            if let explicit = item.values.verticalGuide, explicit.slot == 4 { return place.y + explicit.offset }
            if let baseline = item.view.firstTextBaseline(in: LayoutSize(width: place.width, height: place.height)) {
                return place.y + baseline
            }
        }
        return nil
    }

    override func contentSize(proposal: ProposedViewSize) -> LayoutSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let height = proposal.height.flatMap { $0.isFinite ? $0 : nil }
        return Self.querySize { queriedSize(width: width, height: height) }
    }

    override var hasNativeProposals: Bool { true }
    override var retainsArithmeticOnNativeMeasure: Bool { true }
    override func nativeProposals(width: Double?, size: LayoutSize) -> [NativeProposal] {
        let bounds = Rect(0, 0, width ?? size.width, size.height)
        let places = childPlaces(in: bounds)
        return zip(items, places).compactMap { item, place in
            place.map { NativeProposal(view: item.view, place: $0) }
        }
    }

    private func queriedSize(width: Double?, height: Double?) -> LayoutSize {
        if sourceElement?.isGeometryReader == true { return GeometryReaderArithmetic.size(width: width) }
        let barPadding = sourceElement?.safeAreaPadding != nil && sourceElement?.safeBarSizingAxes != .neither
            ? sourceElement?.safeAreaPadding ?? EdgeInsets(0) : EdgeInsets(0)
        return GridArithmetic.size(of: items, rows: implicitRows, columns: implicitColumns,
                                   rowSpacing: rowSpacing, columnSpacing: columnSpacing,
                                   padding: padding + barPadding, width: width, height: height, flow: flowColumns)
    }

    override func arrange(in bounds: Rect) {
        beginArrangement(in: bounds)
        if items.count == 1, let item = items.first {
            for proposal in preparedLayoutPlan(in: bounds) where proposal.view === item.view {
                place(item, at: proposal.place)
            }
            return
        }
        // The plan is an ordered subsequence of items, including when hidden
        // cells have no rectangle. Do not rebuild a hash table on each pass.
        var index = items.startIndex
        for proposal in preparedLayoutPlan(in: bounds) {
            guard let view = proposal.view else { continue }
            while index < items.endIndex, items[index].view !== view { index += 1 }
            guard index < items.endIndex else { break }
            place(items[index], at: proposal.place)
            index += 1
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
        return GridArithmetic.places(
            of: items, rows: implicitRows, columns: implicitColumns,
            rowSpacing: rowSpacing, columnSpacing: columnSpacing, padding: padding, in: bounds,
            direction: direction, flow: flowColumns)
    }

    override func context(for child: WinUIView, at place: Rect) -> SafeAreaContext {
        let context = layoutSafeArea(in: contextBounds)
            .padding(SafeAreaArithmetic.physicalInsets(sourceElement?.safeAreaPadding ?? EdgeInsets(0), direction: direction))
        return context.child(in: place, preservingOutsets: child.carriesSafeAreaOutsets)
    }

}
