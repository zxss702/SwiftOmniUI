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
        Self.querySize {
            StackArithmetic.size(of: items, axis: axis, spacing: spacing, padding: padding, width: width)
        }
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
            place(items[index], at: proposal.place)
            index += 1
        }
    }
}
