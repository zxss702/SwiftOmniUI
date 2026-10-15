// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// A Grid: the core's grid arithmetic over the relay's panel.
@MainActor
final class WinUIGridView: WinUITravellingLayout {
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
            place.map { NativeProposal(view: item.view, width: $0.width) }
        }
    }

    private func queriedSize(width: Double?) -> LayoutSize {
        if sourceElement?.isGeometryReader == true { return GeometryReaderArithmetic.size(width: width) }
        return GridArithmetic.size(of: items, rows: rows, columns: columns,
                                   rowSpacing: rowSpacing, columnSpacing: columnSpacing,
                                   padding: padding, width: width, flow: flowColumns)
    }

    override func arrange(in bounds: Rect) {
        beginArrangement(width: bounds.width)
        let places = childPlaces(in: bounds)
        for (item, place) in zip(items, places) {
            if let place { self.place(item, at: place) }
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
            of: items, rows: rows, columns: columns,
            rowSpacing: rowSpacing, columnSpacing: columnSpacing, padding: padding, in: bounds,
            direction: direction, flow: flowColumns)
    }
    override func context(for child: WinUIView, at place: Rect) -> SafeAreaContext {
        let context = layoutSafeArea(in: allocatedBounds)
            .padding(SafeAreaArithmetic.physicalInsets(sourceElement?.safeAreaPadding ?? EdgeInsets(0), direction: direction))
        return context.child(in: place, preservingOutsets: child.sourceElement?.observesSafeArea == true)
    }

}
