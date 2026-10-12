// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// A ZStack: its children one over another, each in its area, or where an engine's placement run puts it.
/// Design: docs/design/platforms/winui/drawing.md#a-placed-child
@MainActor
class WinUIZStackView: WinUITravellingLayout {
    /// The placement a state drives, one per child; nil while each child stands in its own area.
    var placement: HostPlacementRun? {
        didSet {
            guard placement != oldValue else { return }
            holdInDrawingOrder()

            // A run moving on asks only for an arrangement: its places need no room, so nothing around is measured.
            if let placements = placement?.placements, !placements.isEmpty, oldValue?.placements.isEmpty == false {
                apply(placements)
            } else {
                invalidateMeasurements()
            }
        }
    }

    /// Computed during arrangement; shared by placement and child reports.
    private var insetContext: SafeAreaContext?
    private weak var insetBase: WinUIView?

    /// The room inside the ZStack's own edge, in DIPs.
    var padding = EdgeInsets(0) {
        didSet { if padding != oldValue { invalidateMeasurements() } }
    }

    @discardableResult
    override func setItems(_ items: [WinUILayoutItem]) -> Bool {
        defer { holdInDrawingOrder() }
        return super.setItems(items)
    }

    override func contentSize(width: Double?) -> LayoutSize {
        let size = ZStackArithmetic.size(of: items, padding: padding, width: width)
        if WinUIView.arranging == 0 {
            let room = Rect(x: 0, y: 0, width: size.width, height: size.height)
            let places = ZStackArithmetic.places(of: items, in: room, padding: padding, direction: direction)
            for (item, place) in zip(items, places) {
                if let place, let layout = item.view as? WinUILayoutView {
                    layout.prepareMeasure(width: place.width)
                }
            }
        }
        return size
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
                ? SafeAreaArithmetic.bar(of: bar, edge: physicalEdge, in: context, direction: direction) : .zero
            let extent = edge == .top || edge == .bottom
                ? barPlace.height + bar.values.margin.top + bar.values.margin.bottom
                : barPlace.width + bar.values.margin.left + bar.values.margin.right
            let next = bar.isShown
                ? context.inset(edge: physicalEdge, extent: extent, spacing: sourceElement?.number(.spacing) ?? 0) : context
            insetContext = next
            let base = current[0]
            insetBase = base.view
            let basePlace = SafeAreaArithmetic.base(of: base, boundary: base.element?.isSafeAreaBoundary == true,
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

    /// Draws the children back to front as the run ranks them, or in their order without one - the order a click
    /// reaches them in too, with nothing moved and nothing laid out again.
    private func holdInDrawingOrder() {
        let ordered = ZStackArithmetic.drawingOrder(of: items.count, placedBy: placement?.placements ?? [])
        for (rank, index) in ordered.enumerated() {
            items[index].view.setZIndex(ordered == Array(items.indices) ? 0 : Int32(rank))
        }
    }

    /// Stands each child where the run says, drawn as it says: at once inside a pass, and between passes in the
    /// arrangement each place asks for.
    private func apply(_ placements: [HostPlacement]) {
        let count = min(items.count, placements.count)
        for index in 0..<count {
            let placement = placements[index]
            let view = items[index].view
            view.layout(placement.place)
            view.setPlacedDrawing(placement.drawing, opacity: placement.drawnOpacity)
            (view as? WinUIGridView)?.setShadeOpacity(placement.drawnShade)
        }
        for item in items[count...] { item.view.setPlacedDrawing(nil, opacity: 1) }
    }
    override func context(for child: WinUIView, at place: Rect) -> SafeAreaContext {
        if sourceElement?.safeAreaInsetEdge != nil {
            if insetBase === child, let insetContext { return insetContext.child(in: place) }
            // The inset's content receives the incoming edge proposal, not its
            // own contribution, so GeometryReader inside a bar cannot loop.
            return SafeAreaContext(bounds: Rect(0, 0, place.width, place.height))
        }
        return super.context(for: child, at: place)
    }

}
