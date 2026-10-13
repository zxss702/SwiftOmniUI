// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// A Grid: the core's grid arithmetic over a panel.
@MainActor
final class GTKGridView: GTKTravellingLayout {
    var rows: [GridLength] = [] {
        didSet { if rows != oldValue { invalidateMeasurements() } }
    }

    var columns: [GridLength] = [] {
        didSet { if columns != oldValue { invalidateMeasurements() } }
    }

    /// The room between two rows, and between two columns.
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

    /// The room inside the grid's own edge.
    var padding = EdgeInsets(0) {
        didSet { if padding != oldValue { invalidateMeasurements() } }
    }

    /// Draws the shade a placed layout lays over its card - the grid's second child - `opacity` opaque.
    /// Design: docs/design/platforms/gtk/drawing.md#a-placed-child
    func setShadeOpacity(_ opacity: Double) {
        guard items.count > 1 else { return }
        items[1].view.setOpacity(min(max(opacity, 0), 1))
    }

    override func contentSize(width: Double?) -> LayoutSize {
        if sourceElement?.isGeometryReader == true { return GeometryReaderArithmetic.size(width: width) }
        return GridArithmetic.size(
            of: items, rows: rows, columns: columns,
            rowSpacing: rowSpacing, columnSpacing: columnSpacing, padding: padding, width: width,
            flow: flowColumns)
    }

    override func arrange(in bounds: Rect) {
        beginArrangement(width: bounds.width)
        let context = layoutSafeArea(in: bounds)
        if let element = sourceElement, element.isSafeAreaBoundary, let item = items.first(where: { !$0.departing }) {
            let next = context.padding(SafeAreaArithmetic.physicalInsets(element.safeAreaPadding ?? EdgeInsets(0), direction: direction))
            let place = SafeAreaArithmetic.base(of: item, boundary: item.element?.preservesSafeAreaProposal == true,
                                               ignores: item.element?.ignoresSafeArea,
                                               in: next, direction: direction)
            self.place(item, at: place)
            return
        }
        if sourceElement?.isGeometryReader == true {
            let places = GeometryReaderArithmetic.places(of: items, in: bounds, direction: direction, safeArea: context) {
                $0.element?.preservesSafeAreaProposal == true
            }
            for (item, place) in zip(items, places) {
                if let place { self.place(item, at: place) }
            }
            return
        }
        let places = GridArithmetic.places(
            of: items, rows: rows, columns: columns,
            rowSpacing: rowSpacing, columnSpacing: columnSpacing, padding: padding, in: bounds,
            direction: direction, flow: flowColumns)
        for (item, place) in zip(items, places) {
            if let place { self.place(item, at: place) }
        }
    }
    override func context(for child: GTKView, at place: Rect) -> SafeAreaContext {
        let frame = placedFrame
        let context = layoutSafeArea(in: Rect(0, 0, frame.width, frame.height))
            .padding(SafeAreaArithmetic.physicalInsets(sourceElement?.safeAreaPadding ?? EdgeInsets(0), direction: direction))
        return context.child(in: place)
    }

}
