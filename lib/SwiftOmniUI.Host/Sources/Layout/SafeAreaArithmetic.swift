// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore

/// Where a page's content stands against the window's safe area, the same on every host that has one: clear of the
/// bars and the notch, but on an edge where its layout lets it under them - edge to edge, or clear of the keyboard
/// alone - out to the window's edge.
/// Design: docs/design/host/layout.md#the-safe-area
@_spi(Host) public enum SafeAreaArithmetic {
    /// An inset outside a frame adds its bar to the frame's reported size.
    /// A frame outside the inset constrains this combined size as usual.
    @MainActor
    public static func size<Child: LayoutChild>(base: Child, bar: Child, edge: Edge,
                                               spacing: Double, width: Double?) -> LayoutSize {
        let vertical = edge == .top || edge == .bottom
        let barSize = SingleChildArithmetic.size(of: bar, padding: EdgeInsets(0), width: vertical ? width : nil)
        let gap = bar.isShown ? spacing : 0
        let baseWidth = vertical ? width : width.map { max(0, $0 - barSize.width - gap) }
        let baseSize = SingleChildArithmetic.size(of: base, padding: EdgeInsets(0), width: baseWidth)
        return vertical
            ? LayoutSize(width: max(baseSize.width, barSize.width), height: max(0, baseSize.height + barSize.height + gap))
            : LayoutSize(width: max(0, baseSize.width + barSize.width + gap), height: max(baseSize.height, barSize.height))
    }

    /// The room a page's content stands in: `safe` - the window's room clear of its bars and notch - reaching out to
    /// `whole` on each edge `edges` lets the content under the bars; `safe` where the content says nothing.
    public static func room(safe: Rect, whole: Rect, edges: SafeAreaEdges?) -> Rect {
        guard let edges else { return safe }
        let (left, top, right, bottom) = sides(edges)
        let minX = underTheBars(left) ? whole.x : safe.x
        let minY = underTheBars(top) ? whole.y : safe.y
        let maxX = underTheBars(right) ? whole.x + whole.width : safe.x + safe.width
        let maxY = underTheBars(bottom) ? whole.y + whole.height : safe.y + safe.height
        return Rect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }

    /// Whether content standing so on an edge runs under the bars and the notch there.
    public static func underTheBars(_ area: SafeArea) -> Bool {
        area == .none || area == .keyboard
    }

    private static func sides(_ edges: SafeAreaEdges) -> (SafeArea, SafeArea, SafeArea, SafeArea) {
        switch edges {
        case .uniform(let area): (area, area, area, area)
        case .edges(let left, let top, let right, let bottom): (left, top, right, bottom)
        }
    }
}

extension MountedElement {
    /// Which edges of the window's safe area this layout stands clear of, as the tree says; nil where it says nothing.
    public var ignoresSafeArea: SafeAreaEdges? {
        value(.ignoresSafeArea).flatMap(SafeAreaEdges.init(propValue:))
    }

    /// The edges a page's content lets it under the bars on: its own content's, which is the page's one child.
    public var contentSafeArea: SafeAreaEdges? {
        type == .page ? children.first?.ignoresSafeArea : ignoresSafeArea
    }
}
