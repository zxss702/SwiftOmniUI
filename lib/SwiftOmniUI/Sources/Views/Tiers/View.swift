// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// The properties every positioned view has: the value half of a control's
/// contract, shared by the control and its `Style`, including where it sits in
/// a Grid or a ZStack.
@preconcurrency @MainActor public protocol ViewProperties: VisualElementProperties {}

/// A piece of interface: a control, a layout, or a view composed of other
/// views.
///
///     struct Header: View {
///         private let title: String
///
///         init(_ title: String) {
///             self.title = title
///         }
///
///         var body: some View {
///             Text(title).fontSize(28).fontAttributes(.bold)
///         }
///     }
///
/// `body` is read the first time the view is built, and again when what it was
/// built with or a state it read changes; otherwise the view is carried
/// whole. A view that draws itself - a `Text`, a `VStack` - has no body and
/// declares none; its `Body` is `Never`.
///
/// Configure a composed view the way every control is configured: what it is
/// goes in the initializer, with no default, and what a caller may leave out
/// is a modifier written after it, which lands on the view's root:
///
///     Header("Settings")
///         .padding(0, 8)
///         .gridRow(1)
@preconcurrency @MainActor public protocol View: Element, Page {
    /// What this view is made of, read each time the view is built. A view
    /// that draws itself has no body - `Never` says so.
    associatedtype Body: View = Never

    /// The view this one is made of.
    @ViewBuilder var body: Body { get }
}

extension View {
    /// A composed view as a node: a placeholder the differ expands once it
    /// knows whether this view stood here last render - so its `@State` is
    /// kept. A view that draws itself provides its own `node`, so this default
    /// runs only for composed views.
    /// Design: docs/design/views/composition.md#a-composed-view-is-a-placeholder
    public var node: Node {
        Node.composed(self, type: String(reflecting: Self.self)) { body.node }
    }
}

extension View where Body == Never {
    /// A view that draws itself has no body; it is never read.
    public var body: Never { fatalError("\(Self.self) draws itself - it has no body") }
}

/// The absence of a view: the `Body` of a view that draws itself, and the
/// `Body` of a scene that draws itself.
extension Never: View {
    /// Never is built - never read.
    public var node: Node { fatalError("Never is not a view") }
}

extension View {
    /// One modifier step on any view: the change lands on the view's root
    /// node, and the result is opaque the way `some View` is.
    func revised(_ change: (inout Node) -> Void) -> ModifiedContent {
        var node = node
        change(&node)
        return ModifiedContent(node: node)
    }

    /// Sets a property by its token - what the typed `setValue` is written
    /// over, and every modifier that writes a value it built itself.
    func setting(_ property: Prop, _ value: PropValue) -> ModifiedContent {
        revised { $0.props[property] = value }
    }

    /// Sets one of this view's properties to a value of the type its contract
    /// declares.
    func setting<Owner: Contract, Value: HostRepresentable>(
        _ property: ElementProperty<Owner, Value>,
        _ value: Value
    ) -> ModifiedContent {
        setting(property.token, value.propValue)
    }

    /// A marker the view's container reads to name it - a `Picker`'s choice
    /// or a `TabView`'s tab - for a view composed of others.
    @_disfavoredOverload
    public func tag<V: Hashable & HostRepresentable>(_ value: V) -> ModifiedContent {
        setting(ViewContract.tag, value.propValue)
    }

    /// What the keyboard's return key is captioned - Go, Search, Send, Next -
    /// on a view holding a field that submits. A `SecureField`, or any
    /// composition whose field is inside rather than the view itself.
    public func submitLabel(_ value: ReturnKey) -> ModifiedContent {
        setting(TextFieldContract.submitLabel.token, value.propValue)
    }

    /// `submitLabel` from a state, `$x`: the host sets each new value as it
    /// stands, and no view is rebuilt for it.
    @_disfavoredOverload @_spi(Host)
    public func submitLabel(_ state: Binding<ReturnKey>) -> ModifiedContent {
        revised { $0.drivePlain(TextFieldContract.submitLabel.token, by: state) }
    }

    /// The accent colour the controls inside this view draw with - on a
    /// `ProgressView`, a `Toggle`, or any composition whose tintable element
    /// is inside rather than the view itself.
    @_disfavoredOverload
    public func tint(_ value: Color) -> ModifiedContent {
        setting(TintElementContract.tint.token, value.propValue)
    }

    /// The shadow this view drops - the SwiftUI spelling:
    ///
    ///     ColorPicker(.cornflowerBlue)
    ///         .shadow(radius: 4)
    ///         .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
    public func shadow(
        color: Color = .black.opacity(1.0 / 3), radius: Double, x: Double = 0, y: Double = 0
    ) -> ModifiedContent {
        setting(VisualElementContract.shadow, DropShadow(color: color, radius: radius, x: x, y: y))
    }

    /// How big the controls inside this view draw - the SwiftUI spelling:
    ///
    ///     ProgressView()
    ///         .controlSize(.small)
    ///
    /// Set on a control it sizes that control; set on a container it sizes
    /// every control inside, the way `.controlSize` is inherited in SwiftUI.
    public func controlSize(_ size: ControlSize) -> ModifiedContent {
        revised { $0.writeInherited(ControlSizeElementContract.controlSize, size) }
    }
}

extension View {
    /// Hears one of this view's events that carries nothing, written with its
    /// contract.
    @_spi(Host) public func hearing<Owner: Contract>(
        _ event: ElementEvent<Owner, Void>,
        _ handler: @escaping EventHandler
    ) -> ModifiedContent {
        revised {
            $0.addHandler(event.token) {
                guard MemberValues.carried(EventBuffer.current, by: event.name) != nil else { return }
                try await handler()
            }
        }
    }

    /// Hears one of this view's events, its value handed over as the type its
    /// contract declares.
    @_spi(Host) public func hearing<Owner: Contract, Value: HostRepresentable>(
        _ event: ElementEvent<Owner, Value>,
        _ handler: @escaping ValueEventHandler<Value>
    ) -> ModifiedContent {
        revised {
            $0.addHandler(event.token) {
                guard let value = MemberValues.carried(
                    EventBuffer.current, by: event.name, as: Value.self)
                else { return }
                try await handler(value)
            }
        }
    }

    /// Hears one of this view's events that carries two values.
    @_spi(Host) public func hearing<Owner: Contract, First: HostRepresentable, Second: HostRepresentable>(
        _ event: ElementEvent<Owner, (First, Second)>,
        _ handler: @escaping ValueEventHandler<First, Second>
    ) -> ModifiedContent {
        revised {
            $0.addHandler(event.token) {
                guard let (first, second) = MemberValues.carried(
                    EventBuffer.current, by: event.name, as: First.self, Second.self)
                else { return }
                try await handler(first, second)
            }
        }
    }

    /// Hears one of this view's events that carries three values.
    @_spi(Host) public func hearing<
        Owner: Contract, First: HostRepresentable, Second: HostRepresentable, Third: HostRepresentable
    >(
        _ event: ElementEvent<Owner, (First, Second, Third)>,
        _ handler: @escaping ValueEventHandler<First, Second, Third>
    ) -> ModifiedContent {
        revised {
            $0.addHandler(event.token) {
                guard let (first, second, third) = MemberValues.carried(
                    EventBuffer.current, by: event.name, as: First.self, Second.self, Third.self)
                else { return }
                try await handler(first, second, third)
            }
        }
    }
}

extension ViewProperties {
    /// Adds space around the preceding view. Each view call encloses its
    /// earlier modifiers, so a later background includes this space.
    ///
    ///     Text("Total").padding(16)                        // all four sides
    ///     Text("Total").padding(EdgeInsets(16, 0, 0, 0))   // the left edge only
    ///     Text("Total").padding(.horizontal, 16)           // left and right
    ///     Text("Total").padding()                          // the library's default
    public func padding(_ value: EdgeInsets) -> Modified {
        modified { node in
            if Self.self is any View.Type {
                node = node.mappingLayoutLeaves {
                    $0.wrapPadding()
                    $0.props[.contentPadding] = value.propValue
                }
            } else {
                node.write(ViewContract.padding, value)
            }
        }
    }

    /// The same space on the edges named, `nil` for the library's default.
    ///
    ///     Text("Total").padding(.horizontal, 16)
    ///     Text("Total").padding(.top)
    public func padding(_ edges: Edge.Set = .all, _ length: Double? = nil) -> Modified {
        let amount = length ?? libraryDefaultPadding
        var insets = EdgeInsets(0, 0, 0, 0)
        if edges.contains(.leading) { insets.left = amount }
        if edges.contains(.top) { insets.top = amount }
        if edges.contains(.trailing) { insets.right = amount }
        if edges.contains(.bottom) { insets.bottom = amount }
        return padding(insets)
    }

    /// Left and right, then top and bottom. This library's own.
    @_spi(Host) public func padding(_ horizontalSize: Double, _ verticalSize: Double) -> Modified {
        padding(EdgeInsets(horizontalSize, verticalSize))
    }

    /// Each side in turn: left, top, right, bottom. This library's own.
    @_spi(Host) public func padding(_ left: Double, _ top: Double, _ right: Double, _ bottom: Double) -> Modified {
        padding(EdgeInsets(left, top, right, bottom))
    }

    /// The same space on all four sides.
    public func padding(_ length: Double) -> Modified {
        padding(EdgeInsets(length, length, length, length))
    }

    /// The same space on all four sides, as a number literal.
    public func padding(_ all: Int) -> Modified {
        padding(EdgeInsets(Double(all)))
    }

    /// `padding` from a state, `$x`: the host animates the property to each
    /// new value, and no view is rebuilt for it. This library's own.
    @_spi(Host) public func padding(_ state: Binding<EdgeInsets>) -> Modified {
        modified { node in
            if Self.self is any View.Type {
                node = node.mappingLayoutLeaves {
                    $0.wrapPadding()
                    $0.driveJourney(.contentPadding, by: state)
                }
            } else {
                node.driveJourney(ViewContract.padding, by: state)
            }
        }
    }

    /// The same space on all four sides, from a state, `$x`. This library's own.
    @_spi(Host) public func padding(_ state: Binding<Double>) -> Modified {
        padding(state.convert { EdgeInsets($0, $0, $0, $0) })
    }

    /// The same space on all four sides, from a state holding a whole number, `$x`. This library's own.
    @_spi(Host) public func padding(_ state: Binding<Int>) -> Modified {
        padding(state.convert { EdgeInsets(Double($0)) })
    }

    /// How the view uses the width its parent offers - filling it, or sitting
    /// at one end of it. This library's own: `VStack(alignment:)` and
    /// `.frame(alignment:)` are the view-facing shapes.
    ///
    ///     Button("Save").horizontalAlignment(.center)
    @_spi(Host) public func horizontalAlignment(_ value: AxisAlignment) -> Modified {
        setValue(ViewContract.horizontalAlignment, value)
    }

    /// The same, for the height.
    @_spi(Host) public func verticalAlignment(_ value: AxisAlignment) -> Modified {
        setValue(ViewContract.verticalAlignment, value)
    }

    /// `horizontalAlignment` from a state, `$x`: the host sets each new value
    /// as it stands, and no view is rebuilt for it.
    @_spi(Host) public func horizontalAlignment(_ state: Binding<AxisAlignment>) -> Modified {
        plain(ViewContract.horizontalAlignment, by: state)
    }

    /// `verticalAlignment` from a state, `$x`: the host sets each new value as
    /// it stands, and no view is rebuilt for it.
    @_spi(Host) public func verticalAlignment(_ state: Binding<AxisAlignment>) -> Modified {
        plain(ViewContract.verticalAlignment, by: state)
    }

    /// The view shares the room its stack has left over along the stack's axis,
    /// never less than `minimum` long. What a `Spacer` is written with; for
    /// anything else, `.frame(maxWidth:)` says it better.
    @_spi(Host) public func flex(_ minimum: Double) -> Modified {
        setValue(ViewContract.flex, minimum)
    }

    /// `flex` from a state, `$x`: the host sets each new value as it stands,
    /// and no view is rebuilt for it.
    @_spi(Host) public func flex(_ state: Binding<Double>) -> Modified {
        plain(ViewContract.flex, by: state)
    }

    /// A marker the view's container reads to name it - a `Picker`'s choice
    /// or a `TabView`'s tab. Any value that crosses, compared by its own
    /// `==`.
    ///
    ///     Picker("Size", selection: $size) {
    ///         Text("Small").tag(Size.small)
    ///         Text("Large").tag(Size.large)
    ///     }
    public func tag<V: Hashable & HostRepresentable>(_ value: V) -> Modified {
        setValue(ViewContract.tag, value.propValue)
    }
}

extension View {
    /// Hears one of this view's events that carries nothing, landing on the
    /// root of what it is made of.
    ///
    /// - Parameters:
    ///   - event: the member, written with its contract.
    ///   - handler: what runs.
    @_disfavoredOverload
    public func onEvent<Owner: Contract>(
        _ event: ElementEvent<Owner, Void>,
        _ handler: @escaping EventHandler
    ) -> ModifiedContent {
        hearing(event, handler)
    }

    /// Hears one of this view's events, its value handed over as the type its
    /// contract declares.
    ///
    /// - Parameters:
    ///   - event: the member, written with its contract.
    ///   - handler: given the value.
    @_disfavoredOverload
    public func onEvent<Owner: Contract, Value: HostRepresentable>(
        _ event: ElementEvent<Owner, Value>,
        _ handler: @escaping ValueEventHandler<Value>
    ) -> ModifiedContent {
        hearing(event, handler)
    }

    /// Hears one of this view's events that carries two values, handed over
    /// as the types its contract declares, in its order.
    ///
    /// - Parameters:
    ///   - event: the member, written with its contract.
    ///   - handler: given the values.
    @_disfavoredOverload
    public func onEvent<Owner: Contract, First: HostRepresentable, Second: HostRepresentable>(
        _ event: ElementEvent<Owner, (First, Second)>,
        _ handler: @escaping ValueEventHandler<First, Second>
    ) -> ModifiedContent {
        hearing(event, handler)
    }

    /// Hears one of this view's events that carries three values, handed over
    /// as the types its contract declares, in its order.
    ///
    /// - Parameters:
    ///   - event: the member, written with its contract.
    ///   - handler: given the values.
    @_disfavoredOverload
    public func onEvent<
        Owner: Contract, First: HostRepresentable, Second: HostRepresentable, Third: HostRepresentable
    >(
        _ event: ElementEvent<Owner, (First, Second, Third)>,
        _ handler: @escaping ValueEventHandler<First, Second, Third>
    ) -> ModifiedContent {
        hearing(event, handler)
    }

    /// Adds space around the preceding view. Each call encloses its earlier
    /// modifiers, so a later background includes this space.
    ///
    ///     Text("Total").padding(16)                        // all four sides
    ///     Text("Total").padding(EdgeInsets(16, 0, 0, 0))   // the left edge only
    ///     Text("Total").padding(.horizontal, 16)           // left and right
    ///     Text("Total").padding()                          // the library's default
    @_disfavoredOverload
    public func padding(_ value: EdgeInsets) -> ModifiedContent {
        revised { node in
            node = node.mappingLayoutLeaves {
                $0.wrapPadding()
                $0.props[.contentPadding] = value.propValue
            }
        }
    }

    /// The same space on the edges named, `nil` for the library's default.
    ///
    ///     Text("Total").padding(.horizontal, 16)
    ///     Text("Total").padding(.top)
    @_disfavoredOverload
    public func padding(_ edges: Edge.Set = .all, _ length: Double? = nil) -> ModifiedContent {
        padding(paddingInsets(edges, length))
    }

    /// Left and right, then top and bottom. This library's own.
    @_disfavoredOverload
    @_spi(Host) public func padding(_ horizontalSize: Double, _ verticalSize: Double) -> ModifiedContent {
        padding(EdgeInsets(horizontalSize, verticalSize))
    }

    /// Each side in turn: left, top, right, bottom. This library's own.
    @_disfavoredOverload
    @_spi(Host) public func padding(_ left: Double, _ top: Double, _ right: Double, _ bottom: Double) -> ModifiedContent {
        padding(EdgeInsets(left, top, right, bottom))
    }

    /// The same space on all four sides.
    @_disfavoredOverload
    public func padding(_ length: Double) -> ModifiedContent {
        padding(EdgeInsets(length, length, length, length))
    }

    /// The same space on all four sides, as a number literal.
    @_disfavoredOverload
    public func padding(_ all: Int) -> ModifiedContent {
        padding(EdgeInsets(Double(all)))
    }

    /// `padding` from a state, `$x`: the host animates the property to each
    /// new value, and no view is rebuilt for it. This library's own.
    @_disfavoredOverload
    @_spi(Host) public func padding(_ state: Binding<EdgeInsets>) -> ModifiedContent {
        revised { node in
            node = node.mappingLayoutLeaves {
                $0.wrapPadding()
                $0.driveJourney(.contentPadding, by: state)
            }
        }
    }

    /// The same space on all four sides, from a state, `$x`. This library's own.
    @_disfavoredOverload
    @_spi(Host) public func padding(_ state: Binding<Double>) -> ModifiedContent {
        padding(state.convert { EdgeInsets($0, $0, $0, $0) })
    }

    /// The same space on all four sides, from a state holding a whole number, `$x`. This library's own.
    @_disfavoredOverload
    @_spi(Host) public func padding(_ state: Binding<Int>) -> ModifiedContent {
        padding(state.convert { EdgeInsets(Double($0)) })
    }

    /// How the view uses the width its parent offers - filling it, or sitting
    /// at one end of it. This library's own: `VStack(alignment:)` and
    /// `.frame(alignment:)` are the view-facing shapes.
    ///
    ///     Button("Save").horizontalAlignment(.center)
    @_disfavoredOverload
    @_spi(Host) public func horizontalAlignment(_ value: AxisAlignment) -> ModifiedContent {
        setting(ViewContract.horizontalAlignment, value)
    }

    /// The same, for the height.
    @_disfavoredOverload
    @_spi(Host) public func verticalAlignment(_ value: AxisAlignment) -> ModifiedContent {
        setting(ViewContract.verticalAlignment, value)
    }

    /// `horizontalAlignment` from a state, `$x`: the host sets each new value
    /// as it stands, and no view is rebuilt for it.
    @_disfavoredOverload
    @_spi(Host) public func horizontalAlignment(_ state: Binding<AxisAlignment>) -> ModifiedContent {
        revised { $0.drivePlain(ViewContract.horizontalAlignment, by: state) }
    }

    /// `verticalAlignment` from a state, `$x`: the host sets each new value as
    /// it stands, and no view is rebuilt for it.
    @_disfavoredOverload
    @_spi(Host) public func verticalAlignment(_ state: Binding<AxisAlignment>) -> ModifiedContent {
        revised { $0.drivePlain(ViewContract.verticalAlignment, by: state) }
    }

    /// Keeps the view at its own size on the axes asked, rather than taking
    /// what its parent offers - centered in the room it is given:
    ///
    ///     Text("…")
    ///         .fixedSize()
    ///
    ///     Label("Amount")
    ///         .fixedSize(horizontal: false, vertical: true)
    public func fixedSize(horizontal: Bool, vertical: Bool) -> ModifiedContent {
        var modified = ModifiedContent(node: node)
        if horizontal { modified = modified.horizontalAlignment(.center) }
        if vertical { modified = modified.verticalAlignment(.center) }
        return modified
    }

    /// The same, on both axes.
    public func fixedSize() -> ModifiedContent {
        fixedSize(horizontal: true, vertical: true)
    }
}

/// The padding `.padding()` writes, the same on every platform: sixteen
/// device units - wide enough for a control's edge, narrow enough for
/// ordinary text.
let libraryDefaultPadding: Double = 16

/// The insets `padding(_:_:)` writes - shared by `ViewProperties` and `View`.
private func paddingInsets(_ edges: Edge.Set, _ length: Double?) -> EdgeInsets {
    let amount = length ?? libraryDefaultPadding
    var insets = EdgeInsets(0, 0, 0, 0)
    if edges.contains(.leading) { insets.left = amount }
    if edges.contains(.top) { insets.top = amount }
    if edges.contains(.trailing) { insets.right = amount }
    if edges.contains(.bottom) { insets.bottom = amount }
    return insets
}

extension View {
    /// A menu on the view itself, opened with a right-click.
    ///
    ///     Text(item.name)
    ///         .contextMenu {
    ///             MenuItem("Rename") { rename(item) }
    ///             Divider()
    ///             MenuItem("Delete", role: .destructive) { remove(item) }
    ///         }
    ///
    /// The same entries a menu bar takes - `MenuItem`, `Menu`
    /// and `Divider` - attached to a view instead of to a page.
    ///
    /// Context menus are a desktop interaction. A host with no native context
    /// menu interaction leaves this modifier inert, so do not put the only way
    /// to perform an essential action behind it.
    ///
    /// - Parameter items: the entries, in the order they are shown.
    public func contextMenu(@ViewBuilder _ items: () -> any View) -> ModifiedContent {
        revised {
            // After the view's own children; the host finds it by type.
            // Design: docs/design/views/modifiers.md#slot-children
            $0.children.append(Node(contract: ContextMenuContract.self,
                                   children: items().environment(\.isMenuContent, true).labelStyle(.titleAndIcon).node.asChildren))
        }
    }
}

extension View {
    /// How this view's values animate when they change.
    ///
    ///     VStack { … }.animation(.spring(response: 0.26))
    ///     Text(count).animation(nil)
    ///
    /// A changed value arrives immediately by default; `nil` also snaps.
    /// An explicit animation applies to this
    /// view only, not to the views inside it; `application.animation` sets the
    /// whole application.
    ///
    /// - Parameter animation: how its values animate, or `nil` for none.
    /// - Returns: the view, with the animation on it.
    public func animation(_ animation: Animation?) -> ModifiedContent {
        revised { node in
            var plan = node.animation ?? AnimationPlan(base: nil)
            plan.base = animation ?? Animation.none
            node.animation = plan
        }
    }

    /// How this view's values animate when `value` changes - and only then.
    ///
    ///     Text(message).animation(.bouncy, value: message)
    ///
    /// The animation applies to the render a change to `value` causes; a render
    /// where `value` stands the same leaves the view animating as it otherwise
    /// would.
    ///
    /// - Parameters:
    ///   - animation: the animation to use, or `nil` for none.
    ///   - value: what changes to animate on.
    /// - Returns: the view, with the trigger on it.
    public func animation<V: Equatable>(_ animation: Animation?, value: V) -> ModifiedContent {
        revised { node in
            var plan = node.animation ?? AnimationPlan(base: nil)
            plan.gates.append((value: AnyEquatableValue(value), animation: animation))
            node.animation = plan
        }
    }

    /// How some of this view's values animate, leaving the rest as they were.
    /// This library's own: `value:` is the public shape.
    ///
    ///     VStack { … }
    ///         .animation(.spring(response: 0.24))
    ///         .animation(.none, .size)
    ///
    /// The last rule that names a value answers for it. The usual use is a view
    /// whose shape changes: it takes its new size at once while still
    /// animating to its new place.
    ///
    /// - Parameters:
    ///   - animation: how those values animate.
    ///   - values: which of them. See `AnimationValues` for what each name covers.
    /// - Returns: the view, with the rule on it.
    @_spi(Host) public func animation(_ animation: Animation, _ values: AnimationValues) -> ModifiedContent {
        revised { node in
            var plan = node.animation ?? AnimationPlan(base: nil)
            plan.rules.append((values: values, animation: animation))
            node.animation = plan
        }
    }

    /// Rewrites the transaction the views below this one run their changes
    /// under.
    ///
    ///     Row(item).transaction { $0.disablesAnimations = true }
    ///
    /// - Parameter transform: what to do to the transaction.
    /// - Returns: the view, with the rewrite on it.
    public func transaction(_ transform: @escaping @Sendable (inout Transaction) -> Void) -> ModifiedContent {
        revised { node in
            var plan = node.animation ?? AnimationPlan(base: nil)
            plan.transactions.append(TransactionTransform(transform))
            node.animation = plan
        }
    }

    /// Who this view is among its siblings: its key across renders.
    ///
    /// A view that comes back with the same key keeps its control, and only the
    /// properties that changed are written to it. Give one to anything whose
    /// position can change, so inserting, removing or reordering moves the
    /// existing controls instead of rewriting each into its neighbour:
    ///
    ///     VStack {
    ///         ForEach(items, id: \.id) { item in
    ///             Text(item.title)            // key from the loop
    ///         }
    ///
    ///         if showingTotal {
    ///             Text("Total").id("total")   // key written by hand
    ///         }
    ///     }
    ///
    /// An `.id()` written on the view wins over the one `ForEach` gives. Any
    /// `Hashable` is a key - a string, a number, a UUID, the author's own enum
    /// or struct - compared as `String(describing:)`: a description that says
    /// less than the value gives two values one key, and a class is keyed by
    /// something it holds (`.id(file.path)`).
    ///
    /// - Parameter value: who this view is - distinct among its siblings and
    ///   the same across renders.
    @_disfavoredOverload
    public func id(_ value: some Hashable) -> ModifiedContent {
        revised { $0.id = String(describing: value) }
    }

    /// Provides an object to this view and everything under it, resolved by
    /// type: any view below declaring `@Environment var context: MyContext`
    /// reads the nearest `MyContext` provided above it. A nearer
    /// `.environment()` of the same type overrides for its own branch.
    ///
    ///     @State var context = MyContext()   // a class of @State properties, usually
    ///
    ///     ChildView()
    ///         .environment(context)
    ///
    /// Providing reads no property, so a change in the object rebuilds the
    /// readers below and not the provider; replacing the object rebuilds the
    /// branch.
    public func environment<Value: AnyObject>(_ object: Value) -> ModifiedContent {
        revised { $0.environments.append((key: ObjectIdentifier(Value.self), object: object)) }
    }

    /// Writes a keyed environment value to this view and everything under it,
    /// read below with `@Environment(\.key)`. A nearer write of the same key
    /// overrides for its own branch, and a view that reads one is rebuilt when
    /// what it resolves to moves.
    ///
    ///     ChildView()
    ///         .environment(\.textEditorWraps, false)
    ///
    /// - Parameters:
    ///   - keyPath: the `EnvironmentValues` property to write - writable, so a
    ///     custom entry declares get and set alike.
    ///   - value: what the key reads below.
    public func environment<Value>(
        _ keyPath: WritableKeyPath<EnvironmentValues, Value>,
        _ value: Value
    ) -> ModifiedContent {
        revised { $0.environmentValues[keyPath: keyPath] = value }
    }

    /// The keyed style from the application's style sheet that this view wears.
    ///
    ///     Text("Welcome").style("Headline")
    ///
    /// A style without a key applies to every control of its type by itself.
    public func style(_ key: String) -> ModifiedContent {
        setting(VisualElementContract.style, Name(key))
    }
}

extension View {
    /// Whether the platform has given this view the focus, written into the
    /// binding. Read-only: the platform moves the focus.
    ///
    ///     @State private var focused = false
    ///     TextField($name).isFocused($focused)
    public func isFocused(_ binding: Binding<Bool>) -> ModifiedContent {
        hearing(VisualElementContract.isFocusedChanged) { focused in
            binding.wrappedValue = focused
        }
    }

    /// Reads where a value the host is animating has got to, at most so many
    /// times a second, into a state of your own.
    ///
    ///     @State private var fade = 1.0
    ///     @State private var shown = 1.0
    ///
    ///     VStack {
    ///         Text("\(Int(shown * 100))%")
    ///     }
    ///     .opacity($fade)
    ///     .samples($fade, into: $shown, .every(100))
    ///
    /// Reading `fade` answers where it is going, and `$fade.journey.value` in a
    /// body rebuilds that body on every frame; this copies some of those frames
    /// into an ordinary state instead. It stops when the value lands, the last
    /// sample being where the value ended. A value that is only shown wants a
    /// driven text (`Text($fade.journey.convert { … })`), which costs no render.
    ///
    /// - Parameters:
    ///   - source: the value the host is animating, `$x` of a `@State`.
    ///   - target: the state to read it into, `$y`.
    ///   - asks: how often, at most.
    public func samples<Value: Walked>(
        _ source: Binding<Value>,
        into target: Binding<Value>,
        _ asks: Asks
    ) -> ModifiedContent {
        revised {
            guard let from = source.described, let image = from.walkedImage(),
                  let into = target.described
            else {
                return
            }

            $0.samples.append((image: image, into: ObjectIdentifier(into), asks: asks, take: {
                // Off the lanes, not the journey's own read, so the element being
                // built does not become a reader of the value.
                guard let now = from.journeyLanes?.value else { return }

                guard StateImage.bytes(of: now.carried)
                    != StateImage.bytes(of: into.value.carried) else { return }

                target.wrappedValue = now
            }))
        }
    }
}

extension View {
    /// One space for the geometry the views inside and outside it measure,
    /// SwiftUI's `geometryGroup`.
    ///
    /// SwiftUI needs the marker where a parent that moves animates a child's
    /// geometry off its own coordinates; SwiftOmniUI measures and places every
    /// element in the same pass as its parent's, so the space is already one
    /// and the modifier stands for the source's sake, adding no node.
    public func geometryGroup() -> ModifiedContent {
        revised { _ in }
    }
}
