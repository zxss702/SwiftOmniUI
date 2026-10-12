// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// `.safeAreaInset(edge:) {}` floats a bar over an edge of the view it was
// written on: the content keeps the whole room - a scroll view inside draws
// its background under the bar and scrolls beneath it - and the bar's extent
// is told in the content's safe area all the same, so a scroller can inset
// its document clear of the bar.
// Design: docs/design/views/modifiers.md#composed-modifiers

extension View {
    /// A bar floating over `edge`, its extent told in the content's safe area:
    ///
    ///     page.safeAreaInset(edge: .top) { Header() }
    ///
    /// The content keeps the whole room - a scroll view inside draws its
    /// background beneath the bar and scrolls its content under it, inset so
    /// the last of it stands clear. `content` sits at `alignment` across the
    /// bar; `spacing` adds to the room the bar keeps clear past its extent.
    /// The bar draws no background of its own.
    ///
    /// - Parameters:
    ///   - edge: `.top` or `.bottom`.
    ///   - alignment: where the bar sits across.
    ///   - spacing: more room kept clear past the bar's extent.
    ///   - content: the bar.
    public func safeAreaInset<Content: View>(
        edge: VerticalEdge,
        alignment: HorizontalAlignment = .center,
        spacing: Double? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let bar = content().frame(
            maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
        return SafeAreaInsetContent(base: self, bar: bar,
                                    edge: edge == .top ? .top : .bottom, spacing: spacing ?? 0)
    }

    /// The same, on the horizontal axis:
    ///
    ///     page.safeAreaInset(edge: .leading) { Sidebar() }
    ///
    /// - Parameters:
    ///   - edge: `.leading` or `.trailing`.
    ///   - alignment: where the bar sits down it.
    ///   - spacing: more room kept clear past the bar's extent.
    ///   - content: the bar.
    public func safeAreaInset<Content: View>(
        edge: HorizontalEdge,
        alignment: VerticalAlignment = .center,
        spacing: Double? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let bar = content().frame(
            maxHeight: .infinity, alignment: Alignment(horizontal: .center, vertical: alignment))
        return SafeAreaInsetContent(base: self, bar: bar,
                                    edge: edge == .leading ? .leading : .trailing, spacing: spacing ?? 0)
    }
}

private struct SafeAreaInsetContent<Base: View, Bar: View>: View {
    let base: Base
    let bar: Bar
    let edge: Edge
    let spacing: Double

    init(base: Base, bar: Bar, edge: Edge, spacing: Double) {
        self.base = base
        self.bar = bar
        self.edge = edge
        self.spacing = spacing
    }

    var body: some View {
        let edge = edge, spacing = spacing
        let inset = bar
        let content = base
        var stack = ZStack()
        stack.node.write(StackBaseContract.spacing, spacing)
        stack.node.props[.safeAreaInsetEdge] = edge.propValue
        stack.node.producer = {
            // The content fills the whole room; the bar takes only what it
            // takes at the edge, standing over it - the last of the two
            // children so it draws on top, a decoration no part of the room.
            var bar = inset.node
            bar.props[.isLayoutDecoration] = true.propValue
            switch edge {
            case .top: bar.write(ViewContract.verticalAlignment, AxisAlignment.start)
            case .bottom: bar.write(ViewContract.verticalAlignment, AxisAlignment.end)
            case .leading: bar.write(ViewContract.horizontalAlignment, AxisAlignment.start)
            case .trailing: bar.write(ViewContract.horizontalAlignment, AxisAlignment.end)
            }
            return [content.node, bar]
        }
        return AnyView(stack)
    }
}
