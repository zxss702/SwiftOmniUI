// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// How `@State` on a composed view survives the view being rebuilt: the view
// enters the tree as a placeholder, and the differ adopts the old boxes'
// storage before it builds the body.
// Design: docs/design/core/identity-and-diffing.md#state-survives-a-rebuild

/// What the differ needs of any state box without knowing its value's type.
protocol StateBox: AnyObject {
    /// Takes over `other`'s storage when it is a box of the same value type.
    func adopt(from other: AnyObject)

    /// The storage this box holds after adoption - what says two boxes are one state.
    var lender: AnyObject { get }

    /// Tells the box the property the author declared it as (Builds.swift).
    func named(_ path: String)
}

extension StateBox {
    /// A borrowed value and an author's own class answer to no name.
    func named(_ path: String) {}
}

/// Marks a wrapper whose state is owned elsewhere - `Binding`. The walk stops at
/// one, so borrowed storage is never adopted as the borrower's own.
protocol BorrowedState {
    /// What the wrapper borrows from: the storage behind a whole `@State` and which
    /// part of it, or nothing for a binding made from closures.
    var lends: (lender: AnyObject?, lent: AnyHashable?) { get }
}

/// A lazy row source owns its models, not child view state. Its current row
/// closure is retained by the lazy container and each requested row is scanned
/// when built; recursively reflecting every offscreen model here is wasted work.
protocol LazyRowStateBoundary {}

/// One stored property of a composed view, as the differ can compare it - what
/// decides, beside its reads, whether the view is built again or carried.
/// Design: docs/design/core/identity-and-diffing.md#what-a-view-was-built-with
enum Input {
    /// A value that says whether it equals another.
    case value(any Equatable)

    /// An object, by identity.
    case reference(ObjectIdentifier)

    /// A state lent to the view: the storage it lends, and which part of it.
    case borrowed(ObjectIdentifier, AnyHashable?)

    /// A state the view owns, compared by the storage it holds - AFTER
    /// adoption, which is when the box knows.
    case box(StateBox)

    /// An `@Environment` slot, compared by what it resolved to.
    case slot(EnvironmentSlot)

    /// How many parts a container of values has.
    case parts(Int)

    /// A closure, a built node, anything nothing can compare.
    case opaque

    /// Whether every input matches its predecessor, path for path.
    static func same(
        _ fresh: [(path: String, input: Input)],
        _ kept: [(path: String, input: Input)]
    ) -> Bool {
        guard fresh.count == kept.count else { return false }

        for (now, then) in zip(fresh, kept) {
            guard now.path == then.path, matches(now.input, then.input) else { return false }
        }

        return true
    }

    /// The first input that does not match, by its property's name - the reason an
    /// inspector gives for a build.
    static func difference(
        _ fresh: [(path: String, input: Input)],
        _ kept: [(path: String, input: Input)]
    ) -> String? {
        guard fresh.count == kept.count else { return "set of properties" }

        for (now, then) in zip(fresh, kept) where now.path != then.path
            || !matches(now.input, then.input) {
            let name = BuildScope.readable(now.path)

            if case .opaque = now.input {
                return "\(name), which cannot be compared"
            }

            return name
        }

        return nil
    }

    /// Whether one input matches its predecessor.
    private static func matches(_ now: Input, _ then: Input) -> Bool {
        switch (now, then) {
        case let (.value(a), .value(b)):
            return equal(a, b)
        case let (.reference(a), .reference(b)):
            return a == b
        case let (.borrowed(a, partA), .borrowed(b, partB)):
            return a == b && partA == partB
        case let (.box(a), .box(b)):
            return a.lender === b.lender
        case let (.slot(a), .slot(b)):
            return a.same(as: b)
        case let (.parts(a), .parts(b)):
            return a == b
        default:
            return false
        }
    }

    /// Equality across the existential, opened on the first value's type.
    private static func equal(_ a: any Equatable, _ b: any Equatable) -> Bool {
        func open<Value: Equatable>(_ a: Value) -> Bool {
            (b as? Value).map { $0 == a } ?? false
        }

        return open(a)
    }
}

/// Every state box and `@Environment` slot a view owns, with its inputs, in one
/// walk. Each box comes back under the path the walk reached it by, which pairs
/// it with its predecessor next render.
/// Design: docs/design/core/identity-and-diffing.md#paths-pair-state
@MainActor func stateParts(
    in value: Any
) -> (
    boxes: [(path: String, box: StateBox)],
    slots: [EnvironmentSlot],
    inputs: [(path: String, input: Input)]
) {
    var boxes: [(path: String, box: StateBox)] = []
    var slots: [EnvironmentSlot] = []
    var inputs: [(path: String, input: Input)] = []
    collectStateParts(in: value, at: "", boxes: &boxes, slots: &slots, inputs: &inputs)
    return (boxes, slots, inputs)
}

@MainActor private func collectStateParts(
    in value: Any,
    at path: String,
    boxes: inout [(path: String, box: StateBox)],
    slots: inout [EnvironmentSlot],
    inputs: inout [(path: String, input: Input)]
) {
    // An aim the view was handed is compared by its box and never adopted; one it
    // declares is `@Aim`'s underscored backing property, adopted like any state.
    if let aim = value as? Aiming, !(path.split(separator: ".").last?.hasPrefix("_") ?? false) {
        inputs.append((path: path, input: .borrowed(ObjectIdentifier(aim.box), nil)))
        return
    }

    if let box = value as? StateBox {
        boxes.append((path: path, box: box))
        box.named(path)
        inputs.append((path: path, input: .box(box)))
        return
    }

    if let slot = value as? EnvironmentSlot {
        slots.append(slot)
        inputs.append((path: path, input: .slot(slot)))
        return
    }

    // A borrowed state is compared by what it borrows from.
    if let borrowed = value as? BorrowedState {
        let lends = borrowed.lends
        inputs.append((
            path: path,
            input: lends.lender.map { .borrowed(ObjectIdentifier($0), lends.lent) } ?? .opaque))
        return
    }

    // A built node is interface, never state, and cannot be compared.
    if value is Node {
        inputs.append((path: path, input: .opaque))
        return
    }

    if value is any LazyRowStateBoundary {
        inputs.append((path: path, input: .opaque))
        return
    }

    // A keyed element carries its builder branch, which tells the arms of an `if`
    // apart, and the type of the view inside.
    if let keyed = value as? Keyed {
        collectStateParts(
            in: keyed.raw,
            at: "\(path).\(keyed.segment)\(storedViewType(of: keyed.raw))",
            boxes: &boxes,
            slots: &slots,
            inputs: &inputs)
        return
    }

    // Equality decides whether a view's body can be carried, but it must not hide the dynamic properties the
    // view owns. Their boxes still adopt the previous storage, and environment slots still resolve and compare.
    if let comparable = value as? any Equatable {
        inputs.append((path: path, input: .value(comparable)))
        if value is any View {
            var members: [(path: String, input: Input)] = []
            for (offset, child) in Mirror(reflecting: value).children.enumerated() {
                collectStateParts(
                    in: child.value,
                    at: "\(path).\(child.label ?? String(offset))\(storedViewType(of: child.value))",
                    boxes: &boxes, slots: &slots, inputs: &members)
            }
            inputs.append(contentsOf: members.filter {
                switch $0.input {
                case .box, .slot: true
                default: false
                }
            })
        }
        return
    }

    let mirror = Mirror(reflecting: value)

    // A reference keeps itself alive; as an input it is the object it is.
    if mirror.displayStyle == .class {
        inputs.append((path: path, input: .reference(ObjectIdentifier(value as AnyObject))))
        return
    }

    let children = Array(mirror.children)

    // A leaf the mirror cannot open - a closure, a metatype - counts as changed; an
    // empty struct or enum is the one value it can be.
    if children.isEmpty {
        inputs.append((path: path, input: mirror.displayStyle == nil ? .opaque : .parts(0)))
        return
    }

    inputs.append((path: path, input: .parts(children.count)))

    // A collection's children have no labels, so their position stands in.
    for (offset, child) in children.enumerated() {
        collectStateParts(
            in: child.value,
            at: "\(path).\(child.label ?? String(offset))\(storedViewType(of: child.value))",
            boxes: &boxes,
            slots: &slots,
            inputs: &inputs)
    }
}

/// The type of a stored view, in brackets after the property holding it, so one
/// property holding different views gives different paths. Module-qualified.
private func storedViewType(of value: Any) -> String {
    value is Element ? "(\(String(reflecting: type(of: value))))" : ""
}

extension Node {
    /// A subtree nobody has built yet, and what it takes to build it right.
    struct Stateful {
        /// The composed view's module-qualified type, which decides whose state it keeps.
        let viewType: String

        /// The state boxes the fresh view owns, under the paths the walk found them at.
        let boxes: [(path: String, box: StateBox)]

        /// The `@Environment` slots, filled before the body builds
        /// (Environment.swift).
        let slots: [EnvironmentSlot]

        /// What the view was built with, compared against last render's to decide whether
        /// it is built or carried.
        let inputs: [(path: String, input: Input)]

        /// Builds the subtree - after the boxes have adopted their predecessors' storage.
        let build: () -> Node

        /// The scene this view is, where it is one (SceneRecord.swift).
        let scene: SceneRecord?

        /// Fills every slot with the nearest provided object of its type, and
        /// every keyed slot from the values above it; a slot nobody provided
        /// for is left for its read to report.
        func resolve(
            from scope: [(key: ObjectIdentifier, object: AnyObject)],
            under values: EnvironmentValues
        ) {
            for slot in slots {
                slot.fill(values: values)
                if let found = scope.last(where: { $0.key == slot.wants }) {
                    slot.fill(found.object)
                }
            }
        }

        /// Builds the subtree and lands what the author wrote on the view onto its
        /// root - or onto each of them, when the body is a fragment of several.
        func expand(over written: Node) -> Node {
            var node = build()
            if node.type == .fragment { node.materialize() }
            if node.type == .fragment, node.children.count > 1, written.lazyIdentity != nil,
               let stack = written.props[.lazyRowStack]?.numbers, !stack.isEmpty {
                let children = node.asChildren
                node.type = stack[0] == 1 ? .hStack : .vStack
                node.children = children
                if stack.count > 1 { node.write(StackBaseContract.spacing, stack[1]) }
            }
            for (property, member) in written.inheritedMembers {
                node.inherit(property, member: member)
            }
            node.hasExplicitFontBasis = node.hasExplicitFontBasis || written.hasExplicitFontBasis
            node.lazyIdentity = written.lazyIdentity ?? node.lazyIdentity

            // A fragment keeps no element of its own to write on: what the author
            // wrote on the view lands on each child the body splices in.
            if node.type == .fragment {
                node.environments = written.environments + node.environments
                node.environmentValues = node.environmentValues.overlaid(with: written.environmentValues)
                node.focusedValues = node.focusedValues.overlaid(with: written.focusedValues)
                node.sceneFocusedValues = node.sceneFocusedValues.overlaid(with: written.sceneFocusedValues)

                // A body of one view is that view: it stands in the view's
                // place, taking what the body's root itself carried - a
                // `.verticalAlignment` written on a TupleView - onto the one
                // child, under what the placeholder wrote. A fragment of
                // several stays a fragment: the differ lands its writes on
                // the children when it splices them in.
                if node.children.count == 1 {
                    var child = node.children[0]
                    child.absorbFragmentWrites(of: node, environments: false)
                    child = landing(child, written: written)
                    child.environments = node.environments + child.environments
                    child.environmentValues = child.environmentValues.overlaid(with: node.environmentValues)
                    child.focusedValues = child.focusedValues.overlaid(with: node.focusedValues)
                    child.sceneFocusedValues = child.sceneFocusedValues.overlaid(with: node.sceneFocusedValues)
                    node = child
                    return node
                }

                node.children = node.children.map { landing($0, written: written) }
                return node
            }

            node.props.merge(written.props) { _, wrote in wrote }
            node.environments = written.environments + node.environments
            node.environmentValues = node.environmentValues.overlaid(with: written.environmentValues)
            node.focusedValues = node.focusedValues.overlaid(with: written.focusedValues)
            node.sceneFocusedValues = node.sceneFocusedValues.overlaid(with: written.sceneFocusedValues)
            node.driven.merge(written.driven) { _, wrote in wrote }
            node.animation = AnimationPlan.merged(node.animation, under: written.animation)

            for (name, handler) in written.events.sorted(by: { $0.key < $1.key }) {
                node.addHandler(name, handler)
            }

            // Its own watches first, then what was written on it - one order every render.
            node.watches += written.watches

            // And its lifetime handlers, in the same order (Lifetime.swift).
            node.created += written.created
            node.destroying += written.destroying
            node.tasks += written.tasks

            // And its engines, registered against the element its body ends on.
            node.engines += written.engines

            // Preferences written on a composed view belong to its body's
            // root, just like its events. Dropping these loses both the
            // Text.LayoutKey reader and the selection anchors above it.
            node.absorbPreferenceWrites(of: written)

            // And slot children written on it - a `.contextMenu` - after its own.
            node.children += written.children

            node.id = written.id ?? node.id
            node.key = written.key ?? node.key
            return node
        }

        /// `written` landed on one child of a fragment: the same merge `expand`
        /// runs on a single root, except the view's key scopes the child's.
        private func landing(_ child: Node, written: Node) -> Node {
            var child = child
            child.props.merge(written.props) { _, wrote in wrote }
            child.driven.merge(written.driven) { _, wrote in wrote }
            child.animation = AnimationPlan.merged(child.animation, under: written.animation)

            for (name, handler) in written.events.sorted(by: { $0.key < $1.key }) {
                child.addHandler(name, handler)
            }

            child.watches += written.watches
            child.created += written.created
            child.destroying += written.destroying
            child.tasks += written.tasks
            child.engines += written.engines
            child.absorbPreferenceWrites(of: written)
            child.children += written.children
            child.lazyIdentity = written.lazyIdentity ?? child.lazyIdentity
            if child.session == nil { child.session = written.session }
            child.id = written.id ?? child.id
            child.key = written.key.map { scope in
                child.key.map { "\(scope).\($0)" } ?? scope
            } ?? child.key
            return child
        }
    }

    /// This node with every placeholder built, recursively, with no state carried
    /// over - for tests that read a tree structurally, resolving the standard
    /// environment as a render does.
    var built: Node { built(within: StandardEnvironment.scope, under: EnvironmentValues()) }

    /// The same, resolving `@Environment` from `scope` and `values` as a render
    /// at this place would.
    func built(
        within scope: [(key: ObjectIdentifier, object: AnyObject)],
        under values: EnvironmentValues
    ) -> Node {
        var node = self
        var scope = scope
        var values = values.overlaid(with: node.environmentValues)
        scope.append(contentsOf: node.environments)
        var kept: [Stateful] = []

        while true {
            if let stateful = node.stateful {
                stateful.resolve(from: scope, under: values)
                kept.append(stateful)
                node = stateful.expand(over: node)
                values = values.overlaid(with: node.environmentValues)
                scope.append(contentsOf: node.environments)
                continue
            }

            break
        }

        node.keptState = kept
        node.materialize()
        node.resolveEnabled(in: values)
        node.resolveControlStyle(in: scope)
        node.children = node.children.map { $0.built(within: scope, under: values) }
        return node
    }

    /// A placeholder for a composed view, expanded by the differ before anything is
    /// sent.
    ///
    /// - Parameter scene: the scene this view is, where it is one.
    @MainActor static func composed(
        _ view: Any,
        type: String,
        scene: SceneRecord? = nil,
        build: @escaping () -> Node
    ) -> Node {
        var node = Node(type: .composed)
        let parts = stateParts(in: view)
        node.stateful = Stateful(
            viewType: type,
            boxes: parts.boxes,
            slots: parts.slots,
            inputs: parts.inputs,
            build: build,
            scene: scene)
        return node
    }
}

extension NodeType {
    /// The differ's placeholder for a composed view. It never crosses to a host, so
    /// no contract declares it.
    static let composed = NodeType("Composed")

    /// A transparent group - a `TupleView`, `Group`, `ForEach` or `EmptyView`: the
    /// differ splices its children into the parent element's own, so it never
    /// crosses to a host either.
    static let fragment = NodeType("Fragment")
}

extension Node {
    /// This node spliced into a parent's child list: a fragment's children
    /// with the fragment's per-child writes landed on each, any other node
    /// itself. The spread recurses, so a fragment among the children hands
    /// its own writes on down rather than dropping them.
    var asChildren: [Node] {
        guard type == .fragment else { return [self] }

        var fragment = self
        fragment.materialize()
        return fragment.children.flatMap { child -> [Node] in
            var child = child
            child.absorbFragmentWrites(of: fragment)
            return child.asChildren
        }
    }

    /// What a fragment writes on each child it stands for. A fragment keeps
    /// no element of its own, so a modifier on it lands on the children it
    /// splices in - the fragment's own answer winning where both wrote the
    /// same thing, the child's where it wrote alone. `environments` spreads
    /// the fragment's scopes onto the child too; false where the differ has
    /// them in scope already.
    mutating func absorbFragmentWrites(of fragment: Node, environments: Bool = true) {
        hasExplicitFontBasis = hasExplicitFontBasis || fragment.hasExplicitFontBasis
        lazyIdentity = fragment.lazyIdentity ?? lazyIdentity
        props.merge(fragment.props) { _, wrote in wrote }
        driven.merge(fragment.driven) { _, wrote in wrote }
        animation = AnimationPlan.merged(animation, under: fragment.animation)

        for (name, handler) in fragment.events.sorted(by: { $0.key < $1.key }) {
            addHandler(name, handler)
        }

        watches += fragment.watches
        created += fragment.created
        destroying += fragment.destroying
        tasks += fragment.tasks
        engines += fragment.engines

        // Its published bags too: a fragment owns no element, so a
        // `.focusedValue` written through it lands on the children it stands
        // for.
        focusedValues = focusedValues.overlaid(with: fragment.focusedValues)
        sceneFocusedValues = sceneFocusedValues.overlaid(with: fragment.sceneFocusedValues)

        absorbPreferenceWrites(of: fragment)
        layoutValues.merge(fragment.layoutValues) { _, wrote in wrote }
        destinations.merge(fragment.destinations) { _, wrote in wrote }
        if itemDestination == nil { itemDestination = fragment.itemDestination }
        if textRenderer == nil { textRenderer = fragment.textRenderer }
        if customLayout == nil { customLayout = fragment.customLayout }

        if environments {
            self.environments = fragment.environments + self.environments
            environmentValues = environmentValues.overlaid(with: fragment.environmentValues)
        }

        if session == nil { session = fragment.session }
        if aim == nil { aim = fragment.aim }
    }

    /// Preference metadata follows the same root as the modifier's frame
    /// handlers, through both composed views and transparent fragments.
    mutating func absorbPreferenceWrites(of written: Node) {
        preferenceSeeds = written.preferenceSeeds + preferenceSeeds
        anchorBoxes = written.anchorBoxes + anchorBoxes
        preferenceObservers += written.preferenceObservers
        preferenceTransforms += written.preferenceTransforms
    }
}
