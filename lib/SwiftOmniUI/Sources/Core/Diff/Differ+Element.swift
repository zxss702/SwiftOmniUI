// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// One element reconciled: its composed views carried or built, its properties,
// events, engines and driven states compared, and the patch that says so.
// Design: docs/design/core/identity-and-diffing.md#carrying-a-view

extension Differ {
    /// Registers this element's engines, or hands the ones it has this render's
    /// closures; a different count starts over.
    /// Design: docs/design/core/identity-and-diffing.md#engines-on-an-element
    private func arm(
        _ declared: [EngineDeclaration],
        previous: [Int]?
    ) -> [Int] {
        if let previous = previous, previous.count == declared.count {
            var kept = true

            for (id, engine) in zip(previous, declared) {
                kept = Renderer.shared.board(for: engine.sync)
                    .rearm(id, following: engine.follows, with: engine.run) && kept
            }

            // Unless the board forgot them, as after a session claimed afresh: then they
            // are registered again under the numbers they had.
            if kept { return previous }
        }

        for id in previous ?? [] {
            Renderer.shared.disarm(id)
        }

        return declared.map { engine in
            let id = allocateHandlerId()

            Renderer.shared.board(for: engine.sync).arm(EngineEntry(
                id: id,
                priority: engine.priority,
                sync: engine.sync,
                follows: engine.follows,
                run: engine.run))

            return id
        }
    }

    /// Reconciles one element and returns it as it now stands, with the patch that
    /// gets the host there: a composed view carried whole, an element replaced, an
    /// element changed, or one unchanged whose empty patch its parent drops.
    ///
    /// `sizesArrive` says the layout it stands in is measured.
    func element(
        id: ElementId,
        rendered: RenderedNode?,
        node: Node,
        forced: Bool = false,
        sizesArrive: Bool = false
    ) -> (node: RenderedNode, patch: HostPatch) {
        var node = node

        // Whether an inspector's frame is open for this element
        // (Inspection.swift).
        var inspected = false
        defer { if inspected { Inspection.leave() } }

        var views: [(
            type: String,
            boxes: [(path: String, box: StateBox)],
            inputs: [(path: String, input: Input)])] = []

        // How many times this element has been described, this time included.
        let builds = (rendered?.builds ?? 0) + 1

        // The builder path belongs to where the element was written, so it is read
        // before any placeholder is unwrapped.
        let key = node.key

        // An aim takes the key this element settled on (Aim.swift).
        let written = node.aim
        written?.attach(id, walk: walkStamp)

        // The readings asked for here, keyed by their target and held by this element
        // (Sampling.swift).
        var readings: [Sampling] = []

        for (image, into, asks, take) in node.samples {
            readings.append(image.sample(into: into, every: asks.window, take: take))
        }

        // What `.environment()` provided here joins the scope before anything below
        // resolves; the count is kept for the clean walk.
        var pushed = node.environments.count
        let outerValues = envValues
        envValues = envValues.overlaid(with: node.environmentValues)
        let inputIsEnabled = envValues.isEnabled
        scope.append(contentsOf: node.environments)
        defer { scope.removeLast(pushed); envValues = outerValues }

        // What the element holds for its life - a page's session - handed back on every
        // build (ElementSession.swift).
        var session: AnyObject?

        if let request = node.session {
            let same = rendered?.views.first?.type == node.stateful?.viewType
            let object = (same ? rendered?.session : nil) ?? request.make()

            request.object = object
            session = object
            scope.append((key: request.type, object: object))
            pushed += 1
        }

        // And which views this element enters, for the containers under it.
        var entered = 0
        defer { bodies.removeLast(entered) }

        // The environments visible at a composed view, which a carry compares.
        // Design: docs/design/core/identity-and-diffing.md#what-a-carry-cannot-see
        var seen: [ObjectIdentifier: ObjectIdentifier] = [:]

        // What the clean walk needs to build this element again without its parent: a
        // composed view keeps its placeholder, a container its node with the content
        // still to run; a leaf keeps nothing.
        // Design: docs/design/core/identity-and-diffing.md#the-clean-walk
        var placeholder = node.stateful != nil || node.producer != nil ? node : nil

        // The node as written, which a leaf wearing a themed value keeps.
        let authored = node

        // Everything the builds below read, recorded against this element.
        var reads: Set<ObjectIdentifier> = []

        // The frame the last body build ran under, for the container content below.
        var frame: BuildScope.Frame?

        // The scene this element is in, held while it and its subtree are built.
        let outerScene = sceneRecord
        defer { sceneRecord = outerScene }

        // Unwraps nested placeholders, outermost first, until a real node comes out.
        while true {
            // A composed view: the same key holding the same kind of view keeps its state,
            // adopted before the body reads it.
            // Design: docs/design/core/identity-and-diffing.md#state-survives-a-rebuild
            if let stateful = node.stateful {
                let step = views.count

                if let record = stateful.scene, sceneRecord == nil {
                    sceneRecord = record
                }

                if let rendered = rendered,
                    step < rendered.views.count,
                    rendered.views[step].type == stateful.viewType {
                    // By path, not by position.
                    // Design: docs/design/core/identity-and-diffing.md#paths-pair-state
                    var kept: [String: StateBox] = [:]

                    for (path, box) in rendered.views[step].boxes where kept[path] == nil {
                        kept[path] = box
                    }

                    for (path, fresh) in stateful.boxes {
                        if let previous = kept[path] {
                            fresh.adopt(from: previous)
                        }
                    }
                }

                // A state a scene keeps takes the scene's storage for its key, before the body
                // reads it (SceneRecord.swift).
                if let record = sceneRecord {
                    for (_, box) in stateful.boxes {
                        (box as? SceneClaiming)?.claimScene(record)
                    }
                }

                views.append((
                    type: stateful.viewType, boxes: stateful.boxes, inputs: stateful.inputs))

                // Slots resolve against everything provided so far, before the body builds.
                stateful.resolve(from: scope, under: envValues)

                // A composed view built with the same inputs that read nothing that moved is
                // carried whole; decided on the outermost view alone.
                // Design: docs/design/core/identity-and-diffing.md#carrying-a-view
                if step == 0 {
                    seen = snapshot()

                    if let rendered = rendered, !forced, !describeAll, !stylesMoved,
                        let kept = rendered.views.first,
                        kept.type == stateful.viewType,
                        rendered.reads.isDisjoint(with: changed),
                        rendered.seen == seen,
                        rendered.inputIsEnabled == inputIsEnabled,
                        let wrote = rendered.placeholder,
                        sameWriting(node, as: wrote),
                        Input.same(stateful.inputs, kept.inputs) {
                        if Inspection.recording {
                            inspected = Inspection.enter(
                                stateful.viewType, .carried, element: id)
                        }

                        return carry(rendered, written: node)
                    }

                    if Inspection.recording {
                        inspected = Inspection.enter(
                            stateful.viewType,
                            .built(reason(stateful, node: node, rendered: rendered, seen: seen)),
                            element: id)
                    }
                }

                let built = BuildScope.Frame(
                    view: stateful.viewType,
                    builds: builds,
                    read: rendered?.reads ?? [],
                    changed: self.changed,
                    names: self.named,
                    everything: describeAll)

                frame = built
                bodies.append(stateful.viewType)
                entered += 1

                node = ReadScope.observed(into: &reads) {
                    BuildScope.within(built) { stateful.expand(over: node) }
                }
                pushed += node.environments.count
                envValues = envValues.overlaid(with: node.environmentValues)
                scope.append(contentsOf: node.environments)

                // An expansion can land on a node holding a session of its own -
                // the way a composed view's `NavigationStack` surfaces its
                // `links` only once the placeholder expanded to it. The check
                // above ran on the placeholder, so the session is handed now,
                // ahead of this element's own materialize: the object the same
                // element was rendered with, or the request's first make.
                if let request = node.session {
                    let same = rendered?.type == node.type
                    let object = (same ? rendered?.session : nil) ?? request.make()
                    request.object = object
                    session = session ?? object
                    scope.append((key: request.type, object: object))
                    pushed += 1
                }

                continue
            }

            break
        }

        // A `.focusedValue` written on this element or above it puts the whole
        // subtree in the publishing branch: any element there may be the one
        // holding the keyboard focus, so each reports the platform's moves -
        // which is how the store knows the chain.
        let outsideFocusScope = inFocusedScope
        inFocusedScope = inFocusedScope || !node.focusedValues.isEmpty
        defer { inFocusedScope = outsideFocusScope }

        // A scene written as a node rather than a scene type - a test's own tree.
        if node.type == .scene, sceneRecord == nil, case .manual(let name) = id {
            sceneRecord = Scenes.shared.record(id: name)
        }

        // A scene's `.focusedSceneValue` fold reads the authored node while
        // the walk stands inside it - what the scene publishes is answered
        // before the rendered element lands.
        let enteredScene = node.type == .scene ? (sceneRecord?.id ?? manualName(of: id)) : nil
        if let name = enteredScene {
            sceneNodes.append((id: name, node: node))
        }
        defer { if enteredScene != nil { sceneNodes.removeLast() } }

        // The container's own content runs here, inside this element's read scope and
        // build frame: the reader of a state is the closure that read it.
        // Design: docs/design/core/identity-and-diffing.md#containers-run-their-own-content
        let within = frame ?? bareFrame(for: rendered, builds: builds)

        // A container built again for what its own closure read: an inspector names the
        // view and the container.
        if Inspection.recording, forced, views.isEmpty {
            let owner = Inspection.short(within?.view ?? "a view")

            inspected = Inspection.enter(
                "\(owner) › \(node.type.name)",
                .built("for " + names(of: (rendered?.reads ?? []).intersection(changed))),
                element: id)
        }

        let lazySource = node.lazyWindow != nil ? node : nil
        let materialize = { () -> Node in
            let shallow = { () -> Node in
                var made = node
                made.materialize()
                return made
            }

            guard let within else { return shallow() }

            return BuildScope.within(within, shallow)
        }
        // Each lazy row observes its own closure. Observing the complete
        // materialization here would also subscribe the container to every
        // row's models, keeping those subscriptions after the rows leave.
        node = if lazySource?.lazyProducer != nil {
            ReadScope.collect(into: &reads, materialize)
        } else {
            ReadScope.observed(into: &reads, materialize)
        }

        // An aim on the root of a composed view's content is the same element.
        if let inner = node.aim, inner !== written {
            inner.attach(id, walk: walkStamp)
        }

        // The same for a reading written on that root.
        for (image, into, asks, take) in node.samples {
            readings.append(image.sample(into: into, every: asks.window, take: take))
        }

        // A fragment - a `TupleView`, `Group`, `ForEach` or `EmptyView` - is
        // transparent: it keeps no element of its own. What was written on it
        // lands on each child, and its children stand in their parent's list as
        // though written there; this node stays only to anchor the views above it.
        if node.type == .fragment {
            var grouped = node
            grouped.children = node.children.flatMap(\.asChildren).map { child in
                var child = child
                child.absorbFragmentWrites(of: node, environments: false)
                return child
            }

            // What stood here was a plain element: nothing of it carries over.
            if let rendered, rendered.type != .fragment {
                forget(rendered)
            }

            var patch = HostPatch(id: id, type: .fragment)
            let children = reconcileChildren(
                of: rendered?.type == .fragment ? rendered : nil,
                node: grouped, into: &patch, sizesArrive: sizesArrive)

            let result = RenderedNode(
                id: id,
                type: .fragment,
                props: [:],
                events: [:],
                key: key,
                views: views,
                placeholder: placeholder,
                view: within?.view,
                reads: reads,
                builds: builds,
                provided: Array(scope.suffix(pushed)),
                seen: seen,
                children: children)
            result.environmentValues = node.environmentValues
            result.inputIsEnabled = inputIsEnabled
            result.lazyIdentity = node.lazyIdentity
            // Its writes and listeners fanned out into the children above; what
            // a parent's fold reads of it is theirs alone.
            result.preferenceValues = foldedPreferences(seeds: [], transforms: [], children: children)
            result.session = session
            return (result, patch)
        }

        node.resolveEnabled(in: envValues)

        // The style is applied here, so a host receives every value already on the
        // control (Style.swift).
        node = styled(node, with: styles)
        node.resolveEnabled(in: envValues)

        // And its visual states resolved, the element reading what they follow.
        // Design: docs/design/views/styles.md#which-state-a-control-is-in
        let visualInput = node.visualStates.isEmpty ? nil : (rendered?.visualInput ?? VisualInput())
        var visualState: String?

        if let visualInput {
            visualState = resolveVisualStates(
                &node, input: visualInput, previous: rendered?.visualState, reads: &reads)

            if placeholder == nil {
                placeholder = authored
            }
        }

        node.resolveControlStyle(in: scope)
        node.resolveShapeFill()

        // Inside a publishing branch any element may be the one holding the
        // focus - it reports the platform's moves, which is how the store
        // knows what the chain publishes now.
        if inFocusedScope {
            let store = focusStore
            node.addHandler(.isFocusedChanged) {
                store.focusChanged(id, within: EventBuffer.current.first?.bool ?? false)
            }
        }

        // Themed values are picked here, which makes this element the color scheme's reader.
        // Design: docs/design/core/identity-and-diffing.md#themes
        if node.props.values.contains(where: \.isThemed) {
            node.props = ReadScope.collect(into: &reads) {
                node.props.mapValues { $0.isThemed ? $0.resolvingColorScheme() : $0 }
            }

            if placeholder == nil {
                placeholder = authored
            }
        }

        // A Canvas is mounted before its size is known. On a later rebuild,
        // reuse only the old allocation, then run the newest renderer at that
        // size. Its own reads are indexed separately from the view body's.
        var canvasReads: Set<ObjectIdentifier> = []
        if let canvas = node.canvas, node.props[.drawable] == nil {
            canvas.inheritSize(from: rendered?.type == node.type ? rendered?.canvas : nil)
            if let size = canvas.size {
                let drawing = canvas.drawing(at: size, force: true)
                node.props[.drawable] = drawing.commands.propValue
                canvasReads = drawing.reads ?? []
            }
        } else {
            // An explicitly supplied drawable is the source of the Canvas.
            node.canvas = nil
        }

        // Properties described last render and not now are named for the host to clear.
        // Design: docs/design/core/identity-and-diffing.md#properties-no-longer-described
        let lost = (rendered?.props.keys.filter { node.props[$0] == nil } ?? []).sorted()

        // Except those with no host default, which replace the element.
        // A different outer composed view at the same structural slot begins
        // a new lifetime even when both bodies produce the same native node.
        // Deeper type changes keep this element's outer lifetime; the builder
        // gives conditional branches distinct child keys.
        let outerViewChanged = rendered.map { old in
            old.views.first?.type != views.first?.type
        } ?? false
        let replace = rendered != nil
            && (rendered!.type != node.type || outerViewChanged
                || lost.contains { !$0.facts.cleared })

        // Nothing to build on: the element is new, or cannot become what is described.
        let previous = replace ? nil : rendered

        if replace, let rendered = rendered {
            forget(rendered)
        }

        // The engines this element runs, under numbers it keeps; a conversion's engines
        // come first, in property order. A replacement must arm new engines after
        // forgetting the old ones, rather than retaining IDs that forget disarms.
        // Design: docs/design/core/identity-and-diffing.md#engines-on-an-element
        let converting = node.driven.keys.sorted()
            .compactMap { node.driven[$0]!.conversion }
            .flatMap { $0.declarations() }
        let engines = arm(converting + node.engines, previous: previous?.engines)

        var patch = HostPatch(id: id, type: node.type)
        patch.replace = replace
        patch.fresh = describeAll || previous == nil
        if patch.fresh || node.lazyIdentity != previous?.lazyIdentity {
            patch.lazyIdentity = node.lazyIdentity
        }
        if patch.fresh || node.lazyRequestGeneration != previous?.lazyRequestGeneration {
            patch.lazyRequestGeneration = node.lazyRequestGeneration
        }

        // How this element's values animate: its own plan, or the application's.
        let plan = node.animation
        let standing = animation

        // The `.animation(_:value:)` gates whose watched value moved this render.
        let armed: Set<Int> = { () -> Set<Int> in
            guard let plan, let previous, previous.gates.count == plan.gates.count else {
                return []
            }

            return Set(plan.gates.indices.filter { !(previous.gates[$0] == plan.gates[$0].value) })
        }()

        // The transaction this render's writes ran under, with this element's
        // `.transaction(_:)` rewrites over it.
        let transacting = plan?.transaction(under: transaction) ?? transaction

        // A value gate rewrites this change's animation locally, including an
        // explicit nil. Otherwise the write's transaction overrides the
        // standing instruction without changing that instruction.
        let animating = { (values: AnimationValues) -> Animation in
            if transacting?.disablesAnimations == true { return .none }
            if transacting?.isGeometryFeedback == true, !values.isDisjoint(with: .size) { return .none }

            let resolved = (plan?.animation(for: values, armed: armed) ?? .inherited)
                .resolved(against: standing)

            if !armed.isEmpty { return resolved }
            if let override = transacting?.animation, !resolved.isCustom { return override }

            return resolved
        }

        // The standing instruction: what a change animates by where no write
        // named one - gates and transactions do not rewrite it.
        let travel = { (values: AnimationValues) in
            (plan?.animation(for: values) ?? .inherited).resolved(against: standing)
        }

        // What values with no kind of their own animate at.
        let travels = travel(.all)

        // An element that places children or answered `.animation(_:)` for itself says how
        // its children animate; `.inherited`, the default on both sides, is never said.
        // Design: docs/design/core/identity-and-diffing.md#layout-animation
        if NodeType.saysMotion.contains(node.type)
            || plan?.base != nil {
            let mine = node.type == .app
                ? animation
                : (plan?.animation(for: .place).map { $0.isInherited ? .inherited : $0 }
                    ?? .inherited)

            // Inherited until told otherwise; the application says its own once.
            let was: Animation? = node.type == .app
                ? (describeAll ? nil : previous?.animation)
                : (describeAll ? .inherited : (previous?.animation ?? .inherited))

            // Which parts of a child's place animate.
            var lanes = AnimationLanes.all

            if travel(.place).isNothing { lanes.subtract(.place) }
            if travel(.width).isNothing { lanes.subtract(.width) }
            if travel(.height).isNothing { lanes.subtract(.height) }

            // A measured layout's children take their sizes at once.
            if node.childSizesArrive { lanes.subtract([.width, .height]) }
            let stood = describeAll ? AnimationLanes.all : (previous?.lanes ?? .all)

            if was != mine || stood != lanes {
                patch.animation = HostLayoutMotion(animation: mine, lanes: lanes)
            }
            if node.type != .app, transacting != nil || !armed.isEmpty {
                // Resolve this write independently of the standing mask. An
                // idle application's .none must not disable withAnimation.
                var moving = AnimationLanes.all
                if animating(.place).isNothing { moving.subtract(.place) }
                if animating(.width).isNothing { moving.subtract(.width) }
                if animating(.height).isNothing { moving.subtract(.height) }
                if node.childSizesArrive { moving.subtract([.width, .height]) }
                if transacting?.isGeometryFeedback == true { moving = [] }
                patch.layoutTransition = HostLayoutMotion(animation: animating(.place), lanes: moving)
            }
        }

        // Nothing is cleared on an element described from scratch.
        patch.clearedProperties = replace ? [] : lost

        // `.onChanged` against what this continuing element carried last time; a
        // different count starts over.
        // Design: docs/design/core/identity-and-diffing.md#watching-values
        if let previous = previous, previous.watched.count == node.watches.count {
            for (index, watch) in node.watches.enumerated() {
                let old = previous.watched[index]

                // Nil: the stored value is of another type, and the slot starts over.
                if watch.matches(old) == false {
                    let new = watch.value
                    fire { try await watch.run(old, new) }
                }
            }
        }

        // `.onAppear` for an element that was not here.
        // Design: docs/design/core/identity-and-diffing.md#created-and-destroying
        if previous == nil {
            node.created.forEach(fire)
        }

        let tasks = reconcileTasks(node.tasks, previous: previous?.tasks ?? [])

        // Every property when there is nothing to compare against, or on a resync.
        let changed = previous.map { was in
            node.props.filter { key, value in was.props[key] != value }
        } ?? node.props

        patch.properties = describeAll ? node.props : changed

        // A property that changed on a continuing element animates to its new value; a
        // measured size arrives at once.
        // Design: docs/design/core/identity-and-diffing.md#transitions
        let measured = sizesArrive || node.reportsFrame

        if !describeAll, !replace, previous != nil,
            plan != nil || !travels.isNothing || transacting != nil {
            for (property, value) in patch.properties
            where value.moves && property.facts.travels
                && patch.transitions[property] == nil {
                if measured, !property.facts.moves.isDisjoint(with: [.width, .height]) { continue }

                let moves = animating(value.kind.union(property.facts.moves))

                if moves.isNothing { continue }

                patch.transitions[property] = HostTransition(animation: moves)
            }
        }

        // Handler ids are kept per event, assigned in name order.
        // Design: docs/design/core/identity-and-diffing.md#handlers-and-their-ids
        var events: [Event: Int] = [:]
        for (name, handler) in node.events.sorted(by: { $0.key < $1.key }) {
            let handlerId = previous?.events[name] ?? allocateHandlerId()
            events[name] = handlerId
            handlers[handlerId] = handler
            handlerEnvironments[handlerId] = envValues
        }

        if let previous = previous {
            // An event this element no longer handles takes its id with it.
            for (name, handlerId) in previous.events where events[name] == nil {
                handlers.removeValue(forKey: handlerId)
                handlerEnvironments.removeValue(forKey: handlerId)
            }
        }

        // Sent when the handled set changed; an empty map only for a continuing element.
        let eventsChanged = describeAll || previous == nil
            ? !events.isEmpty
            : Set(events.keys) != Set(previous!.events.keys)

        if eventsChanged {
            patch.events = .replace(events.mapValues { Int32($0) })
        }

        // The properties driven to a state, numbered in walk and name order; the set is
        // sent whenever it changed, an emptied one included.
        // Design: docs/design/core/identity-and-diffing.md#driven-properties
        var driven: [Prop: StateEntry] = [:]

        for key in node.driven.keys.sorted() {
            let registration = node.driven[key]!
            let state = registration.state

            // What `.inherited` means on this value can be answered only here; the answer
            // stays on the state and is read at the crossing.
            let mine = travel(key.facts.moves.union(registration.values))

            state.inherited = mine
            state.door = registration.kind

            driven[key] = StateEntry(
                number: Renderer.shared.number(for: state),
                mode: registration.mode,
                kind: registration.kind)
        }

        let tiesChanged = describeAll || previous == nil
            ? !driven.isEmpty
            : driven != previous!.driven

        if tiesChanged {
            patch.driven = .replace(driven.mapValues(HostStateBinding.init))
        }

        let children = withCustomLayoutOwner(node.type == .customLayout ? id : nil) {
            reconcileChildren(of: previous, node: node, into: &patch, sizesArrive: node.childSizesArrive)
        }

        if let source = lazySource {
            if describeAll || source.lazyRows !== previous?.lazySource?.lazyRows {
                patch.lazyRows = source.lazyRows
            }
            // Recreating a content closure (for example for a sibling's lifetime
            // counter) does not change the measurements of the retained rows.
            // Keep its fresh builders and handlers, but invalidate sizes only
            // when the source's reads, identities, or retained children changed.
            var contentReads = (previous?.reads ?? []).subtracting(source.lazyWindow.map { [$0] } ?? [])
            if let request = source.lazyRequestWindow { contentReads.remove(request) }
            let changedChildren: [HostPatch] = switch patch.children {
            case .arranged(let patches), .changed(let patches): patches
            case .unchanged: []
            }
            patch.lazyContentChanged = previous == nil
                || patch.lazyRows != nil
                || previous?.props[.items] != node.props[.items]
                || !contentReads.isDisjoint(with: self.changed)
                || changedChildren.contains { !$0.fresh && !$0.isEmpty }
        }

        // Native frames are only reported when they change. A fresh anchor
        // value on the same mounted element must retain the last frame and
        // identity before preferences are compared, including Text's origin.
        if let previous, previous.anchorBoxes.count == node.anchorBoxes.count {
            for (box, before) in zip(node.anchorBoxes, previous.anchorBoxes) where box !== before {
                box.inherit(from: before)
            }
        }

        // A text rebuilt under one element takes the last layout report over:
        // its folded answer keeps saying where the words stand until the host
        // says again.
        if let box = node.textLayoutBox,
            let before = previous?.textLayoutBox, box !== before {
            box.inherit(from: before)
        }

        // What the subtree answers each preference key, folded over the
        // children's settled answers; each observer fires once its answer
        // moves - and once on first mount, as `.onPreferenceChange` always
        // tells the value it found.
        // Design: docs/design/core/identity-and-diffing.md#preferences
        let folded = foldedPreferences(
            seeds: node.preferenceSeeds,
            transforms: node.preferenceTransforms,
            children: children)

        let preferenceWatches: [PreferenceWatch] = node.preferenceObservers.enumerated()
            .map { index, observer in
                let answer = folded[observer.box.key]?.value ?? observer.box.makeDefault()

                if previous?.preferenceWatches.count == node.preferenceObservers.count,
                    let heard = previous?.preferenceWatches[index].last {
                    if !observer.box.same(heard, answer) {
                        fire { try await observer.run(heard, answer) }
                    }
                } else {
                    fire { try await observer.run(answer, answer) }
                }

                return PreferenceWatch(box: observer.box, last: answer, run: observer.run)
            }

        let sourceReads = reads
        reads.formUnion(lazySource?.lazyRowReadings?.states ?? [])
        let canvasBodyReads = reads
        reads.formUnion(canvasReads)
        let result = RenderedNode(
            id: id,
            type: node.type,
            props: node.props,
            events: events,
            animation: patch.animation?.animation ?? previous?.animation ?? .inherited,
            lanes: patch.animation?.lanes ?? previous?.lanes ?? .all,
            gates: node.animation?.gates.map(\.value) ?? [],
            key: key,
            views: views,
            placeholder: placeholder,
            view: within?.view,
            reads: reads,
            builds: builds,
            provided: Array(scope.suffix(pushed)),
            seen: seen,
            watched: node.watches.map { $0.value },
            engines: engines,
            driven: driven,
            readings: readings,
            children: children
        )
        result.environmentValues = node.environmentValues
        result.inputIsEnabled = inputIsEnabled
        result.placementPlan = node.animation
        result.childSizesArrive = node.childSizesArrive
        result.lazySource = lazySource
        result.lazySourceReads = sourceReads
        result.lazyIdentity = node.lazyIdentity
        result.lazyRequestGeneration = node.lazyRequestGeneration
        result.canvas = node.canvas
        result.canvasReads = canvasReads
        result.canvasBodyReads = canvasBodyReads
        node.canvas?.owner = result
        result.sizesArrive = sizesArrive
        result.visualInput = visualInput
        result.visualState = visualState
        result.preferenceSeeds = node.preferenceSeeds
        result.anchorBoxes = node.anchorBoxes
        result.preferenceTransforms = node.preferenceTransforms
        result.preferenceValues = folded
        result.preferenceWatches = preferenceWatches
        result.textLayoutBox = node.textLayoutBox
        result.focusedValues = node.focusedValues
        result.sceneFocusedValues = node.sceneFocusedValues

        // What a host pulls mid-layout: the element's code objects by its id.
        // Replacing only a Layout value changes no serializable property or
        // child. Keep that update in the sparse patch so hosts take the new box.
        if previous != nil,
           !NodeCode.sameLayoutValues(codeObjects[id]?.values ?? [:], node.layoutValues),
           let owner = customLayoutOwners.last {
            customLayoutsWithChangedValues.insert(owner)
        }
        let childLayoutValuesChanged = customLayoutsWithChangedValues.remove(id) != nil
        let layoutObjectChanged = previous != nil && node.customLayout !== codeObjects[id]?.layout
        patch.customLayoutChanged = layoutObjectChanged || childLayoutValuesChanged
        if node.customLayout != nil || !node.layoutValues.isEmpty || node.canvas != nil {
            codeObjects[id] = NodeCode(layout: node.customLayout, values: node.layoutValues, canvas: node.canvas)
        } else {
            codeObjects.removeValue(forKey: id)
        }

        // What it runs as it leaves: this build's closures, the newest.
        result.destroying = node.destroying
        result.tasks = tasks
        result.session = session

        return (result, patch)
    }

    /// An element id's author-given name, where it has one.
    private func manualName(of id: ElementId) -> String? {
        if case .manual(let name) = id { return name }

        return nil
    }

    /// The frame a bare container's content runs under: the view the walk is in,
    /// with this element's own count and reads.
    private func bareFrame(for rendered: RenderedNode?, builds: Int) -> BuildScope.Frame? {
        guard let view = bodies.last ?? rendered?.view else { return nil }

        return BuildScope.Frame(
            view: view,
            builds: builds,
            read: rendered?.reads ?? [],
            changed: changed,
            names: named,
            everything: describeAll)
    }

    /// Why a composed view is built rather than carried, in words - the carry's
    /// questions in the carry's order. Asked only while an inspector records.
    private func reason(
        _ stateful: Node.Stateful,
        node: Node,
        rendered: RenderedNode?,
        seen: [ObjectIdentifier: ObjectIdentifier]
    ) -> String {
        guard let rendered else { return "first time" }

        let causes = rendered.reads.intersection(changed)

        if !causes.isEmpty {
            return "for " + names(of: causes)
        }

        if describeAll {
            return "the whole tree"
        }

        guard let kept = rendered.views.first, kept.type == stateful.viewType else {
            return "a different view here"
        }

        if stylesMoved {
            return "the styles moved"
        }

        if rendered.seen != seen {
            return "an environment it sees was replaced"
        }

        if let wrote = rendered.placeholder, !sameWriting(node, as: wrote) {
            return "its parent wrote it differently"
        }

        if let input = Input.difference(stateful.inputs, kept.inputs) {
            return "built with a new \(input)"
        }

        return "with its parent"
    }

    /// States by the names their authors gave them, in name order.
    private func names(of states: Set<ObjectIdentifier>) -> String {
        states.map { named[$0] ?? "state" }.sorted().joined(separator: ", ")
    }

    /// Whether the parent wrote the same things on a composed view as last render.
    /// Design: docs/design/core/identity-and-diffing.md#what-the-parent-wrote
    private func sameWriting(_ node: Node, as kept: Node) -> Bool {
        guard node.props == kept.props,
            NodeCode.sameLayoutValues(node.layoutValues, kept.layoutValues),
            node.inheritedMembers == kept.inheritedMembers,
            node.hasExplicitFontBasis == kept.hasExplicitFontBasis,
            node.lazyIdentity == kept.lazyIdentity,
            node.animation == kept.animation,
            node.children.isEmpty, kept.children.isEmpty,
            node.engines.isEmpty, kept.engines.isEmpty,
            node.samples.isEmpty, kept.samples.isEmpty,
            Set(node.events.keys) == Set(kept.events.keys),
            node.watches.count == kept.watches.count,
            node.created.count == kept.created.count,
            node.destroying.count == kept.destroying.count,
            node.tasks.count == kept.tasks.count,
            node.environments.count == kept.environments.count,
            node.driven.count == kept.driven.count,
            node.focusedValues.same(as: kept.focusedValues),
            node.sceneFocusedValues.same(as: kept.sceneFocusedValues)
        else { return false }

        for (fresh, old) in zip(node.watches, kept.watches)
        where fresh.matches(old.value) != true {
            return false
        }

        for (fresh, old) in zip(node.tasks, kept.tasks)
        where !fresh.matches(old.value) {
            return false
        }

        for (fresh, old) in zip(node.environments, kept.environments)
        where fresh.key != old.key || fresh.object !== old.object {
            return false
        }

        for (key, fresh) in node.driven {
            guard let old = kept.driven[key],
                fresh.state === old.state,
                fresh.kind == old.kind,
                fresh.mode == old.mode,
                fresh.values == old.values,
                fresh.conversion == nil,
                old.conversion == nil
            else { return false }
        }

        return true
    }

    /// Carries a composed element whose inputs, reads and writing all held: nothing
    /// under it is built, and the handlers the parent wrote on it are taken fresh.
    /// Design: docs/design/core/identity-and-diffing.md#what-the-parent-wrote
    private func carry(
        _ rendered: RenderedNode,
        written node: Node
    ) -> (node: RenderedNode, patch: HostPatch) {
        for (name, handler) in node.events {
            if let id = rendered.events[name] {
                handlers[id] = handler
            }
        }

        // Its `.onDisappear`: its body's last ones, then the parent's, taken fresh.
        rendered.destroying =
            Array(rendered.destroying.dropLast(node.destroying.count)) + node.destroying

        rendered.placeholder = node

        return revisit(rendered, walking: false)
    }

    /// The nearest provided object per type, by identity - what a carry compares.
    private func snapshot() -> [ObjectIdentifier: ObjectIdentifier] {
        var seen: [ObjectIdentifier: ObjectIdentifier] = [:]

        for entry in scope {
            seen[entry.key] = ObjectIdentifier(entry.object)
        }

        return seen
    }
}
