// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// A layout an author writes: `sizeThatFits` and `placeSubviews` run where the
// container lays out, on the host's own pass, over `LayoutSubview` adapters
// of its children - the layout object rides the node to the host, and
// `.layoutValue` rides the child's.
// Design: docs/design/views/measured-layouts.md#custom-layouts

/// A tag a child carries for its layout to read - `.layoutValue` writes it,
/// `subview[K.self]` answers it inside the layout's methods.
///
///     struct FlowLineBreakLayoutValueKey: LayoutValueKey {
///         static let defaultValue = false
///     }
public protocol LayoutValueKey {
    /// What the key carries.
    associatedtype Value

    /// What a child that wrote nothing answers.
    static var defaultValue: Value { get }
}

/// Facts a `Layout` declares about itself.
public struct LayoutProperties: Sendable {
    /// The axis the layout's children flow along where it has one - a host
    /// may read it to answer the layout direction's questions; nil where the
    /// layout has no direction of flow.
    public var stackOrientation: Axis?

    /// Properties with nothing declared.
    public init() {}
}

/// A custom arrangement of a container's children, as SwiftUI's `Layout`
/// names it: the container asks `sizeThatFits` for its size and runs
/// `placeSubviews` to position each child, the `cache` carrying whatever the
/// measure pass learned for the place pass.
///
///     struct FlowLayout: Layout {
///         func sizeThatFits(
///             proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache
///         ) -> Size { ... }
///         func placeSubviews(
///             in bounds: Rect, proposal: ProposedViewSize,
///             subviews: Subviews, cache: inout Cache
///         ) { ... }
///     }
///
/// A layout is used where a stack is: `FlowLayout { subviews }` builds a
/// container arranged by it.
public protocol Layout: Sendable {
    /// Whatever the layout keeps between its measure and place passes.
    associatedtype Cache

    /// The children the container measures and places, in written order.
    typealias Subviews = LayoutSubviews

    /// Facts about the layout a host may read.
    static var layoutProperties: LayoutProperties { get }

    /// The cache the layout keeps for one arrangement, made at the start of
    /// a measure; a layout keeping nothing declares `Cache == Void` and gets
    /// this for free.
    func makeCache(subviews: Subviews) -> Cache

    /// The cache refreshed as the children change - same layout, new
    /// subviews; the default keeps what was made.
    func updateCache(_ cache: inout Cache, subviews: Subviews)

    /// The container's size for the room `proposal` offers.
    func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache
    ) -> Size

    /// Each child placed inside `bounds`; `subview.place(at:proposal:)` is
    /// where one goes.
    func placeSubviews(
        in bounds: Rect, proposal: ProposedViewSize,
        subviews: Subviews, cache: inout Cache
    )

    /// A layout is not a view itself - `callAsFunction` makes the container.
    associatedtype Body: View = Never
}

extension Layout {
    /// No declared facts.
    public static var layoutProperties: LayoutProperties { LayoutProperties() }

    /// Nothing to refresh.
    public func updateCache(_ cache: inout Cache, subviews: Subviews) {}

    /// The container this layout arranges - `FlowLayout { subviews }`:
    ///
    ///     FlowLayout(spacing: 4) {
    ///         ForEach(items) { ItemView($0) }
    ///     }
    ///
    /// - Parameter content: The children the layout measures and places.
    public func callAsFunction<Content: View>(
        @ViewBuilder _ content: () -> Content
    ) -> CustomLayoutContainer<Self, Content> {
        CustomLayoutContainer(layout: self, content: content())
    }
}

extension Layout where Cache == Void {
    /// Nothing kept between the passes.
    public func makeCache(subviews: Subviews) -> Void {}
}

extension Layout where Body == Never {
    /// A layout draws nothing of its own.
    public var body: Never { fatalError("a Layout has no body of its own") }
}

/// One child as a `Layout` sees it: measure it, read its dimensions or the
/// tags `.layoutValue` wrote on it, and place it.
///
/// The host builds each subview over its own child; its answers are measured
/// answers, not the zeros `ViewDimensions` reads ahead of layout.
public struct LayoutSubview: @unchecked Sendable {
    /// The `.layoutValue` tags the child carries, by key identity.
    let layoutValues: [ObjectIdentifier: Any]

    /// The child's size for a proposal - the host's own measure, which
    /// negotiates the offered width: a proposal's height goes unanswered on
    /// hosts that measure by width alone.
    let measureSize: (ProposedViewSize) -> Size

    /// The child's size and measured guide answers for a proposal.
    let measureDimensions: (ProposedViewSize) -> ViewDimensions

    /// Where the child goes: its `anchor` point at `position`, sized for
    /// `proposal`.
    let placeView: (Point, UnitPoint, ProposedViewSize) -> Void

    /// How loudly the child asked for its size - `.layoutPriority` carried.
    public var priority: Double

    /// A subview over the host's adapters.
    @_spi(Host) public init(
        layoutValues: [ObjectIdentifier: Any],
        priority: Double,
        measureSize: @escaping (ProposedViewSize) -> Size,
        measureDimensions: @escaping (ProposedViewSize) -> ViewDimensions,
        placeView: @escaping (Point, UnitPoint, ProposedViewSize) -> Void
    ) {
        self.layoutValues = layoutValues
        self.priority = priority
        self.measureSize = measureSize
        self.measureDimensions = measureDimensions
        self.placeView = placeView
    }

    /// The child's size for `proposal`.
    public func sizeThatFits(_ proposal: ProposedViewSize) -> Size {
        measureSize(proposal)
    }

    /// The child's dimensions for `proposal` - its measured size and the
    /// answers its alignment guides and baselines give there.
    public func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
        measureDimensions(proposal)
    }

    /// Places the child: its `anchor` point lands on `position`, its size the
    /// one it takes for `proposal`.
    public func place(
        at position: Point,
        anchor: UnitPoint = .topLeading,
        proposal: ProposedViewSize
    ) {
        placeView(position, anchor, proposal)
    }

    /// The tag `.layoutValue(key: K.self, value:)` wrote on this child, or
    /// the key's default.
    public subscript<K: LayoutValueKey>(key: K.Type) -> K.Value {
        layoutValues[ObjectIdentifier(key)] as? K.Value ?? K.defaultValue
    }
}

/// The children a `Layout` arranges, in written order.
public struct LayoutSubviews: RandomAccessCollection, Sendable {
    /// The subviews.
    let elements: [LayoutSubview]

    /// The direction text flows inside the container.
    public var layoutDirection: LayoutDirection

    /// The subviews of a container about to measure or place.
    @_spi(Host) public init(
        _ elements: [LayoutSubview],
        direction: LayoutDirection = .leftToRight
    ) {
        self.elements = elements
        self.layoutDirection = direction
    }

    /// The first subview's position.
    public var startIndex: Int { elements.startIndex }

    /// One past the last subview's position.
    public var endIndex: Int { elements.endIndex }

    /// The subview at `position`, in written order.
    public subscript(position: Int) -> LayoutSubview { elements[position] }
}

/// A layout object as a node carries it: the concrete `Layout` and its
/// methods with `Cache` opened, the cache made on the first measure.
@_spi(Host) public final class LayoutBox: @unchecked Sendable {
    /// `updateCache`, refreshing the cache as children change.
    private let refresh: (LayoutSubviews) -> Void

    /// `sizeThatFits` with the cache opened.
    private let sizeOf: (ProposedViewSize, LayoutSubviews) -> Size

    /// `placeSubviews` with the cache opened.
    private let placeAll: (Rect, ProposedViewSize, LayoutSubviews) -> Void

    /// The box of `layout`.
    public init<L: Layout>(_ layout: L) {
        var cache: L.Cache?

        func ensure(_ subviews: LayoutSubviews) -> L.Cache {
            if let made = cache { return made }
            let made = layout.makeCache(subviews: subviews)
            cache = made
            return made
        }

        refresh = { subviews in
            var current = ensure(subviews)
            layout.updateCache(&current, subviews: subviews)
            cache = current
        }
        sizeOf = { proposal, subviews in
            var current = ensure(subviews)
            defer { cache = current }
            return layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &current)
        }
        placeAll = { bounds, proposal, subviews in
            var current = ensure(subviews)
            defer { cache = current }
            layout.placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &current)
        }
    }

    /// The layout's `updateCache`, run as the children change.
    public func update(subviews: LayoutSubviews) { refresh(subviews) }

    /// The layout's `sizeThatFits`.
    public func measure(
        proposal: ProposedViewSize, subviews: LayoutSubviews
    ) -> Size {
        sizeOf(proposal, subviews)
    }

    /// The layout's `placeSubviews`.
    public func place(
        in bounds: Rect, proposal: ProposedViewSize, subviews: LayoutSubviews
    ) {
        placeAll(bounds, proposal, subviews)
    }
}

/// The code objects one element lends its host: the layout a `CustomLayout`
/// container arranges by, and the `.layoutValue` tags a child carries. What
/// the differ keeps by element id so a host can pull them mid-layout.
struct NodeCode {
    /// The container's layout object.
    var layout: LayoutBox?

    /// The child's `.layoutValue` tags, by key identity.
    var values: [ObjectIdentifier: Any] = [:]

    /// A Canvas renderer the host asks for at its allocated size.
    var canvas: CanvasBox?
}

/// The container a `callAsFunction` on a `Layout` makes: its children stand
/// as its subviews, the layout object riding the node to the host.
public struct CustomLayoutContainer<L: Layout, Content: View>: LayoutView {
    /// The node this container describes.
    public var node: Node

    /// A container of `content` arranged by `layout`.
    init(layout: L, content: Content) {
        node = Node(contract: CustomLayoutContract.self, children: [content.node])
        node.customLayout = LayoutBox(layout)
    }
}

extension View {
    /// A tag this view's layout reads through `subview[K.self]` - invisible
    /// to every layout but one that asks for `K`:
    ///
    ///     Color.clear
    ///         .layoutValue(key: FlowLineBreakLayoutValueKey.self, value: true)
    ///
    /// - Parameters:
    ///   - key: Which layout value to write.
    ///   - value: The tag this child carries.
    public func layoutValue<K: LayoutValueKey>(
        key: K.Type, value: K.Value
    ) -> ModifiedContent {
        revised { $0.layoutValues[ObjectIdentifier(key)] = value }
    }
}
