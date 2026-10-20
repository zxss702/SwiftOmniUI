// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

extension GTKRegistrations {
    /// The stacks, the grid and the ZStack: the room a layout leaves around and between its children, the box it
    /// paints, and whether a click beside its children goes on to what is under it.
    static func layouts(_ registry: Registry<GTKView>) {
        registry.add(VStackContract.self, create: { _ in GTKStackView(axis: .vertical) }) { stack in
            stack.applies(stackMembers) { view, values in applyStack(view, values) }
            stack.applies(boxMembers) { view, values in applyBox(view, values) }
            stack.property(VisualElementContract.ignoresInput) { view, ignores in view.setIgnoresInput(ignores ?? false) }
            stack.property(LayoutContract.letsInputThrough) { view, lets in view.passesBeside = lets ?? false }
            stack.property(LayoutContract.hitShape) { view, shape in view.hitShape = shape }
        }

        registry.add(HStackContract.self, create: { _ in GTKStackView(axis: .horizontal) }) { stack in
            stack.applies(stackMembers) { view, values in applyStack(view, values) }
            stack.applies(boxMembers) { view, values in applyBox(view, values) }
            stack.property(VisualElementContract.ignoresInput) { view, ignores in view.setIgnoresInput(ignores ?? false) }
            stack.property(LayoutContract.letsInputThrough) { view, lets in view.passesBeside = lets ?? false }
            stack.property(LayoutContract.hitShape) { view, shape in view.hitShape = shape }
        }

        registry.add(GridContract.self, create: { _ in GTKGridView() }) { grid in
            grid.applies([
                GridContract.rows, GridContract.columns, GridContract.contentSizedTracks,
                GridContract.rowSpacing, GridContract.columnSpacing,
                GridContract.flowColumns,
                PaddingElementContract.contentPadding,
            ]) { view, values in
                view.contentSizedTracks = values[GridContract.contentSizedTracks] ?? false
                view.rows = values[GridContract.rows] ?? []
                view.columns = values[GridContract.columns] ?? []
                view.flowColumns = values[GridContract.flowColumns] ?? []
                view.rowSpacing = values[GridContract.rowSpacing] ?? 0
                view.columnSpacing = values[GridContract.columnSpacing] ?? 0
                view.padding = values[PaddingElementContract.contentPadding] ?? EdgeInsets(0)
            }
            grid.applies(boxMembers) { view, values in applyBox(view, values) }
            grid.property(VisualElementContract.ignoresInput) { view, ignores in view.setIgnoresInput(ignores ?? false) }
            grid.property(LayoutContract.letsInputThrough) { view, lets in view.passesBeside = lets ?? false }
            grid.property(LayoutContract.hitShape) { view, shape in view.hitShape = shape }
        }

        registry.add(CustomLayoutContract.self, create: { _ in GTKCustomLayoutView() }) { layout in
            layout.property(PaddingElementContract.contentPadding) { view, padding in view.padding = padding ?? EdgeInsets(0) }
            layout.applies(boxMembers) { view, values in applyBox(view, values) }
            layout.property(VisualElementContract.ignoresInput) { view, ignores in view.setIgnoresInput(ignores ?? false) }
            layout.property(LayoutContract.letsInputThrough) { view, lets in view.passesBeside = lets ?? false }
            layout.property(LayoutContract.hitShape) { view, shape in view.hitShape = shape }
        }

        registry.add(LazyVStackContract.self, madeByHost: GTKLazyStackView.self) { lazy in
            lazy.applies(stackMembers + [LazyVStackContract.items]) { view, values in
                view.spacing = values[StackBaseContract.spacing]
                view.padding = values[PaddingElementContract.contentPadding] ?? EdgeInsets(0)
            }
            lazy.applies(boxMembers) { view, values in applyBox(view, values) }
            lazy.property(VisualElementContract.ignoresInput) { view, ignores in view.setIgnoresInput(ignores ?? false) }
            lazy.property(LayoutContract.letsInputThrough) { view, lets in view.passesBeside = lets ?? false }
            lazy.property(LayoutContract.hitShape) { view, shape in view.hitShape = shape }
            lazy.raises(LazyVStackContract.realizedChanged)
        }

        registry.add(LazyHStackContract.self, madeByHost: GTKLazyStackView.self) { lazy in
            lazy.applies(stackMembers + [LazyHStackContract.items]) { view, values in
                view.spacing = values[StackBaseContract.spacing]
                view.padding = values[PaddingElementContract.contentPadding] ?? EdgeInsets(0)
            }
            lazy.applies(boxMembers) { view, values in applyBox(view, values) }
            lazy.property(VisualElementContract.ignoresInput) { view, ignores in view.setIgnoresInput(ignores ?? false) }
            lazy.property(LayoutContract.letsInputThrough) { view, lets in view.passesBeside = lets ?? false }
            lazy.property(LayoutContract.hitShape) { view, shape in view.hitShape = shape }
            lazy.raises(LazyHStackContract.realizedChanged)
        }

        registry.add(LazyVGridContract.self, madeByHost: GTKLazyGridView.self) { grid in
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
            grid.property(LayoutContract.letsInputThrough) { view, lets in view.passesBeside = lets ?? false }
            grid.property(LayoutContract.hitShape) { view, shape in view.hitShape = shape }
            grid.raises(LazyVGridContract.realizedChanged)
        }

        registry.add(LazyHGridContract.self, madeByHost: GTKLazyGridView.self) { grid in
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
            grid.property(LayoutContract.letsInputThrough) { view, lets in view.passesBeside = lets ?? false }
            grid.property(LayoutContract.hitShape) { view, shape in view.hitShape = shape }
            grid.raises(LazyHGridContract.realizedChanged)
        }

        registry.add(ZStackContract.self, create: { _ in GTKZStackView() }) { layout in
            layout.property(PaddingElementContract.contentPadding) { view, padding in view.padding = padding ?? EdgeInsets(0) }
            layout.applies(boxMembers) { view, values in applyBox(view, values) }
            layout.property(VisualElementContract.ignoresInput) { view, ignores in view.setIgnoresInput(ignores ?? false) }
            layout.property(LayoutContract.letsInputThrough) { view, lets in view.passesBeside = lets ?? false }
            layout.property(LayoutContract.hitShape) { view, shape in view.hitShape = shape }
        }

        registry.add(MaskedContract.self, create: { _ in GTKMaskedView() }) { layout in
            layout.property(PaddingElementContract.contentPadding) { view, padding in view.padding = padding ?? EdgeInsets(0) }
            layout.applies(boxMembers) { view, values in applyBox(view, values) }
            layout.property(VisualElementContract.ignoresInput) { view, ignores in view.setIgnoresInput(ignores ?? false) }
            layout.property(LayoutContract.letsInputThrough) { view, lets in view.passesBeside = lets ?? false }
            layout.property(LayoutContract.hitShape) { view, shape in view.hitShape = shape }
        }

        // Where the user moves it is reported by the element, on the display's frames.
        // Design: docs/design/platforms/gtk/layout.md#scrolling
        registry.add(ScrollViewContract.self, create: { _ in GTKScrollView() }) { scroll in
            scroll.applies([
                ScrollViewContract.orientation, ScrollViewContract.verticalScrollIndicators,
                ScrollViewContract.horizontalScrollIndicators, ScrollViewContract.scrollOffset,
                ScrollViewContract.defaultScrollAnchor,
                PaddingElementContract.contentPadding,
            ]) { view, values in
                view.apply(
                    orientation: values[ScrollViewContract.orientation] ?? .vertical,
                    padding: values[PaddingElementContract.contentPadding] ?? EdgeInsets(0),
                    verticalBar: values[ScrollViewContract.verticalScrollIndicators] ?? .automatic,
                    horizontalBar: values[ScrollViewContract.horizontalScrollIndicators] ?? .automatic,
                    defaultAnchor: values[ScrollViewContract.defaultScrollAnchor],
                    offset: values.changed(ScrollViewContract.scrollOffset) ? values[ScrollViewContract.scrollOffset] : nil)
            }
            scroll.applies([
                VisualElementContract.background,
                BorderElementContract.shape, BorderElementContract.stroke, BorderElementContract.strokeWidth,
                LayoutContract.clipPath, LayoutContract.clipFillRule,
            ]) { view, values in
                // A scroller cuts what it shows to its bounds; a shape cuts it to the shape.
                view.setPathClip(values[LayoutContract.clipPath], evenOdd: (values[LayoutContract.clipFillRule] ?? .nonzero) == .evenOdd)
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
        LayoutContract.clipsContent, LayoutContract.clipPath, LayoutContract.clipFillRule,
        LayoutContract.hitPath, LayoutContract.hitFillRule,
    ]

    private static func applyBox<Realized: ElementContract>(_ view: GTKLayoutView, _ values: ElementValues<Realized>) {
        view.setPathClip(values[LayoutContract.clipPath], evenOdd: (values[LayoutContract.clipFillRule] ?? .nonzero) == .evenOdd)
        view.setHitPath(values[LayoutContract.hitPath], evenOdd: (values[LayoutContract.hitFillRule] ?? .nonzero) == .evenOdd)
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

    private static func applyStack<Realized: ElementContract>(_ view: GTKStackView, _ values: ElementValues<Realized>) {
        view.spacing = values[StackBaseContract.spacing]
        view.padding = values[PaddingElementContract.contentPadding] ?? EdgeInsets(0)
    }
}
