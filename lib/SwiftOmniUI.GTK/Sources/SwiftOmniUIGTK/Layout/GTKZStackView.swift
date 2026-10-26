// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// A ZStack: its children one over another, each in its area, or where an engine's placement run puts it.
/// Design: docs/design/platforms/gtk/drawing.md#a-placed-child
@MainActor
class GTKZStackView: GTKTravellingLayout {
    override func firstTextBaseline(in size: LayoutSize) -> Double? {
        let places = ZStackArithmetic.places(of: items, in: Rect(0, 0, size.width, size.height),
                                            padding: padding, direction: direction)
        return zip(items, places).compactMap { item, place -> Double? in
            guard let place, item.isShown, !item.departing else { return nil }
            let baseline = item.values.verticalGuide.flatMap { $0.slot == 4 ? $0.offset : nil }
                ?? item.view.firstTextBaseline(in: LayoutSize(width: place.width, height: place.height))
            return baseline.map { place.y + $0 }
        }.min()
    }

    /// The placement a state drives, one per child; nil while each child stands in its own area.
    var placement: HostPlacementRun? {
        didSet {
            guard placement != oldValue else { return }
            setChildren(heldViews())

            // A run moving on asks only for an allocation: its places need no room, so nothing around is measured.
            if let placements = placement?.placements, !placements.isEmpty, oldValue?.placements.isEmpty == false {
                apply(placements)
            } else {
                invalidateMeasurements()
            }
        }
    }

    /// Computed during arrangement; shared by placement and child reports.
    private var insetContext: SafeAreaContext?
    private weak var insetBase: GTKView?

    /// The room inside the ZStack's own edge.
    var padding = EdgeInsets(0) {
        didSet { if padding != oldValue { invalidateMeasurements() } }
    }

    /// The children back to front as the run ranks them, or in their order without one: GTK draws a panel's
    /// children in that order and a click reaches the last first.
    override func heldViews() -> [GTKView] {
        ZStackArithmetic.drawingOrder(of: items.count, placedBy: placement?.placements ?? []).map { items[$0].view }
    }

    override func contentSize(width: Double?) -> LayoutSize {
        let current = items.filter { !$0.departing }
        if let edge = sourceElement?.safeAreaInsetEdge, current.count == 2 {
            return SafeAreaArithmetic.size(base: current[0], bar: current[1], edge: edge,
                                           spacing: sourceElement?.number(.spacing) ?? 0, width: width)
        }
        return ZStackArithmetic.size(of: items, padding: padding, width: width)
    }

    override func arrange(in bounds: Rect) {
        if let placements = placement?.placements, !placements.isEmpty {
            return apply(placements)
        }

        beginArrangement(width: bounds.width)
        for item in items where item.view.nativeSafeBarOwner == nil { item.view.setPlacedDrawing(nil, opacity: 1) }
        insetContext = nil
        insetBase = nil
        let current = items.filter { !$0.departing }
        if let edge = sourceElement?.safeAreaInsetEdge, current.count == 2 {
            let context = layoutSafeArea(in: bounds)
            let physicalEdge = SafeAreaArithmetic.physicalEdge(edge, direction: direction)
            let bar = current[1]
            let barPlace = bar.isShown
                ? SafeAreaArithmetic.bar(of: bar, edge: physicalEdge, in: context, direction: direction) : Rect(0, 0, 0, 0)
            let extent = edge == .top || edge == .bottom
                ? barPlace.height + bar.values.margin.top + bar.values.margin.bottom
                : barPlace.width + bar.values.margin.left + bar.values.margin.right
            let next = bar.isShown
                ? context.inset(edge: physicalEdge, extent: extent, spacing: sourceElement?.number(.spacing) ?? 0) : context
            insetContext = next
            let base = current[0]
            insetBase = base.view
            let basePlace = SafeAreaArithmetic.base(of: base, boundary: base.element?.preservesSafeAreaProposal == true,
                                                   ignores: base.element?.ignoresSafeArea,
                                                   in: next, direction: direction)
            self.place(base, at: basePlace)
            if bar.isShown {
                if bar.view.nativeSafeBarOwner != nil {
                    bar.view.recordSafeBarPlace(barPlace, context: SafeAreaContext(bounds: Rect(0, 0, barPlace.width, barPlace.height)))
                } else {
                    self.place(bar, at: barPlace)
                }
            }
            return
        }
        let room = Rect(x: 0, y: 0, width: bounds.width, height: bounds.height)
        let places = ZStackArithmetic.places(of: items, in: room, padding: padding, direction: direction)
        for (item, place) in zip(items, places) {
            if let place { self.place(item, at: place) }
        }
    }

    /// Stands each child where the run says, drawn as it says: at once inside an allocation, and between them in
    /// the allocation each place asks for.
    private func apply(_ placements: [HostPlacement]) {
        let count = min(items.count, placements.count)
        for index in 0..<count {
            let placement = placements[index]
            let view = items[index].view
            view.setPlacedDrawing(placement.drawing, opacity: placement.drawnOpacity)
            view.layout(placement.place)
            (view as? GTKGridView)?.setShadeOpacity(placement.drawnShade)
        }
        for item in items[count...] { item.view.setPlacedDrawing(nil, opacity: 1) }
    }
    override func context(for child: GTKView, at place: Rect) -> SafeAreaContext {
        if sourceElement?.safeAreaInsetEdge != nil {
            if insetBase === child, let insetContext {
                return insetContext.child(in: place, preservingOutsets: child.sourceElement?.observesSafeArea == true)
            }
            // The inset's content receives the incoming edge proposal, not its
            // own contribution, so GeometryReader inside a bar cannot loop.
            return SafeAreaContext(bounds: Rect(0, 0, place.width, place.height))
        }
        return super.context(for: child, at: place)
    }

}
