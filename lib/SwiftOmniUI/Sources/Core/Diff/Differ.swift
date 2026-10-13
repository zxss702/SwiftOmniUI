// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The differ: what a render built, walked against the tree the host holds, with
// only the differences packed into a `HostPatch`. Element ids and handler ids
// are allocated here, because both outlive the tree that made them.
// Design: docs/design/core/identity-and-diffing.md#keys

/// Walks the authored tree against the rendered one and produces the message.
/// Design: docs/design/core/identity-and-diffing.md#what-a-walk-keeps
final class Differ {
    /// The next element id. Never reset, not even by a resync.
    /// Design: docs/design/core/identity-and-diffing.md#ids-are-never-reused
    private var nextElementId = 1

    /// The next handler id, under the same rule.
    private var nextHandlerId = 1

    /// Which walk this is, so an aim knows one walk from the next.
    private(set) var walkStamp = 0

    /// Whether this walk describes every element in full, for a resync.
    /// Design: docs/design/core/identity-and-diffing.md#a-resync-keeps-matching
    private(set) var describeAll = false

    /// The style sheet this walk resolves every element against.
    private(set) var styles: StyleSheet?

    /// How a changed value animates where its element says nothing else.
    var animation: Animation = .standard

    /// The transaction the writes this render answers ran under - what
    /// `withAnimation` and `withTransaction` left for it; nil by default.
    var transaction: Transaction?

    /// Whether the sheet moved at the top of this walk, which carries no view.
    /// Design: docs/design/core/identity-and-diffing.md#what-a-carry-cannot-see
    private(set) var stylesMoved = false

    /// The states written since the tree the host holds was built.
    private(set) var changed: Set<ObjectIdentifier> = []

    /// What each changed state is called, for `debugInfo()` (Builds.swift).
    var named: [ObjectIdentifier: String] = [:]

    /// The code objects a host pulls by element id - a `CustomLayout`'s
    /// layout box and the `.layoutValue` tags a child carries. They ride the
    /// node, never the wire; the element's number is how the host asks.
    var codeObjects: [ElementId: NodeCode] = [:]

    /// The handlers this walk found to run - `.onChanged`, `.onAppear` - in order.
    /// Design: docs/design/core/render.md#handlers-in-the-message
    var fired: [EventHandler] = []

    /// The `.onDisappear` handlers of what this walk let go, innermost first.
    private var leaving: [EventHandler] = []

    /// The environments in scope where the walk stands, nearest last.
    var scope: [(key: ObjectIdentifier, object: AnyObject)] = []

    /// The keyed environment values in scope where the walk stands - what
    /// `.environment(\.key, _)` wrote on the elements above.
    var envValues = EnvironmentValues()

    /// Whether the walk stands inside a `.focusedValue` publisher - any
    /// element there may be the one holding the keyboard focus, so each
    /// reports the platform's moves to `focusStore`.
    var inFocusedScope = false

    /// The focused element and the values its chain publishes - what
    /// `@FocusedValue` slots resolve from, offered through `scope` like the
    /// standard environment objects (FocusedValueStore.swift).
    let focusStore = FocusedValueStore()

    /// The composed views whose bodies the walk is inside, outermost first.
    var bodies: [String] = []

    /// What every live element's events run, kept between renders.
    /// Design: docs/design/core/identity-and-diffing.md#handlers-and-their-ids
    var handlers: [Int: EventHandler] = [:]

    /// The scene the walk is inside; `Scenes.building` follows it.
    var sceneRecord: SceneRecord? {
        didSet { Scenes.shared.building = sceneRecord }
    }

    /// The `.scene` nodes the walk is inside, innermost last - what a scene's
    /// `.focusedSceneValue` fold reads while the scene is still being built.
    var sceneNodes: [(id: String, node: Node)] = []

    /// The tree this walk was given, where it was given one - what a
    /// `.focusedSceneValue` read folds before the rendered tree lands.
    /// Nil on the clean walk, which folds `lastRendered` instead.
    var authoredRoot: Node?

    /// Reconciles the tree just built against the one the host holds. `describeAll`
    /// makes the patch complete while matching stays as it always is; a nil
    /// `rendered` is only for a first render.
    func reconcile(
        _ rendered: RenderedNode?,
        with tree: Node,
        styles: StyleSheet? = nil,
        describeAll: Bool = false,
        changed: Set<ObjectIdentifier> = []
    ) -> (node: RenderedNode, patch: HostPatch) {
        self.describeAll = describeAll
        self.changed = changed
        stylesMoved = !StyleSheet.same(styles, self.styles)
        self.styles = styles
        walkStamp += 1
        seedScope()
        authoredRoot = tree

        // The root keeps whatever key it was given until the author states another.
        let id = tree.id.map(ElementId.manual) ?? rendered?.id ?? identity(for: tree)
        let previous = rendered?.id == id ? rendered : nil

        if let rendered = rendered, previous == nil {
            forget(rendered)
        }

        let result = element(id: id, rendered: previous, node: tree)
        lastRendered = result.node
        focusStore.stale()
        return result
    }

    /// The clean walk: no fresh tree, and exactly the elements whose reads intersect
    /// `changed` are built again. Sound only when every cause named its state.
    /// Design: docs/design/core/identity-and-diffing.md#the-clean-walk
    func revisit(
        _ rendered: RenderedNode,
        changed: Set<ObjectIdentifier>
    ) -> (node: RenderedNode, patch: HostPatch) {
        describeAll = false
        self.changed = changed
        stylesMoved = false
        walkStamp += 1
        seedScope()
        authoredRoot = nil

        let result = revisit(rendered)
        lastRendered = result.node
        focusStore.stale()
        return result
    }

    /// The root the last walk answered, so a dispatched handler can ask its tree.
    private(set) var lastRendered: RenderedNode?

    /// One kept element: built again from its placeholder when its reads moved,
    /// walked for changed descendants when they did not.
    func revisit(
        _ rendered: RenderedNode,
        walking: Bool = true
    ) -> (node: RenderedNode, patch: HostPatch) {
        let windowOnly = rendered.lazySource?.lazyWindow.map {
            rendered.reads.intersection(changed) == Set([$0])
        } ?? false
        if let placeholder = rendered.placeholder,
            !rendered.reads.isDisjoint(with: changed), !windowOnly {
            return element(
                id: rendered.id,
                rendered: rendered,
                node: placeholder,
                forced: true,
                sizesArrive: rendered.sizesArrive)
        }

        // A composed view walked past is written down only as the path to something
        // built below it, and not for a view just carried.
        let walked = walking && Inspection.recording && !rendered.views.isEmpty
            && Inspection.enter(rendered.views[0].type, .walked, element: rendered.id)
        defer { if walked { Inspection.leave() } }

        // And the scene it is in, whose record the kept state below is claimed from.
        let outer = sceneRecord
        if rendered.type == .scene, sceneRecord == nil, case .manual(let name) = rendered.id {
            sceneRecord = Scenes.shared.record(id: name)
        }
        defer { sceneRecord = outer }

        var patch = HostPatch(id: rendered.id, type: rendered.type)

        // What this element provided stays in scope while its children are walked -
        // its keyed writes overlaid the same way `element` found them.
        scope.append(contentsOf: rendered.provided)
        let outerValues = envValues
        envValues = envValues.overlaid(with: rendered.environmentValues)
        defer { scope.removeLast(rendered.provided.count); envValues = outerValues }

        // A kept element's `.focusedValue` writes keep the subtree inside the
        // publishing branch, the way `element` finds them on a fresh node.
        let outsideFocusScope = inFocusedScope
        inFocusedScope = inFocusedScope || !rendered.focusedValues.isEmpty
        defer { inFocusedScope = outsideFocusScope }

        // What the host holds is the sequence the patches address - a
        // fragment mounts nothing of its own, so its children stand in this
        // list directly, exactly as reconcileChildren splices them. The
        // arrangement is sent again when that sequence moved.
        let held = mountedIds(of: rendered.children)
        var addressed: [HostPatch] = []

        if windowOnly, var source = rendered.lazySource {
            // Scrolling changes only the selected identities. Keep the prepared
            // ForEach source and its index; new row reads still join this element.
            var reads = rendered.reads
            let frame = BuildScope.Frame(
                view: rendered.view ?? rendered.type.name,
                builds: rendered.builds + 1,
                read: reads, changed: changed, names: named, everything: false)
            ReadScope.observed(into: &reads) {
                BuildScope.within(frame) { source.materialize() }
            }
            rendered.reads = reads
            rendered.builds += 1
            rendered.children = reconcileChildren(
                of: rendered, node: source, into: &patch, sizesArrive: rendered.sizesArrive,
                keepingLazyRows: true)
        } else {
            for (index, child) in rendered.children.enumerated() {
                let (node, childPatch) = revisit(child)
                rendered.children[index] = node

                if node.type == .fragment {
                    let nested: [HostPatch] = switch childPatch.children {
                    case .arranged(let list), .changed(let list): list
                    case .unchanged: []
                    }
                    let byID = Dictionary(
                        nested.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                    addressed.append(contentsOf: flattened(of: node.children).map {
                        byID[$0.id] ?? HostPatch(id: $0.id, type: $0.type)
                    })
                } else {
                    addressed.append(childPatch)
                }
            }

            if addressed.map(\.id) != held {
                patch.children = .arranged(addressed)
            } else {
                let changedChildren = addressed.filter { !$0.isEmpty }
                if !changedChildren.isEmpty {
                    patch.children = .changed(changedChildren)
                    if rendered.lazySource != nil { patch.lazyContentChanged = true }
                }
            }

        }

        // A kept element folds its subtree's preference answers again - a
        // descendant's write may have moved - and any listener hearing a new
        // answer fires.
        // Design: docs/design/core/identity-and-diffing.md#preferences
        rendered.preferenceValues = foldedPreferences(
            seeds: rendered.preferenceSeeds,
            transforms: rendered.preferenceTransforms,
            children: rendered.children)

        for index in rendered.preferenceWatches.indices {
            let watch = rendered.preferenceWatches[index]
            let answer = rendered.preferenceValues[watch.box.key]?.value ?? watch.box.makeDefault()

            guard !watch.box.same(watch.last, answer) else { continue }

            let heard = watch.last
            rendered.preferenceWatches[index].last = answer
            fire { try await watch.run(heard, answer) }
        }

        return (rendered, patch)
    }

    /// The keyed environment each handler was registered under, by handler id.
    var handlerEnvironments: [Int: EnvironmentValues] = [:]

    /// What an element's event runs - the handler knows its own differ and the
    /// keyed environment it was registered in.
    func handler(_ id: Int) -> EventHandler? {
        guard let found = handlers[id] else { return nil }

        return { [weak self] in
            DispatchContext.differ = self
            DispatchContext.envValues = self?.handlerEnvironments[id]
            defer { DispatchContext.differ = nil; DispatchContext.envValues = nil }
            try await found()
        }
    }

    /// A handler queued for the end of a walk, run under the keyed environment
    /// it was registered in.
    func fire(_ handler: @escaping EventHandler) {
        let environment = envValues
        fired.append {
            DispatchContext.envValues = environment
            defer { DispatchContext.envValues = nil }
            try await handler()
        }
    }

    /// Whether the live tree hears `Text.LayoutKey`.
    var watchesTextLayout: Bool {
        lastRendered?.listens(to: ObjectIdentifier(Text.LayoutKey.self)) ?? false
    }

    /// The code objects the element of `id` lent its host, or nothing.
    func codeObjects(for id: ElementId) -> NodeCode? {
        codeObjects[id]
    }

    /// The handlers the last walk found - what left first, then the rest - taken so
    /// each runs once.
    func takeFired() -> [EventHandler] {
        let taken = leaving + fired
        leaving.removeAll(keepingCapacity: true)
        fired.removeAll(keepingCapacity: true)
        return taken
    }

    /// Drops the handlers and engines of an element that left the tree, and of
    /// everything under it, and books its `.onDisappear`.
    func forget(_ node: RenderedNode) {
        for id in node.events.values {
            handlers.removeValue(forKey: id)
            handlerEnvironments.removeValue(forKey: id)
        }

        // Its code objects: no host asks of an element that left.
        codeObjects.removeValue(forKey: node.id)

        // Its engines: nothing is left to ask for their frames.
        for id in node.engines {
            Renderer.shared.disarm(id)
        }

        for child in node.children {
            forget(child)
        }

        // Its `.onDisappear`, once its subtree's is booked - innermost first.
        leaving.append(contentsOf: node.destroying)
    }

    /// Starts a walk's scope with the standard providers, so any view resolves them
    /// and an app's own `.environment()` below is nearer (StandardEnvironment.swift).
    private func seedScope() {
        scope.removeAll(keepingCapacity: true)
        scope.append(contentsOf: StandardEnvironment.scope)
        focusStore.differ = self
        scope.append((key: ObjectIdentifier(FocusedValueStore.self), object: focusStore))
    }

    // MARK: - Identity

    /// A new element's key: the author's, or a fresh number.
    func identity(for node: Node) -> ElementId {
        node.id.map(ElementId.manual) ?? .auto(allocateElementId())
    }

    /// The next element id. Never reused.
    func allocateElementId() -> Int {
        let id = nextElementId
        nextElementId += 1
        return id
    }

    /// The next handler id. Never reused.
    func allocateHandlerId() -> Int {
        let id = nextHandlerId
        nextHandlerId += 1
        return id
    }
}
