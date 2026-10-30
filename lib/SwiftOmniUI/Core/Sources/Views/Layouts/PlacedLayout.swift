// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// A layout of the author's own: a run of views, and arithmetic an engine runs
// on the host's frames saying where each goes and how it is turned.
// Design: docs/design/views/measured-layouts.md#placed-layout

/// Views placed by arithmetic of your own.
///
/// An engine answers one `Placement` per view - where it goes, how it is
/// turned, how opaque it is, which is drawn over which - and writes them as a
/// `PlacedRun` on the state this layout is placed by. It runs again whenever a
/// value it follows moves, with no view rebuilt.
///
///     @State private var ring = PlacedRun()
///     @State private var room = Rect(0, 0, 0, 0)
///
///     PlacedLayout(planets, id: \.name) { planet in
///         Ellipse().fill(planet.colour)
///     }
///     .placement($ring)
///     .frame($room)
///     .engine(following: $room) { _ in
///         ring = PlacedRun(planets.indices.map { index in
///             let angle = Double(index) / Double(planets.count) * 2 * .pi
///             let radius = min(room.width, room.height) / 2 - 40
///
///             return Placement(Rect(
///                 room.width / 2 + cos(angle) * radius - 24,
///                 room.height / 2 + sin(angle) * radius - 24,
///                 48,
///                 48))
///         })
///     }
///
/// A rectangle is in device units from the layout's own top left; views may
/// overlap or sit outside the room, and `zIndex` settles which is on top. On
/// an axis nothing constrains - inside a scroller - keep the answer bounded:
/// placements that grow with the room grow the room, and the layout never
/// settles.
public struct PlacedLayout<Items: RandomAccessCollection, Id: Hashable>: View {
    /// One view being placed: its identity, its index and its item.
    private struct Slot {
        let identity: String
        let index: Int
        let item: Items.Element
    }

    /// The items and the view for each, behind a class so the state walk stops
    /// before the items.
    /// Design: docs/design/views/composition.md#items-held-behind-a-class
    private let source: Source

    private var travel = Animation.inherited

    /// What is drawn over each placed view at its placement's `shade`, if any.
    private var mask: Element?

    /// The state the run of placements is carried on, where there is one.
    private var run: Binding<PlacedRun>?

    /// A layout of views, one per item, placed by the run of placements an
    /// engine writes into the state `.placement(_:)` is given.
    ///
    /// - Parameters:
    ///   - items: what to place, one view each.
    ///   - id: which part of an item is its identity - distinct across the
    ///     items, and stable while the item means the same view, so a view
    ///     keeps its place, its state and its animation when the run changes.
    ///   - content: the view for one item.
    public init(
        _ items: Items,
        id: KeyPath<Items.Element, Id>,
        content: @escaping (Items.Element) -> any View
    ) {
        self.source = Source(items: items, path: id, view: content)
    }

    /// The state this layout's placements are carried on.
    ///
    ///     PlacedLayout(cards, id: \.name) { face($0) }.placement($run)
    ///
    /// One placement a view, in order; a run shorter than the views leaves the
    /// rest where they were. `PlacedRun(placements)` puts the views there at
    /// once, which arithmetic re-run every frame wants, and
    /// `PlacedRun(placements, animation:)` animates them there.
    ///
    /// - Parameter number: the run of placements.
    /// - Returns: the layout, placed by that state.
    @_spi(Host) public func placement(_ number: Binding<PlacedRun>) -> PlacedLayout {
        var copy = self
        copy.run = number
        return copy
    }

    /// How a run written with `animation: .inherited` animates the views to their
    /// new places - their turn and fade with them. A run that states its own
    /// animation is unmoved by it.
    ///
    ///     PlacedLayout(cards, id: \.self) { … }
    ///         .placement($run)
    ///         .animation(.easeOut(duration: 0.3))
    ///
    /// - Parameter animation: how a run written `.inherited` animates; `nil`
    ///   for none.
    /// - Returns: the layout, moving that way.
    public func animation(_ animation: Animation?) -> PlacedLayout {
        var copy = self
        copy.travel = animation ?? .none
        return copy
    }

    /// What to draw over a placed view to darken it, at the opacity its
    /// placement answers as `shade`.
    ///
    ///     PlacedLayout(cards, id: \.name) { face($0) }
    ///         .placement($run)
    ///         .shade(ColorPicker(.black).cornerRadius(14))
    ///
    /// Give it the corners the views have. Where views overlap, a shade darkens
    /// a far view without showing the one behind it, as fading it would.
    ///
    /// - Parameter view: what to draw over each placed view.
    /// - Returns: the layout, shaded.
    @_spi(Host) public func shade(_ view: Element) -> PlacedLayout {
        var copy = self
        copy.mask = view
        return copy
    }

    /// The views, each wrapped for the host to place from the run.
        public var body: some View { AnyView(content) }

        private var content: any View {
        let held = source

        let slots = held.items.enumerated().map { offset, item in
            Slot(
                identity: String(describing: item[keyPath: held.path]),
                index: offset,
                item: item)
        }

        let build = held.view
        let over = mask

        // No placement is described: each arrives on the state, on the host's frames.
        let views = ZStack {
            ForEach(slots, id: \.identity) { slot in
                PlacedLayout.wrapped(build(slot.item), under: over)
            }
        }
        .animation(travel)

        guard let number = run else {
            // With no placement state the views lie over one another.
            return views
        }

        return views.setValue(ViewContract.area.token, on: number, mode: .out, kind: .placement)
    }

    /// What the layout was handed, behind a reference. See `source`.
    private final class Source {
        /// What to place, one view each.
        let items: Items

        /// Which part of an item is its identity.
        let path: KeyPath<Items.Element, Id>

        /// The view for one item.
        let view: (Items.Element) -> any View

        /// What the initializer was handed.
        init(
            items: Items,
            path: KeyPath<Items.Element, Id>,
            view: @escaping (Items.Element) -> any View
        ) {
            self.items = items
            self.path = path
            self.view = view
        }
    }

    /// One view inside the container the host writes its placement onto, so
    /// the author's own properties on the view are never overwritten; a shade
    /// is the container's second child.
    /// Design: docs/design/views/measured-layouts.md#placed-layout
    private static func wrapped(_ view: any View, under mask: Element?) -> any View {
        guard let mask else { return Grid { AnyView(view) } }

        return Grid {
            AnyView(view)
            ModifiedContent(node: mask.node)
        }
    }
}
