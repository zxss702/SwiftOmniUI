// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

extension WinUIRegistrations {
    /// The stacks, the grid and the ZStack: the room a layout leaves around and between its children, and the box
    /// it paints.
    static func layouts(_ registry: Registry<WinUIView>) {
        registry.add(VStackContract.self, create: { _ in WinUIStackView(axis: .vertical) }) { stack in
            stack.applies(stackMembers) { view, values in applyStack(view, values) }
            stack.applies(boxMembers) { view, values in applyBox(view, values) }
            stack.property(VisualElementContract.ignoresInput) { view, ignores in view.setIgnoresInput(ignores ?? false) }
        }

        registry.add(HStackContract.self, create: { _ in WinUIStackView(axis: .horizontal) }) { stack in
            stack.applies(stackMembers) { view, values in applyStack(view, values) }
            stack.applies(boxMembers) { view, values in applyBox(view, values) }
            stack.property(VisualElementContract.ignoresInput) { view, ignores in view.setIgnoresInput(ignores ?? false) }
        }

        registry.add(GridContract.self, create: { _ in WinUIGridView() }) { grid in
            grid.applies([
                GridContract.rows, GridContract.columns,
                GridContract.rowSpacing, GridContract.columnSpacing,
                GridContract.flowColumns,
                PaddingElementContract.contentPadding,
            ]) { view, values in
                view.rows = values[GridContract.rows] ?? []
                view.columns = values[GridContract.columns] ?? []
                view.flowColumns = values[GridContract.flowColumns] ?? []
                view.rowSpacing = values[GridContract.rowSpacing] ?? 0
                view.columnSpacing = values[GridContract.columnSpacing] ?? 0
                view.padding = values[PaddingElementContract.contentPadding] ?? EdgeInsets(0)
            }
            grid.applies(boxMembers) { view, values in applyBox(view, values) }
            grid.property(VisualElementContract.ignoresInput) { view, ignores in view.setIgnoresInput(ignores ?? false) }
        }

        registry.add(CustomLayoutContract.self, create: { _ in WinUICustomLayoutView() }) { layout in
            layout.property(PaddingElementContract.contentPadding) { view, padding in view.padding = padding ?? EdgeInsets(0) }
            layout.applies(boxMembers) { view, values in applyBox(view, values) }
            layout.property(VisualElementContract.ignoresInput) { view, ignores in view.setIgnoresInput(ignores ?? false) }
        }

        registry.add(LazyVStackContract.self, madeByHost: WinUILazyStackView.self) { lazy in
            lazy.applies(stackMembers + [LazyVStackContract.items]) { view, values in
                view.spacing = values[StackBaseContract.spacing]
                view.padding = values[PaddingElementContract.contentPadding] ?? EdgeInsets(0)
            }
            lazy.applies(boxMembers) { view, values in applyBox(view, values) }
            lazy.property(VisualElementContract.ignoresInput) { view, ignores in view.setIgnoresInput(ignores ?? false) }
            lazy.raises(LazyVStackContract.realizedChanged)
        }

        registry.add(LazyHStackContract.self, madeByHost: WinUILazyStackView.self) { lazy in
            lazy.applies(stackMembers + [LazyHStackContract.items]) { view, values in
                view.spacing = values[StackBaseContract.spacing]
                view.padding = values[PaddingElementContract.contentPadding] ?? EdgeInsets(0)
            }
            lazy.applies(boxMembers) { view, values in applyBox(view, values) }
            lazy.property(VisualElementContract.ignoresInput) { view, ignores in view.setIgnoresInput(ignores ?? false) }
            lazy.raises(LazyHStackContract.realizedChanged)
        }

        registry.add(LazyVGridContract.self, madeByHost: WinUILazyGridView.self) { grid in
            grid.property(ViewContract.horizontalContentAlignment) { view, alignment in
                view.trackAlignment = alignment ?? .center
            }
            grid.applies([
                LazyVGridContract.items, LazyVGridContract.flowColumns, LazyVGridContract.rowSpacing,
                LazyVGridContract.columnSpacing, PaddingElementContract.contentPadding,
            ]) { view, values in
                view.tracks = values[LazyVGridContract.flowColumns] ?? []
                view.runSpacing = values[LazyVGridContract.rowSpacing] ?? 0
                view.trackSpacing = values[LazyVGridContract.columnSpacing] ?? 0
                view.padding = values[PaddingElementContract.contentPadding] ?? EdgeInsets(0)
            }
            grid.applies(boxMembers) { view, values in applyBox(view, values) }
            grid.property(VisualElementContract.ignoresInput) { view, ignores in view.setIgnoresInput(ignores ?? false) }
            grid.raises(LazyVGridContract.realizedChanged)
        }

        registry.add(LazyHGridContract.self, madeByHost: WinUILazyGridView.self) { grid in
            grid.property(ViewContract.verticalContentAlignment) { view, alignment in
                view.trackAlignment = alignment ?? .center
            }
            grid.applies([
                LazyHGridContract.items, LazyHGridContract.flowRows, LazyHGridContract.rowSpacing,
                LazyHGridContract.columnSpacing, PaddingElementContract.contentPadding,
            ]) { view, values in
                view.tracks = values[LazyHGridContract.flowRows] ?? []
                view.runSpacing = values[LazyHGridContract.columnSpacing] ?? 0
                view.trackSpacing = values[LazyHGridContract.rowSpacing] ?? 0
                view.padding = values[PaddingElementContract.contentPadding] ?? EdgeInsets(0)
            }
            grid.applies(boxMembers) { view, values in applyBox(view, values) }
            grid.property(VisualElementContract.ignoresInput) { view, ignores in view.setIgnoresInput(ignores ?? false) }
            grid.raises(LazyHGridContract.realizedChanged)
        }

        registry.add(ZStackContract.self, create: { _ in WinUIZStackView() }) { layout in
            layout.property(PaddingElementContract.contentPadding) { view, padding in view.padding = padding ?? EdgeInsets(0) }
            layout.applies(boxMembers) { view, values in applyBox(view, values) }
            layout.property(VisualElementContract.ignoresInput) { view, ignores in view.setIgnoresInput(ignores ?? false) }
        }

        // The mask the `.mask` modifier writes last is laid out in the same room and never drawn; the content is
        // cut to its silhouette.
        // Design: docs/design/platforms/winui/drawing.md#a-mask
        registry.add(MaskedContract.self, create: { _ in WinUIMaskedView() }) { layout in
            layout.property(PaddingElementContract.contentPadding) { view, padding in view.padding = padding ?? EdgeInsets(0) }
            layout.applies(boxMembers) { view, values in applyBox(view, values) }
            layout.property(VisualElementContract.ignoresInput) { view, ignores in view.setIgnoresInput(ignores ?? false) }
        }

        // Where the user moves it is reported by the element, on the display.s frames.
        // Design: docs/design/platforms/winui/layout.md#scrolling
        registry.add(ScrollViewContract.self, create: { _ in WinUIScrollView() }) { scroll in
            scroll.applies([
                ScrollViewContract.orientation, ScrollViewContract.verticalScrollIndicators,
                ScrollViewContract.horizontalScrollIndicators, ScrollViewContract.scrollOffset,
                ScrollViewContract.defaultScrollAnchor, ScrollViewContract.scrollBounceBehavior,
                ScrollViewContract.scrollBounceAxes,
                PaddingElementContract.contentPadding,
            ]) { view, values in
                view.apply(
                    orientation: values[ScrollViewContract.orientation] ?? .vertical,
                    padding: values[PaddingElementContract.contentPadding] ?? EdgeInsets(0),
                    verticalBar: values[ScrollViewContract.verticalScrollIndicators] ?? .automatic,
                    horizontalBar: values[ScrollViewContract.horizontalScrollIndicators] ?? .automatic,
                    defaultAnchor: values[ScrollViewContract.defaultScrollAnchor],
                    offset: values.changed(ScrollViewContract.scrollOffset) ? values[ScrollViewContract.scrollOffset] : nil,
                    bounce: values[ScrollViewContract.scrollBounceBehavior] ?? .automatic,
                    bounceAxes: values[ScrollViewContract.scrollBounceAxes] ?? [.vertical, .horizontal])
            }
            scroll.applies([
                VisualElementContract.background,
                BorderElementContract.shape, BorderElementContract.stroke, BorderElementContract.strokeWidth,
            ]) { view, values in
                // A scroller always cuts what it shows to its bounds; a shape cuts it to the shape.
                view.setBackground(values[VisualElementContract.background]?.propValue)
                view.setOutline(
                    stroke: values[BorderElementContract.stroke]?.propValue,
                    width: values[BorderElementContract.strokeWidth],
                    shape: values[BorderElementContract.shape]?.propValue,
                    clips: values[BorderElementContract.shape] != nil)
            }
            scroll.raises(ScrollViewContract.scrollXChanged)
            scroll.raises(ScrollViewContract.scrollYChanged)
            scroll.raises(ScrollViewContract.scrollStopped)
        }
    }

    /// What every layout takes of its own box: what fills it, its outline, its shape and its cut.
    private static let boxMembers: [any ContractMember] = [
        VisualElementContract.background,
        BorderElementContract.stroke, BorderElementContract.strokeWidth, BorderElementContract.shape,
        LayoutContract.clipsContent,
    ]

    private static func applyBox<Realized: ElementContract>(_ view: WinUILayoutView, _ values: ElementValues<Realized>) {
        view.setBackground(values[VisualElementContract.background]?.propValue)
        view.setOutline(
            stroke: values[BorderElementContract.stroke]?.propValue,
            width: values[BorderElementContract.strokeWidth],
            shape: values[BorderElementContract.shape]?.propValue,
            clips: values[LayoutContract.clipsContent] ?? false)
    }

    /// What both stacks take: the space between their children, and the space inside their own edge.
    private static let stackMembers: [any ContractMember] = [
        StackBaseContract.spacing, PaddingElementContract.contentPadding,
    ]

    private static func applyStack<Realized: ElementContract>(_ view: WinUIStackView, _ values: ElementValues<Realized>) {
        view.spacing = values[StackBaseContract.spacing]
        view.padding = values[PaddingElementContract.contentPadding] ?? EdgeInsets(0)
    }
}
