// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// A VStack or an HStack: the core's stack arithmetic over the relay's panel.
@MainActor
final class WinUIStackView: WinUITravellingLayout {
    /// The axis the stack runs along.
    let axis: StackArithmetic.Axis

    /// The room between two children, in DIPs.
    var spacing: Double? {
        didSet { if spacing != oldValue { invalidateMeasurements() } }
    }

    /// The room inside the stack's own edge, in DIPs.
    var padding = EdgeInsets(0) {
        didSet { if padding != oldValue { invalidateMeasurements() } }
    }

    init(axis: StackArithmetic.Axis) {
        self.axis = axis
        super.init()
    }

    override func contentSize(width: Double?) -> LayoutSize {
        contentSize(proposal: ProposedViewSize(width: width))
    }

    override var contentSizeDependsOnHeight: Bool {
        axis == .horizontal && items.contains { $0.isShown && !$0.departing && ($0.values.scalesToFit || $0.values.isFrameContent) }
    }

    override func contentSize(proposal: ProposedViewSize) -> LayoutSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let height = proposal.height.flatMap { $0.isFinite ? $0 : nil }
        return Self.querySize {
            StackArithmetic.size(of: items, axis: axis, spacing: spacing, padding: padding, width: width, height: height)
        }
    }

    override func firstTextBaseline(in size: LayoutSize) -> Double? {
        let places = Self.querySize {
            StackArithmetic.places(of: items, axis: axis, spacing: spacing, padding: padding,
                                   in: Rect(x: 0, y: 0, width: size.width, height: size.height), direction: direction)
        }
        for (item, place) in zip(items, places) {
            guard let place, item.isShown, !item.departing else { continue }
            if let explicit = item.values.verticalGuide, explicit.slot == 4 { return place.y + explicit.offset }
            if let baseline = item.view.firstTextBaseline(in: LayoutSize(width: place.width, height: place.height)) {
                return place.y + baseline
            }
        }
        return nil
    }

    override var hasNativeProposals: Bool { true }
    override var retainsArithmeticOnNativeMeasure: Bool { true }
    override func nativeProposals(width: Double?, size: LayoutSize) -> [NativeProposal] {
        let room = Rect(x: 0, y: 0, width: width ?? size.width, height: size.height)
        let places = StackArithmetic.places(of: items, axis: axis, spacing: spacing, padding: padding,
                                           in: room, direction: direction)
        return zip(items, places).compactMap { item, place in
            place.map { NativeProposal(view: item.view, place: $0) }
        }
    }

    override func arrange(in bounds: Rect) {
        beginArrangement(in: bounds)
        // nativeProposals preserves item order and only omits unplaced items.
        // Walk that subsequence instead of allocating a lookup table for every
        // HStack/VStack in every newly arranged lazy row.
        var index = items.startIndex
        for proposal in preparedLayoutPlan(in: bounds) {
            guard let view = proposal.view else { continue }
            while index < items.endIndex, items[index].view !== view { index += 1 }
            guard index < items.endIndex else { break }
            let item = items[index]
            if axis == .horizontal, item.values.vertical == AxisAlignment.end.rawValue,
               item.values.verticalGuide == nil, item.matchedGeometry == nil {
                // The row may plan its children at the destination height.
                // Their bottom alignment belongs to the actual native room.
                let top = padding.top + item.values.margin.top
                view.placementBottom = max(top, allocatedBounds.height - padding.bottom - item.values.margin.bottom)
            } else {
                view.placementBottom = nil
            }
            place(item, at: proposal.place)
            index += 1
        }
    }
}
