// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

extension View {
    /// A bar pinned to an edge of the window, drawn over the content: the
    /// window's own overlay, which rides the window rather than the view it
    /// was written on and so holds its place over a navigation's pushes and
    /// pops. A second inset on the same edge replaces the first.
    ///
    /// SPI: the `Edge` form is the host's own; the public name answers
    /// `VerticalEdge` and `HorizontalEdge`, the way SwiftUI spells them.
    @_spi(Host)
    public func safeAreaInset<Content: View>(
        edge: Edge,
        alignment: AxisAlignment = .center,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        SafeAreaInsetAnchor(
            base: self, edge: edge, alignment: alignment, inset: content)
    }
}

/// The anchor `.safeAreaInset` leaves in the tree: the view it was written
/// on, plus a hook that writes the window's overlay for that edge.
struct SafeAreaInsetAnchor<Content: View>: View {
    let base: any View
    let edge: Edge
    let alignment: AxisAlignment
    let inset: () -> Content
    @Environment var window: WindowSession

    // One place per edge of the window.
    private var key: OverlayKey { OverlayKey("swiftomniui.safeAreaInset.\(edge.rawValue)") }

    var body: some View {
        base
            .onAppear {
                window.overlays[key] = InsetView(edge: edge, alignment: alignment, inset: inset)
            }
            .onDisappear {
                window.overlays[key] = nil
            }
    }
}

/// What the overlay shows: the bar, laid along its edge.
private struct InsetView<Content: View>: View {
    let edge: Edge
    let alignment: AxisAlignment
    let inset: () -> Content

    var body: some View {
        // On the edge's own axis the bar fills; across it the alignment says
        // where.
        let pinned = inset()
        return pinned
            .verticalAlignment(edge == .top ? .start : edge == .bottom ? .end : alignment)
            .horizontalAlignment(edge == .leading ? .start : edge == .trailing ? .end : alignment)
    }
}

extension View {
    /// Lets this view under parts of the screen's unsafe strip - the notch,
    /// the bars, the on-screen keyboard:
    ///
    ///     Color.cornflowerBlue.ignoresSafeArea()
    ///     DocView().ignoresSafeArea(.container, edges: .top)
    ///
    /// The SwiftUI form; `ignoresSafeArea(_:)` on a `Layout`, which says what
    /// the layout stays clear of, is the same thing said the other way. As
    /// there, the page's own layout is the one the strip is real for - deeper
    /// views stand where the page puts them, and a platform with no unsafe
    /// strip draws no difference.
    ///
    /// - Parameters:
    ///   - regions: which strips to ignore - `.container`, `.keyboard` or
    ///     `.all`, the last the default.
    ///   - edges: which edges it counts on, `.all` the default.
    public func ignoresSafeArea(
        _ regions: SafeAreaRegions = .all,
        edges: Edge.Set = .all
    ) -> ModifiedContent {
        let answer = regions.stayingClearOf
        let edges: SafeAreaEdges = edges == .all
            ? .uniform(answer)
            : .edges(
                left: edges.contains(.leading) ? answer : .all,
                top: edges.contains(.top) ? answer : .all,
                right: edges.contains(.trailing) ? answer : .all,
                bottom: edges.contains(.bottom) ? answer : .all)
        return revised {
            $0.wrapPaddedFrame()
            $0.write(LayoutContract.ignoresSafeArea, edges)
        }
    }
}
