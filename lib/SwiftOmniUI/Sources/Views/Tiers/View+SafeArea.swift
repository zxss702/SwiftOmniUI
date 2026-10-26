// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// `.safeAreaInset(edge:) {}` places a bar in the incoming safe region and
// reduces the region passed to its base. Ordinary content avoids that region;
// a ScrollView extends its native viewport behind it and consumes it as margins.
// Design: docs/design/views/modifiers.md#composed-modifiers

extension View {
    #if os(Windows) || os(Linux)
    /// Hides the native SafeBar material without changing its content or layout.
    /// Apply after `safeAreaInset`, or to a subtree containing safe-area insets.
    public func hiddenSafeBarBackground(_ hidden: Bool = true) -> ModifiedContent {
        revised { $0.props[Prop("hiddenSafeBarBackground")] = hidden.propValue }
    }
    #endif

    /// A bar floating over `edge`, its extent told in the content's safe area:
    ///
    ///     page.safeAreaInset(edge: .top) { Header() }
    ///
    /// The bar reduces the safe region offered to subsequent content. Several
    /// bars reserve their edges in modifier order. A ScrollView can draw and
    /// scroll beneath them while keeping its first and last content clear.
    /// `spacing` reserves additional room after the bar. Windows supplies native
    /// Mica backing on every edge; page-level top bars share a merged surface.
    /// Other hosts retain their platform's default backing.
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
            // The host recognizes this boundary and places the two children
            // with one SafeAreaContext. The decoration flag excludes the bar
            // from ordinary ZStack sizing; it still reserves safe layout room.
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
