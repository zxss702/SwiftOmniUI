// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// A grid that fills its columns with its children row first, built a row at
/// a time as a scroller shows them - SwiftUI's `LazyVGrid`:
///
///     ScrollView {
///         LazyVGrid(
///             columns: [
///                 GridItem(.flexible(minimum: 128, maximum: 764), spacing: 12, alignment: .leading),
///                 GridItem(.flexible(minimum: 128, maximum: 764), spacing: 12, alignment: .leading),
///             ],
///             spacing: 12
///         ) {
///             ForEach(entries) { entry in EntryCell(entry: entry) }
///         }
///     }
///
/// A `.fixed` column is that many points, a `.flexible` one a share of what
/// is left, and an `.adaptive` one stands for as many as fit - the host
/// counts them for the room it has, and asks for the cells of the rows in
/// view.
public struct LazyVGrid: View {
    /// What the grid shows, as the builder described it.
    private let content: () -> any View

    /// The columns the cells fill, row first.
    private let columns: [GridItem]

    /// Where a cell's content sits across its column, where the column's
    /// own alignment does not say.
    private let alignment: HorizontalAlignment

    /// The room between one row and the next; nil is the platform's own.
    private let spacing: Double?

    /// The cells the host has asked for.
    @State private var realized: [String] = []
    @State private var realizedGeneration = 0

    /// The identity index survives parent updates; builders stay current.
    @State private var children = LazyChildren()

    /// A grid filling `columns` with what the closure describes, row first,
    /// its cells centered across where a column does not say.
    ///
    /// - Parameters:
    ///   - columns: the columns to fill; an `.adaptive` item stands for as
    ///     many as fit in the room the grid is given.
    ///   - content: the cells, in order.
    public init(columns: [GridItem], @ViewBuilder content: @escaping () -> any View) {
        self.init(columns: columns, alignment: .center, spacing: nil, content: content)
    }

    /// A grid filling `columns` with what the closure describes, row first.
    ///
    /// - Parameters:
    ///   - columns: the columns to fill; an `.adaptive` item stands for as
    ///     many as fit in the room the grid is given.
    ///   - alignment: where a cell's content sits across its column, where
    ///     the column's own alignment does not say.
    ///   - content: the cells, in order.
    public init(
        columns: [GridItem], alignment: HorizontalAlignment, @ViewBuilder content: @escaping () -> any View
    ) {
        self.init(columns: columns, alignment: alignment, spacing: nil, content: content)
    }

    /// A grid filling `columns` with what the closure describes, row first,
    /// the rows `spacing` apart.
    public init(
        columns: [GridItem], spacing: Double?, @ViewBuilder content: @escaping () -> any View
    ) {
        self.init(columns: columns, alignment: .center, spacing: spacing, content: content)
    }

    /// A grid filling `columns` with what the closure describes, row first.
    ///
    /// - Parameters:
    ///   - spacing: the room between one row and the next - the room between
    ///     two columns is each column item's own `spacing`.
    ///   - content: the cells, in order.
    public init(
        columns: [GridItem], alignment: HorizontalAlignment, spacing: Double?,
        @ViewBuilder content: @escaping () -> any View
    ) {
        self.columns = columns
        self.alignment = alignment
        self.spacing = spacing
        self.content = content
    }

    /// The grid's element, built for the window the host last named.
    public var body: some View {
        var element = LazyVGridElement()
        element.node.write(LazyVGridContract.flowColumns, columns)
        element.node.describe(LazyVGridContract.columnSpacing, columns.lazy.compactMap(\.spacing).first)
        if let spacing { element.node.write(LazyVGridContract.rowSpacing, spacing) }

        let count = max(columns.count, 1)
        let held = $realized
        let heldGeneration = $realizedGeneration
        element.node.lazyRequestGeneration = realizedGeneration
        element.node.lazyRequestWindow = heldGeneration.lender.map(ObjectIdentifier.init)
        element.node.lazyRequestGenerationValue = { heldGeneration.wrappedValue }
        let across = alignment.axis
        element.node.write(ViewContract.horizontalContentAlignment, across)
        children.take(content(), into: &element.node, realized: held) { cell, index in
            let item = columns.isEmpty ? GridItem() : columns[index % count]
            let over = item.alignment?.horizontal.axis ?? .center
            if cell.props[.horizontalAlignment] == nil {
                cell.write(ViewContract.horizontalAlignment,
                           cell.props[.maximumWidth]?.number == .infinity ? .fill : over)
            }
            if let down = item.alignment?.vertical.axis, down != .fill {
                cell.write(ViewContract.verticalAlignment, down)
            }
        }
        element.node.addHandler(LazyVGridContract.realizedChanged.token) {
            guard let request = LazyWindowRequest.decode(
                EventBuffer.current, by: LazyVGridContract.realizedChanged.name) else { return }
            if request.identities != held.wrappedValue { held.wrappedValue = request.identities }
            if let generation = request.generation { heldGeneration.wrappedValue = generation }
        }
        return element
    }
}

/// A grid that fills its rows with its children column first, built a column
/// at a time as a scroller shows them - `LazyVGrid` across, SwiftUI's
/// `LazyHGrid`:
///
///     ScrollView(.horizontal) {
///         LazyHGrid(rows: [GridItem(.fixed(80)), GridItem(.fixed(80))]) { … }
///     }
public struct LazyHGrid: View {
    /// What the grid shows, as the builder described it.
    private let content: () -> any View

    /// The rows the cells fill, column first.
    private let rows: [GridItem]

    /// Where a cell's content sits down its row, where the row's own
    /// alignment does not say.
    private let alignment: VerticalAlignment

    /// The room between one column and the next; nil is the platform's own.
    private let spacing: Double?

    /// The cells the host has asked for.
    @State private var realized: [String] = []
    @State private var realizedGeneration = 0

    /// The identity index survives parent updates; builders stay current.
    @State private var children = LazyChildren()

    /// A grid filling `rows` with what the closure describes, column first,
    /// its cells centered down where a row does not say.
    public init(rows: [GridItem], @ViewBuilder content: @escaping () -> any View) {
        self.init(rows: rows, alignment: .center, spacing: nil, content: content)
    }

    /// A grid filling `rows` with what the closure describes, column first.
    ///
    /// - Parameters:
    ///   - alignment: where a cell's content sits down its row, where the
    ///     row's own alignment does not say.
    public init(
        rows: [GridItem], alignment: VerticalAlignment, @ViewBuilder content: @escaping () -> any View
    ) {
        self.init(rows: rows, alignment: alignment, spacing: nil, content: content)
    }

    /// A grid filling `rows` with what the closure describes, column first,
    /// the columns `spacing` apart.
    public init(
        rows: [GridItem], spacing: Double?, @ViewBuilder content: @escaping () -> any View
    ) {
        self.init(rows: rows, alignment: .center, spacing: spacing, content: content)
    }

    /// A grid filling `rows` with what the closure describes, column first.
    ///
    /// - Parameters:
    ///   - spacing: the room between one column and the next - the room
    ///     between two rows is each row item's own `spacing`.
    public init(
        rows: [GridItem], alignment: VerticalAlignment, spacing: Double?,
        @ViewBuilder content: @escaping () -> any View
    ) {
        self.rows = rows
        self.alignment = alignment
        self.spacing = spacing
        self.content = content
    }

    /// The grid's element, built for the window the host last named.
    public var body: some View {
        var element = LazyHGridElement()
        element.node.write(LazyHGridContract.flowRows, rows)
        element.node.describe(LazyHGridContract.rowSpacing, rows.lazy.compactMap(\.spacing).first)
        if let spacing { element.node.write(LazyHGridContract.columnSpacing, spacing) }

        let count = max(rows.count, 1)
        let held = $realized
        let heldGeneration = $realizedGeneration
        element.node.lazyRequestGeneration = realizedGeneration
        element.node.lazyRequestWindow = heldGeneration.lender.map(ObjectIdentifier.init)
        element.node.lazyRequestGenerationValue = { heldGeneration.wrappedValue }
        let down = alignment.axis
        element.node.write(ViewContract.verticalContentAlignment, down)
        children.take(content(), into: &element.node, realized: held) { cell, index in
            let item = rows.isEmpty ? GridItem() : rows[index % count]
            let over = item.alignment?.vertical.axis ?? .center
            if cell.props[.verticalAlignment] == nil {
                cell.write(ViewContract.verticalAlignment,
                           cell.props[.maximumHeight]?.number == .infinity ? .fill : over)
            }
            if let across = item.alignment?.horizontal.axis, across != .fill {
                cell.write(ViewContract.horizontalAlignment, across)
            }
        }
        element.node.addHandler(LazyHGridContract.realizedChanged.token) {
            guard let request = LazyWindowRequest.decode(
                EventBuffer.current, by: LazyHGridContract.realizedChanged.name) else { return }
            if request.identities != held.wrappedValue { held.wrappedValue = request.identities }
            if let generation = request.generation { heldGeneration.wrappedValue = generation }
        }
        return element
    }
}

/// The element a `LazyVGrid` describes - the grid the host virtualizes.
struct LazyVGridElement: LayoutView, GridProperties {
    var node = Node(contract: LazyVGridContract.self)
}

/// The element a `LazyHGrid` describes - the grid the host virtualizes.
struct LazyHGridElement: LayoutView, GridProperties {
    var node = Node(contract: LazyHGridContract.self)
}
