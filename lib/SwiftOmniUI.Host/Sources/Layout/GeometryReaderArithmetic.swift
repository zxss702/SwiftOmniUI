// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore

/// GeometryReader has an ideal extent of ten on unspecified axes. Its children
/// receive the allocated proposal, stacked from the leading top corner.
@_spi(Host) public enum GeometryReaderArithmetic {
    public static func size(width: Double?, height: Double? = nil) -> LayoutSize {
        LayoutSize(width: width.flatMap { $0.isFinite ? max(0, $0) : nil } ?? 10,
                   height: height.flatMap { $0.isFinite ? max(0, $0) : nil } ?? 10)
    }

    @MainActor public static func places<Child: LayoutChild>(of items: [Child], in room: Rect,
                                                          direction: LayoutDirection) -> [Rect?] {
        items.map { item in
            guard item.isShown else { return nil }
            return SingleChildArithmetic.place(of: LeadingChild(base: item), in: room,
                                               padding: EdgeInsets(0), direction: direction)
        }
    }

    @MainActor private struct LeadingChild<Base: LayoutChild>: LayoutChild {
        let base: Base
        var values: LayoutValues {
            var values = base.values
            values.horizontal = 0
            values.vertical = 0
            return values
        }
        var isShown: Bool { base.isShown }
        func size(offered width: Double?) -> LayoutSize { base.size(offered: width) }
    }
}

extension SafeAreaArithmetic {
    /// Ordered inset placement. The bar occupies the incoming safe region's
    /// edge; only the base receives the reduced region.
    @MainActor public static func bar<Child: LayoutChild>(of item: Child, edge: Edge,
                                                        in context: SafeAreaContext,
                                                        direction: LayoutDirection) -> Rect {
        let room = context.safe
        let size = item.size(offered: edge == .top || edge == .bottom ? room.width : nil)
        let height = max(0, size.height + item.values.margin.top + item.values.margin.bottom)
        let width = max(0, size.width + item.values.margin.left + item.values.margin.right)
        let slot: Rect
        switch edge {
        case .top: slot = Rect(room.x, room.y, room.width, height)
        case .bottom: slot = Rect(room.x, room.y + room.height - height, room.width, height)
        case .leading: slot = Rect(room.x, room.y, width, room.height)
        case .trailing: slot = Rect(room.x + room.width - width, room.y, width, room.height)
        }
        return SingleChildArithmetic.place(of: item, in: slot, padding: EdgeInsets(0), direction: direction)
    }

    @MainActor public static func base<Child: LayoutChild>(of item: Child, boundary: Bool,
                                                         ignores: SafeAreaEdges?,
                                                         in context: SafeAreaContext,
                                                         direction: LayoutDirection) -> Rect {
        let context = context.ignoring(ignores)
        return SingleChildArithmetic.place(of: item, in: boundary ? context.bounds : context.safe,
                                           padding: EdgeInsets(0), direction: direction)
    }
}
