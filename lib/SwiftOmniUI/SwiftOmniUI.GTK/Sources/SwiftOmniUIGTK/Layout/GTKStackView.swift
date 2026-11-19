// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// A VStack or an HStack: the core's stack arithmetic over a panel.
@MainActor
final class GTKStackView: GTKTravellingLayout {
    /// The axis the stack runs along.
    let axis: StackArithmetic.Axis

    /// The room between two children.
    var spacing: Double? {
        didSet { if spacing != oldValue { invalidateMeasurements() } }
    }

    /// The room inside the stack's own edge.
    var padding = EdgeInsets(0) {
        didSet { if padding != oldValue { invalidateMeasurements() } }
    }

    init(axis: StackArithmetic.Axis) {
        self.axis = axis
        super.init()
    }

    override func contentSize(width: Double?) -> LayoutSize {
        StackArithmetic.size(of: items, axis: axis, spacing: spacing, padding: padding, width: width)
    }

    override func contentSize(width: Double?, offeredHeight: Double) -> LayoutSize? {
        guard axis == .horizontal,
              items.contains(where: { $0.isShown && !$0.departing && ($0.values.scalesToFit || $0.values.isFrameContent) })
        else { return nil }
        return StackArithmetic.size(
            of: items, axis: axis, spacing: spacing, padding: padding, width: width, height: offeredHeight)
    }

    override func firstTextBaseline(in size: LayoutSize) -> Double? {
        let places = StackArithmetic.places(
            of: items, axis: axis, spacing: spacing, padding: padding,
            in: Rect(0, 0, size.width, size.height), direction: direction)
        for (item, place) in zip(items, places) {
            guard let place, item.isShown, !item.departing else { continue }
            if let explicit = item.values.verticalGuide, explicit.slot == 4 { return place.y + explicit.offset }
            if let baseline = item.view.firstTextBaseline(in: LayoutSize(width: place.width, height: place.height)) {
                return place.y + baseline
            }
        }
        return nil
    }

    override func arrange(in bounds: Rect) {
        beginArrangement(in: bounds)
        let places = StackArithmetic.places(
            of: items, axis: axis, spacing: spacing, padding: padding, in: bounds, direction: direction)
        for (item, place) in zip(items, places) {
            guard let place else { continue }
            if axis == .horizontal, item.values.vertical == AxisAlignment.end.rawValue, item.values.verticalGuide == nil {
                let top = padding.top + item.values.margin.top
                item.view.placementBottom = max(top, allocatedBounds.height - padding.bottom - item.values.margin.bottom)
            } else {
                item.view.placementBottom = nil
            }
            self.place(item, at: place)
        }
    }
}
