// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// What `@FocusedValue` resolves from: the element the platform says holds the
// keyboard focus, the `.focusedValue` bags on the path down to it, and the
// `.focusedSceneValue` bags of the scene it stands in - one per differ, read
// as a state so a move of the focus rebuilds exactly the readers.

/// What a scene's `.focusedSceneValue` offers its windows - an `OfferingScene`
/// carries it to `SceneElement` the way an environment object goes, and the
/// store's fold picks it out of the element's provided objects.
final class FocusedSceneBag {
    /// The writes collected so far.
    var values = FocusedValues()
}

/// The focus chain's store: which element holds the keyboard, and the values
/// the elements above it publish. Every element inside a publishing branch
/// reports the platform's focus moves here; the chain itself is folded off
/// the rendered tree the last walk left.
final class FocusedValueStore: NamedState {
    /// What an inspector calls a rebuild the focus caused.
    var origin: String? { "the focus" }

    /// The differ whose `lastRendered` the chain is folded off - weak, the
    /// differ owns the store.
    weak var differ: Differ?

    /// The element the platform says holds the keyboard focus, where it
    /// stands in a publishing branch; nil everywhere else. Only publishing
    /// branches are heard: focus is exclusive, so the tracked holder's own
    /// report of losing it clears the chain whatever took it.
    private(set) var focused: ElementId?

    /// Whether the folds below answer the tree the last walk left - a focus
    /// report and every finished walk marks it.
    private var dirty = true

    /// The `.focusedValue` bags on the path from the root to `focused`,
    /// outermost first so the nearer publisher wins.
    private var resolvedChain = FocusedValues()

    /// The `.focusedSceneValue` answers of the scene `focused` stands in;
    /// nil where nothing stands focused.
    private var resolvedScene: FocusedValues?

    /// The whole tree's scene answers, folded - what a reader standing
    /// outside every scene resolves.
    private var defaultScene = FocusedValues()

    /// Each scene's folded answers, by its record - filled as readers ask.
    private var sceneBags: [ObjectIdentifier: (record: SceneRecord, bag: FocusedValues)] = [:]

    /// An element's focus report, through the handler the differ puts on
    /// every element inside a publishing branch.
    func focusChanged(_ element: ElementId, within: Bool) {
        let moved: Bool

        if within {
            moved = focused != element
            focused = element
        } else {
            moved = focused == element
            focused = nil
        }

        guard moved else { return }

        dirty = true
        Renderer.shared.stateChanged(self)
    }

    /// A walk finished: the folds are re-answered over the tree it left, and
    /// a moved answer - a `.focusedValue` now saying something else, the
    /// focused element gone - rebuilds the readers. Compared rather than
    /// told, so a walk that changed nothing asks for nothing.
    func stale() {
        let chain = resolvedChain
        let scene = resolvedScene
        let fallback = defaultScene
        let bags = sceneBags

        dirty = true
        refresh()

        var moved = !chain.same(as: resolvedChain)
            || !fallback.same(as: defaultScene)
            || (scene == nil) != (resolvedScene == nil)

        if !moved, let scene, let resolvedScene {
            moved = !scene.same(as: resolvedScene)
        }

        if !moved {
            for each in bags.values where !each.bag.same(as: sceneValues(for: each.record)) {
                moved = true
                break
            }
        }

        if moved {
            Renderer.shared.stateChanged(self)
        }
    }

    /// What `.focusedValue` resolves for a reader standing in `scene`: the
    /// focused branch's writes on top, the scene's own beneath - the focused
    /// element's scene where one stands focused, the reader's otherwise.
    func values(for scene: SceneRecord?) -> FocusedValues {
        refresh()
        return (resolvedScene ?? sceneValues(for: scene)).overlaid(with: resolvedChain)
    }

    /// What `.focusedSceneValue` publishes in `scene`, folded over the whole
    /// of it - a reader sees the answers wherever in the scene it stands.
    func sceneValues(for scene: SceneRecord?) -> FocusedValues {
        refresh()

        guard let scene else { return defaultScene }

        let key = ObjectIdentifier(scene)

        if let found = sceneBags[key] { return found.bag }

        // The authored scene first - a reader inside a scene still being
        // built is answered from the tree it is written as - then the
        // rendered one.
        let bag = differ?.sceneNodes.last(where: { $0.id == scene.id }).map(\.node).map(folded)
            ?? sceneElement(for: scene).map(folded)
            ?? FocusedValues()
        sceneBags[key] = (record: scene, bag: bag)
        return bag
    }

    /// Refolds what a focus report or a finished walk marked: the chain off
    /// the rendered tree, and the fallback bag beside it - off the authored
    /// tree while a walk is inside one, so a first render answers already.
    private func refresh() {
        guard dirty else { return }
        dirty = false

        resolvedChain = FocusedValues()
        resolvedScene = nil
        sceneBags.removeAll(keepingCapacity: true)

        if let authored = differ?.authoredRoot {
            defaultScene = folded(authored)
        } else {
            defaultScene = differ?.lastRendered.map(folded) ?? FocusedValues()
        }

        guard let root = differ?.lastRendered,
            let focused, let path = path(to: focused, in: root)
        else { return }

        for element in path {
            resolvedChain = resolvedChain.overlaid(with: element.focusedValues)
        }

        resolvedScene = path.last(where: { $0.type == .scene }).map(folded) ?? defaultScene
    }

    /// The element `record`'s scene stands as, among the tree's.
    private func sceneElement(for record: SceneRecord) -> RenderedNode? {
        guard let root = differ?.lastRendered else { return nil }

        return sceneElement(in: root, named: record.id)
    }

    /// The `.scene` element named `id` under this one, or nil.
    private func sceneElement(in element: RenderedNode, named id: String) -> RenderedNode? {
        if element.type == .scene, element.id == .manual(id) { return element }

        for child in element.children {
            if let found = sceneElement(in: child, named: id) { return found }
        }

        return nil
    }

    /// The path from `element` down to `id`, outermost first - nil where the
    /// element is not here, as when the focused view left the tree.
    private func path(to id: ElementId, in element: RenderedNode) -> [RenderedNode]? {
        if element.id == id { return [element] }

        for child in element.children {
            if let rest = path(to: id, in: child) { return [element] + rest }
        }

        return nil
    }

    /// The `.focusedSceneValue` writes and offered scene bags under `element`,
    /// folded into one - what a scene publishes as a whole. Asked of an
    /// authored node while a walk is inside it, of a rendered one after.
    private func folded<Each: FocusFolded>(_ element: Each) -> FocusedValues {
        var bag = element.foldedSceneValues

        for entry in element.foldedOffers where entry.key == ObjectIdentifier(FocusedSceneBag.self) {
            if let offered = entry.object as? FocusedSceneBag {
                bag = bag.overlaid(with: offered.values)
            }
        }

        for child in element.foldedChildren {
            bag = bag.overlaid(with: folded(child))
        }

        return bag
    }
}

/// A node the scene fold can walk - authored while a walk is inside it,
/// rendered after.
private protocol FocusFolded {
    /// The elements under it.
    var foldedChildren: [Self] { get }

    /// The `.focusedSceneValue` writes of its own.
    var foldedSceneValues: FocusedValues { get }

    /// The objects it provides its subtree - where a scene's offer rides.
    var foldedOffers: [(key: ObjectIdentifier, object: AnyObject)] { get }
}

extension RenderedNode: FocusFolded {
    var foldedChildren: [RenderedNode] { children }
    var foldedSceneValues: FocusedValues { sceneFocusedValues }
    var foldedOffers: [(key: ObjectIdentifier, object: AnyObject)] { provided }
}

extension Node: FocusFolded {
    var foldedChildren: [Node] { children }
    var foldedSceneValues: FocusedValues { sceneFocusedValues }
    var foldedOffers: [(key: ObjectIdentifier, object: AnyObject)] { environments }
}
