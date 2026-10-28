// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// A ZStack: its children one over another, each in its area, or where an engine's placement run puts it.
/// Design: docs/design/platforms/winui/drawing.md#a-placed-child
@MainActor
class WinUIZStackView: WinUITravellingLayout {
    /// Local insets on every edge own a material behind the bar, above the
    /// scrolling base. Window markers join the shared native material region.
    private var safeAreaBackground: WinUIView?

    override func heldViews() -> [WinUIView] {
        var views = super.heldViews()
        guard sourceElement?.safeAreaInsetEdge != nil else { return views }
        let current = items.filter { !$0.departing }
        guard current.count == 2,
              current[1].view.nativeSafeBarOwner == nil,
              current[1].element?.safeBarBackgroundHidden != true,
              let index = views.firstIndex(where: { $0 === current[1].view }) else { return views }
        if safeAreaBackground == nil {
            let background = WinUIView { _ in swiftomniui_winui_safe_area_background_make() }
            background.placingLayout = self
            safeAreaBackground = background
        }
        // Source identity belongs to mounting, independently of whether a
        // cached native placement plan needs to be rebuilt on this pass.
        swiftomniui_winui_safe_area_background_source(safeAreaBackground!.handle, current[0].view.presentationHandle)
        swiftomniui_winui_safe_area_register(handle, current[1].view.presentationHandle, safeAreaBackground?.presentationHandle)
        views.insert(safeAreaBackground!, at: index)
        holdInDrawingOrder()
        return views
    }

    override func firstTextBaseline(in size: LayoutSize) -> Double? {
        let places = childPlaces(in: Rect(0, 0, size.width, size.height))
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
            holdInDrawingOrder()

            // A run moving on asks only for an arrangement: its places need no room, so nothing around is measured.
            if let placements = placement?.placements, !placements.isEmpty, oldValue?.placements.isEmpty == false {
                forgetLayoutPlans()
                apply(placements, in: allocatedBounds)
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
        defer { holdChildren(); holdInDrawingOrder() }
        return super.setItems(items)
    }

    override func contentSize(width: Double?) -> LayoutSize {
        Self.querySize {
            let current = items.filter { !$0.departing }
            if let edge = sourceElement?.safeAreaInsetEdge, current.count == 2 {
                return SafeAreaArithmetic.size(base: current[0], bar: current[1], edge: edge,
                                               spacing: sourceElement?.number(.spacing) ?? 0, width: width)
            }
            return ZStackArithmetic.size(of: items, padding: padding, width: width)
        }
    }

    override var hasNativeProposals: Bool { true }
    override var retainsArithmeticOnNativeMeasure: Bool { true }

    override func prepareLayoutContent(in bounds: Rect, measuringNative: Bool) {
        super.prepareLayoutContent(in: bounds, measuringNative: measuringNative)
        guard sourceElement?.safeAreaInsetEdge != nil else { return }
        let current = items.filter { !$0.departing }
        guard current.count == 2, current[1].view.nativeSafeBarOwner == nil,
              current[1].element?.safeBarBackgroundHidden != true else { return }
        // Native ownership/background visibility can settle after setItems.
        // Ensure the decoration exists before selecting a cached first plan.
        if safeAreaBackground == nil || (isAttached && safeAreaBackground?.isAttached == false) {
            let previous = safeAreaBackground
            holdChildren()
            if previous !== safeAreaBackground || safeAreaBackground?.isAttached == false { forgetLayoutPlans() }
        }
    }
    override func nativeProposals(width: Double?, size: LayoutSize) -> [NativeProposal] {
        if let placements = placement?.placements, !placements.isEmpty {
            insetContext = nil
            insetBase = nil
            _ = resolveInset(in: Rect(0, 0, width ?? size.width, size.height), items: items.filter { !$0.departing })
            var proposals = zip(items, placements).map { item, placement in
                NativeProposal(view: item.view, place: placement.place)
            }
            appendSafeAreaBackground(to: &proposals, in: Rect(0, 0, width ?? size.width, size.height))
            return proposals
        }
        let places = childPlaces(in: Rect(0, 0, width ?? size.width, size.height))
        var proposals = zip(items, places).compactMap { item, place in
            place.map { NativeProposal(view: item.view, place: $0) }
        }
        appendSafeAreaBackground(to: &proposals, in: Rect(0, 0, width ?? size.width, size.height))
        return proposals
    }

    override func arrange(in bounds: Rect) {
        if let placements = placement?.placements, !placements.isEmpty {
            return apply(placements, in: bounds)
        }

        beginArrangement(in: bounds)
        for item in items where item.view.nativeSafeBarOwner == nil { item.view.setPlacedDrawing(nil, opacity: 1) }
        let byView = Dictionary(uniqueKeysWithValues: items.map { ($0.view.number, $0) })
        for proposal in preparedLayoutPlan(in: bounds) {
            if let background = safeAreaBackground, proposal.view === background {
                background.setPlacedDrawing(nil, opacity: 1)
                background.layout(proposal.place)
                continue
            }
            guard let view = proposal.view, let item = byView[view.number] else { continue }
            let place = proposal.place
            if item.view.nativeSafeBarOwner != nil, item.view !== insetBase,
               sourceElement?.safeAreaInsetEdge != nil {
                item.view.recordSafeBarPlace(place, context: SafeAreaContext(bounds: Rect(0, 0, place.width, place.height)))
            } else {
                self.place(item, at: place)
            }
        }
    }

    /// Native preparation and placement must use the same safe-area widths.
    override func restoreLayoutContext(in bounds: Rect, proposals: [NativeProposal]) {
        insetContext = nil
        insetBase = nil
        let current = items.filter { !$0.departing }
        guard let edge = sourceElement?.safeAreaInsetEdge, current.count == 2 else { return }
        let base = current[0], bar = current[1]
        swiftomniui_winui_safe_area_register(handle, bar.view.presentationHandle, safeAreaBackground?.presentationHandle)
        let context = layoutSafeArea(in: bounds)
        let physicalEdge = SafeAreaArithmetic.physicalEdge(edge, direction: direction)
        let barPlace = proposals.first(where: { $0.view === bar.view })?.place ?? Rect(0, 0, 0, 0)
        let extent = edge == .top || edge == .bottom
            ? barPlace.height + bar.values.margin.top + bar.values.margin.bottom
            : barPlace.width + bar.values.margin.left + bar.values.margin.right
        insetBase = base.view
        insetContext = bar.isShown
            ? context.inset(edge: physicalEdge, extent: extent, spacing: sourceElement?.number(.spacing) ?? 0)
            : context
    }

    private func childPlaces(in bounds: Rect) -> [Rect?] {
        insetContext = nil
        insetBase = nil
        let current = items.filter { !$0.departing }
        if let (base, bar, barPlace, next) = resolveInset(in: bounds, items: current) {
            let basePlace = SafeAreaArithmetic.base(of: base, boundary: base.element?.preservesSafeAreaProposal == true,
                                                   ignores: base.element?.ignoresSafeArea,
                                                   in: next, direction: direction)
            return items.map { item in
                if item.view === base.view { return basePlace }
                if item.view === bar.view, bar.isShown { return barPlace }
                return nil
            }
        }
        return ZStackArithmetic.places(of: items, in: bounds, padding: padding, direction: direction)
    }

    /// An animated placement still needs the current inset as layout input.
    /// Its frames come from the animation, while descendants read this context.
    private func resolveInset(in bounds: Rect, items current: [WinUILayoutItem])
        -> (WinUILayoutItem, WinUILayoutItem, Rect, SafeAreaContext)? {
        guard let edge = sourceElement?.safeAreaInsetEdge, current.count == 2 else { return nil }
        let context = layoutSafeArea(in: bounds)
        let physicalEdge = SafeAreaArithmetic.physicalEdge(edge, direction: direction)
        let base = current[0], bar = current[1]
        let barPlace = bar.isShown
            ? SafeAreaArithmetic.bar(of: bar, edge: physicalEdge, in: context, direction: direction)
            : Rect(0, 0, 0, 0)
        let extent = edge == .top || edge == .bottom
            ? barPlace.height + bar.values.margin.top + bar.values.margin.bottom
            : barPlace.width + bar.values.margin.left + bar.values.margin.right
        let next = bar.isShown
            ? context.inset(edge: physicalEdge, extent: extent, spacing: sourceElement?.number(.spacing) ?? 0)
            : context
        insetBase = base.view
        insetContext = next
        return (base, bar, barPlace, next)
    }

    /// Draws the children back to front as the run ranks them, or in their order without one - the order a click
    /// reaches them in too, with nothing moved and nothing laid out again.
    private func holdInDrawingOrder() {
        if sourceElement?.safeAreaInsetEdge != nil {
            // Fixed inset chrome must stay above the scrolling branch even
            // when a lazy file list installs/reorders transition presenters.
            // Give the material its own rank instead of tying it with the bar
            // and relying on child insertion order after deferred attachment.
            let top = Int32(items.count + 1)
            let bar = items.last(where: { !$0.departing })?.view
            for (index, item) in items.enumerated() {
                let decoration = item.view === bar || item.element?.value(.isLayoutDecoration)?.bool == true
                item.view.setZIndex(decoration ? top + 1 : Int32(index))
            }
            safeAreaBackground?.setZIndex(top)
            return
        }
        let ordered = ZStackArithmetic.drawingOrder(of: items.count, placedBy: placement?.placements ?? [])
        for (rank, index) in ordered.enumerated() {
            items[index].view.setZIndex(ordered == Array(items.indices) ? 0 : Int32(rank))
        }
    }

    /// The backdrop paints the complete reserved strip, including margins and
    /// positive spacing. It never contributes to intrinsic size or safe insets.
    private func appendSafeAreaBackground(to proposals: inout [NativeProposal], in bounds: Rect) {
        guard let background = safeAreaBackground, let edge = sourceElement?.safeAreaInsetEdge else { return }
        let current = items.filter { !$0.departing }
        guard current.count == 2, current[1].view.nativeSafeBarOwner == nil,
              current[1].element?.safeBarBackgroundHidden != true else { return }
        let bar = current[1]
        guard bar.isShown, let place = proposals.first(where: { $0.view === bar.view })?.place else {
            proposals.append(NativeProposal(view: background, place: Rect(0, 0, 0, 0)))
            return
        }
        let room = layoutSafeArea(in: bounds).safe
        let margin = bar.values.margin
        let spacing = max(0, sourceElement?.number(.spacing) ?? 0)
        let frame: Rect
        switch SafeAreaArithmetic.physicalEdge(edge, direction: direction) {
        case .top:
            frame = Rect(room.x, place.y - margin.top, room.width,
                         max(0, place.height + margin.top + margin.bottom + spacing))
        case .bottom:
            frame = Rect(room.x, place.y - margin.top - spacing, room.width,
                         max(0, place.height + margin.top + margin.bottom + spacing))
        case .leading:
            frame = Rect(place.x - margin.left, room.y,
                         max(0, place.width + margin.left + margin.right + spacing), room.height)
        case .trailing:
            frame = Rect(place.x - margin.left - spacing, room.y,
                         max(0, place.width + margin.left + margin.right + spacing), room.height)
        }
        proposals.append(NativeProposal(view: background, place: frame))
    }

    /// Stands each child where the run says, drawn as it says: at once inside a pass, and between passes in the
    /// arrangement each place asks for.
    private func apply(_ placements: [HostPlacement], in bounds: Rect) {
        if !isNativeArranging {
            insetContext = nil
            insetBase = nil
            Self.querySize { _ = resolveInset(in: bounds, items: items.filter { !$0.departing }) }
        }
        let count = min(items.count, placements.count)
        if let background = safeAreaBackground, sourceElement?.safeAreaInsetEdge != nil {
            var proposals = zip(items.prefix(count), placements.prefix(count)).map { item, placement in
                NativeProposal(view: item.view, place: placement.place)
            }
            appendSafeAreaBackground(to: &proposals, in: bounds)
            if let proposal = proposals.last, proposal.view === background {
                background.layout(proposal.place)
                if let index = items.firstIndex(where: { $0.view !== insetBase && !$0.departing }), index < count {
                    background.setPlacedDrawing(placements[index].drawing, opacity: placements[index].drawnOpacity)
                }
            }
        }
        for index in 0..<count {
            let placement = placements[index]
            let view = items[index].view
            if view.nativeSafeBarOwner != nil, view !== insetBase,
               sourceElement?.safeAreaInsetEdge != nil {
                let place = placement.place
                view.recordSafeBarPlace(place, context: SafeAreaContext(bounds: Rect(0, 0, place.width, place.height)))
            } else {
                view.layout(placement.place)
            }
            view.setPlacedDrawing(placement.drawing, opacity: placement.drawnOpacity)
            (view as? WinUIGridView)?.setShadeOpacity(placement.drawnShade)
        }
        for item in items[count...] { item.view.setPlacedDrawing(nil, opacity: 1) }
    }
    override func context(for child: WinUIView, at place: Rect) -> SafeAreaContext {
        if sourceElement?.safeAreaInsetEdge != nil {
            if insetBase === child, let insetContext {
                return insetContext.child(in: place, preservingOutsets: child.carriesSafeAreaOutsets)
            }
            // The inset's content receives the incoming edge proposal, not its
            // own contribution, so GeometryReader inside a bar cannot loop.
            return SafeAreaContext(bounds: Rect(0, 0, place.width, place.height))
        }
        return super.context(for: child, at: place)
    }

    override func detach() {
        swiftomniui_winui_safe_area_register(handle, nil, nil)
        safeAreaBackground?.detach()
        safeAreaBackground = nil
        super.detach()
    }

}
