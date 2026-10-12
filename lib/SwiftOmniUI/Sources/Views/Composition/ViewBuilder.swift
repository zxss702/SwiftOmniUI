// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The result builder behind the nested syntax. Besides joining statements into
// a child list, every method records where each view was written - a path such
// as "1.else.0" that `Node.key` carries to the differ as the view's key.
// Design: docs/design/views/builders.md#every-statement-records-where-it-stood

/// Collects the views written as consecutive statements into one view - a
/// `TupleView`, whose children the differ splices into the parent.
///
/// `if`, `if/else`, `switch`, `ForEach`, `for`/`in` and `if #available` work
/// inside one.
///
///     VStack {
///         Text("Files")
///
///         ForEach(files, id: \.path) { file in
///             Text(file.name)
///         }
///     }
@resultBuilder
public enum ViewBuilder {
    /// A single view written as a statement.
    public static func buildExpression<Content: View>(_ expression: Content) -> Content {
        expression
    }

    /// A view whose concrete type was given up, written as a statement.
    @_disfavoredOverload
    public static func buildExpression(_ expression: any View) -> AnyView {
        let expression = Carry(expression)
        return onMain { AnyView(expression.value) }
    }

    /// One element written as a statement.
    @_disfavoredOverload
    public static func buildExpression(_ expression: Element) -> TupleView {
        let expression = Carry(expression)
        return onMain { TupleView([expression.value]) }
    }

    /// Several, from something that already produced a list - a `ForEach`'s
    /// items, or a hand-built element array.
    @_disfavoredOverload
    public static func buildExpression(_ expression: [Element]) -> TupleView {
        let expression = Carry(expression)
        return onMain { TupleView(expression.value) }
    }

    /// A single statement, handed back as itself - SwiftUI keeps a lone
    /// view unwrapped, so `init { EmptyView() }` still infers `EmptyView`
    /// rather than a tuple holding one.
    public static func buildBlock<Content: View>(_ content: Content) -> Content {
        content
    }

    /// The statements of the closure, in the order they are written, each
    /// keyed by its statement's number whatever the others produce. Disfavored
    /// next to the single-statement overload so a lone view keeps its own type
    /// - a `Color` written alone binds as `Color`, not `TupleView`, letting
    /// builder parameters constrain to `ShapeStyle` and the like.
    @_disfavoredOverload
    public static func buildBlock(_ components: (any View)...) -> TupleView {
        let components = Carry(components)
        return onMain {
            TupleView(components.value.enumerated().flatMap { at($0.offset, $0.element) })
        }
    }

    /// Nothing written: an empty group.
    public static func buildBlock() -> TupleView {
        onMain { TupleView([]) }
    }

    /// An `if` without an `else`; what it builds is keyed apart from the
    /// statement after it.
    public static func buildOptional(_ component: TupleView?) -> TupleView {
        let component = Carry(component)
        return onMain { component.value?.tagged("some") ?? TupleView([]) }
    }

    /// The same, its body having built a lone view rather than a tuple.
    public static func buildOptional<Content: View>(_ component: Content?) -> TupleView {
        let component = Carry(component)
        return onMain { component.value.map { tagged("some", $0) } ?? TupleView([]) }
    }

    /// The same, its body having produced a bare `any View` - an existential
    /// no `Content: View` can hold.
    public static func buildOptional(_ component: (any View)?) -> TupleView {
        let component = Carry(component)
        return onMain { component.value.map { tagged("some", $0) } ?? TupleView([]) }
    }

    /// The `if` branch of an if/else.
    public static func buildEither(first component: TupleView) -> TupleView {
        let component = Carry(component)
        return onMain { component.value.tagged("if") }
    }

    /// The same, the branch having built a lone view rather than a tuple.
    public static func buildEither<Content: View>(first component: Content) -> TupleView {
        let component = Carry(component)
        return onMain { tagged("if", component.value) }
    }

    /// The same, the branch having produced a bare `any View`.
    public static func buildEither(first component: any View) -> TupleView {
        let component = Carry(component)
        return onMain { tagged("if", component.value) }
    }

    /// The `else` branch. Its views are keyed apart from the `if` branch's, so
    /// switching branches replaces the control rather than editing it.
    public static func buildEither(second component: TupleView) -> TupleView {
        let component = Carry(component)
        return onMain { component.value.tagged("else") }
    }

    /// The same, the branch having built a lone view rather than a tuple.
    public static func buildEither<Content: View>(second component: Content) -> TupleView {
        let component = Carry(component)
        return onMain { tagged("else", component.value) }
    }

    /// The same, the branch having produced a bare `any View`.
    public static func buildEither(second component: any View) -> TupleView {
        let component = Carry(component)
        return onMain { tagged("else", component.value) }
    }

    /// A `for` statement's turns, each keyed by its turn number.
    public static func buildArray(_ components: [TupleView]) -> TupleView {
        let components = Carry(components)
        return onMain { TupleView(components.value.enumerated().flatMap { turn in
            slice(turn.offset, turn.element)
        }) }
    }

    /// The same, its turns having each produced a bare `any View`.
    public static func buildArray(_ components: [any View]) -> TupleView {
        let components = Carry(components)
        return onMain { TupleView(components.value.enumerated().flatMap {
            at($0.offset, $0.element)
        }) }
    }

    /// A `TupleView` where the call already produced one.
    public static func buildFinalResult(_ component: TupleView) -> TupleView {
        component
    }

    /// A statement's own type through, so a leaf's `Body` names it: a body of
    /// one expression is that expression's type, not a `TupleView`.
    public static func buildFinalResult<Content: View>(_ component: Content) -> Content {
        component
    }

    /// What an `if #available(…)` block builds, keyed like every other branch.
    public static func buildLimitedAvailability(_ component: TupleView) -> TupleView {
        let component = Carry(component)
        return onMain { component.value.tagged("available") }
    }

    /// The same, its body having built a lone view rather than a tuple.
    public static func buildLimitedAvailability<Content: View>(_ component: Content) -> TupleView {
        let component = Carry(component)
        return onMain { tagged("available", component.value) }
    }

    /// The same, its body having produced a bare `any View`.
    public static func buildLimitedAvailability(_ component: any View) -> TupleView {
        let component = Carry(component)
        return onMain { tagged("available", component.value) }
    }

    /// Any view under `segment`'s path - what the conditional builders write
    /// for a branch that produced a lone view.
    @MainActor private static func tagged(_ segment: String, _ view: any View) -> TupleView {
        if let tuple = view as? TupleView { return tuple.tagged(segment) }
        if let rows = view as? any LazyRows {
            return TupleView([LazyKeyed(segment: segment, rows: rows)])
        }
        let node = view.node
        if let elements = node.lazyElements {
            return TupleView(elements.map { TupleView.keyed(segment, $0) })
        }
        return TupleView(node.asChildren.map { Keyed(segment: segment, raw: $0) })
    }

    /// The views written under one statement, keyed by the statement's number.
    /// A `LazyRows` stays whole - its rows' keys ride the statement's segment,
    /// and a lazy container still asks for them one at a time. A `TupleView`
    /// keeping its statements - a branch's or a turn's - is keyed the same
    /// way, so the row sources inside stay whole under theirs.
    /// Design: docs/design/views/builders.md#several-views-from-one-statement
    private static func at(_ index: Int, _ view: any View) -> [Element] {
        // Builders run where the body that wrote them stood - the UI thread.
        return MainActor.assumeIsolated { Carry(slice(index, view)) }.value
    }

    @MainActor private static func slice(_ index: Int, _ view: any View) -> [Element] {
        let segment = String(index)
        if let rows = view as? any LazyRows {
            return [LazyKeyed(segment: segment, rows: rows)]
        }
        if let elements = (view as? TupleView)?.lazyElements {
            return elements.map { TupleView.keyed(segment, $0) }
        }
        return leaf(segment, view)
    }

    /// One statement's views as elements: the view itself where it stands as
    /// one node - a control reading the statement (a button's `Label`) finds
    /// the view, not just its node - its nodes otherwise, each keyed by its
    /// own number.
    @MainActor private static func leaf(_ segment: String, _ view: any View) -> [Element] {
        let node = view.node
        if let elements = node.lazyElements {
            return elements.map { TupleView.keyed(segment, $0) }
        }
        let nodes = node.asChildren
        if node.type != .fragment || nodes.isEmpty {
            return [Keyed(segment: segment, raw: view, described: node)]
        }
        guard nodes.count > 1 else {
            return nodes.map { Keyed(segment: segment, raw: $0) }
        }
        return nodes.enumerated().map { Keyed(segment: "\(segment).\($0.offset)", raw: $0.element) }
    }
}

/// One more segment on a node's path, added without touching anything else.
/// Design: docs/design/views/builders.md#the-path-rides-a-wrapper
struct Keyed: Element {
    /// What to put in front of whatever path the element already has.
    let segment: String

    /// The element the statement produced.
    let raw: Element

    /// A builder has already described this statement. Keep the original view for
    /// label readers, but do not repeat its node getter or state scan.
    private let described: Node?

    init(segment: String, raw: Element, described: Node? = nil) {
        self.segment = segment
        self.raw = raw
        self.described = described
    }

    /// The same node, with the segment on the front of its path.
    var node: Node {
        var node = described ?? raw.node
        node.key = node.key.map { "\(segment).\($0)" } ?? segment
        return node
    }
}

/// The view a builder closure's lone statement kept, where it kept one - the
/// statement itself, so a control reading it (a button's `Label`) finds the
/// view - or the closure's result where the statement was several views or
/// its node alone.
@MainActor func unwrappedStatement(_ view: any View) -> any View {
    guard let elements = (view as? TupleView)?.lazyElements, elements.count == 1,
          let keyed = elements[0] as? Keyed, let kept = keyed.raw as? any View
    else { return view }
    return kept
}
