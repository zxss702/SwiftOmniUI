// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// What a host holds (`RenderedNode`) and what it is told next (`HostPatch`).
// Design: docs/design/core/identity-and-diffing.md#keys

/// An element's key, stable for as long as the element lives.
///
/// `.auto` is a number the differ assigns and `.manual` is what the author
/// passed to `.id()`; the two never collide. An automatic key survives a render
/// while the element is written in the same place in the source, or stands at
/// the same position when put in by hand. A manual one survives anywhere, which
/// is what a collection needs.
public enum ElementId: Hashable, Sendable {
    /// Assigned by the differ, from a counter, never reused. Written as a
    /// number.
    case auto(Int)

    /// Written by the author with `.id()`. Written as text, which is what
    /// keeps the two namespaces from ever colliding.
    case manual(String)

    /// Whether the author named this one - an element matched by its builder path
    /// must not take an author's name.
    var isManual: Bool {
        if case .manual = self { return true }

        return false
    }
}

/// One element as it stands on the host - a class, so unchanged parts of one
/// tree are shared into the next.
final class RenderedNode {
    /// Who this element is. Fixed for as long as it stays in the tree.
    let id: ElementId

    /// The kind of control the host made; a change of it replaces the element.
    var type: NodeType

    /// Every property the host has been told about, as it was told.
    var props: [Prop: PropValue]

    /// Event token to the handler id the host quotes back, kept for as long as the
    /// element handles that event.
    var events: [Event: Int]

    /// The builder path the element was written at (`Node.key`).
    var key: String?

    /// The source row this element contributes to its lazy parent's geometry.
    var lazyIdentity: String?

    /// The composed views this element was built by, outermost first: each one's
    /// type, its state boxes by path, and what it was built with.
    /// Design: docs/design/core/identity-and-diffing.md#state-survives-a-rebuild
    var views: [(
        type: String,
        boxes: [(path: String, box: StateBox)],
        inputs: [(path: String, input: Input)])]

    /// What stood in for this element's subtree, kept so the clean walk can build it
    /// again without the parent; nil for a leaf.
    /// Design: docs/design/core/identity-and-diffing.md#the-clean-walk
    var placeholder: Node?

    /// The composed view whose body wrote this element, for `debugInfo()` in a bare
    /// container's braces.
    var view: String?

    /// The states this element's builds read. A lazy window can add dependencies
    /// while reusing its source; the renderer counts only the changed readers.
    /// Design: docs/design/core/invalidation.md#live-readers
    var reads: Set<ObjectIdentifier> {
        didSet {
            let added = reads.subtracting(oldValue)
            let removed = oldValue.subtracting(reads)
            if !added.isEmpty { Renderer.shared.reading(added) }
            if !removed.isEmpty { Renderer.shared.unreading(removed) }
        }
    }

    /// A lazy container's identities and row closures, before materialization.
    /// A data or environment rebuild replaces this with a fresh description.
    var lazySource: Node?

    /// How many times this element has been described, for `debugInfo()`.
    var builds: Int

    /// What this element provided to its subtree, pushed again by the clean walk.
    var provided: [(key: ObjectIdentifier, object: AnyObject)]

    /// The keyed environment this element wrote, overlaid again by the clean walk.
    var environmentValues = EnvironmentValues()

    /// The `.focusedValue` bag this element publishes while the focus stands
    /// in its subtree - what the `FocusedValueStore`'s chain fold reads. Kept
    /// so the clean walk folds the same tree.
    var focusedValues = FocusedValues()

    /// Its `.focusedSceneValue` writes, folded into its scene's answers the
    /// same way.
    var sceneFocusedValues = FocusedValues()

    /// The nearest provided object per type when the composed view here was built,
    /// which a carry compares.
    var seen: [ObjectIdentifier: ObjectIdentifier]

    /// The `.onChanged` values of its last build, in written order - the values
    /// only; the closures belong to their render.
    var watched: [Any]

    /// What `.onDisappear` runs as it leaves: its last build's closures.
    var destroying: [EventHandler] = []

    /// What the element holds for its life, where it asked for one.
    var session: AnyObject?

    /// The `.preference` offers this element wrote, kept for the clean walk
    /// which rebuilds the folded answers from them and its children.
    var preferenceSeeds: [PreferenceSeed] = []

    /// The `.transformPreference` rewrites of this element's offer, same
    /// keeping.
    var preferenceTransforms: [PreferenceTransform] = []

    /// What this element's subtree answers each key that asked, folded - the
    /// parents read from it; kept for the clean walk.
    var preferenceValues: [ObjectIdentifier: FoldedPreference] = [:]

    /// The `.onPreferenceChange` listeners of its last build, with the answer
    /// each last heard; the clean walk fires them, the full build compares
    /// them.
    var preferenceWatches: [PreferenceWatch] = []

    /// A text's layout box as this element last held it, so a rebuilt text
    /// under it takes the last report over (`TextLayoutBox.inherit`).
    var textLayoutBox: TextLayoutBox?

    /// Whether this element or one under it watches `key` - what a pushed
    /// report checks before it asks for a render.
    func listens(to key: ObjectIdentifier) -> Bool {
        preferenceWatches.contains { $0.box.key == key }
            || children.contains { $0.listens(to: key) }
    }

    /// The numbers its engines are registered under, in written order; the closures
    /// live on the board.
    var engines: [Int] = []

    /// Whether its sizes arrive at once because its layout is measured - kept for
    /// the clean walk.
    var sizesArrive = false

    /// The properties driven to a state, as the host was told them.
    var driven: [Prop: StateEntry] = [:]

    /// The readings `.samples` asked for here, held - which is how long one lives.
    /// Design: docs/design/core/journeys.md#readings
    let readings: [Sampling]

    /// The elements under it, in the order the host has them.
    var children: [RenderedNode]

    /// How its children were last told to animate; nil until said.
    var animation: Animation?

    /// And which parts of a child's place animated.
    var lanes: AnimationLanes = .all

    /// The values `.animation(_:value:)` watched last render, for arming.
    var gates: [AnyEquatableValue] = []

    /// What the user is doing to it that its visual states follow, and the state it is in; nil for an element that
    /// declares none.
    var visualInput: VisualInput?
    var visualState: String?

    /// One element as the host has it. Made by the differ.
    init(
        id: ElementId,
        type: NodeType,
        props: [Prop: PropValue],
        events: [Event: Int],
        animation: Animation? = nil,
        lanes: AnimationLanes = .all,
        gates: [AnyEquatableValue] = [],
        key: String? = nil,
        views: [(
            type: String,
            boxes: [(path: String, box: StateBox)],
            inputs: [(path: String, input: Input)])] = [],
        placeholder: Node? = nil,
        view: String? = nil,
        reads: Set<ObjectIdentifier> = [],
        builds: Int = 1,
        provided: [(key: ObjectIdentifier, object: AnyObject)] = [],
        seen: [ObjectIdentifier: ObjectIdentifier] = [:],
        watched: [Any] = [],
        engines: [Int] = [],
        driven: [Prop: StateEntry] = [:],
        readings: [Sampling] = [],
        children: [RenderedNode]
    ) {
        self.animation = animation
        self.lanes = lanes
        self.gates = gates
        self.views = views
        self.placeholder = placeholder
        self.view = view
        self.reads = reads
        self.builds = builds
        self.provided = provided
        self.seen = seen
        self.watched = watched
        self.engines = engines
        self.driven = driven
        self.readings = readings
        self.id = id
        self.type = type
        self.props = props
        self.events = events
        self.key = key
        self.children = children

        // A reader of what it read for as long as it lives; an element that read
        // nothing skips the lock.
        if !reads.isEmpty {
            Renderer.shared.reading(reads)
        }

        // And one of the living, for the tally's `alive`.
        Renderer.shared.nodeBorn()
    }

    deinit {
        if !reads.isEmpty {
            Renderer.shared.unreading(reads)
        }

        Renderer.shared.nodeGone()
    }
}

extension HostPatch {
    /// Whether this patch says nothing beyond naming the element, so its parent
    /// leaves it out. A changed driven set counts, an emptied one included.
    /// Design: docs/design/core/identity-and-diffing.md#merging-patches
    @_spi(Host) public var isEmpty: Bool {
        !replace
            && !lazyContentChanged
            && lazyIdentity == nil
            && animation == nil
            && properties.isEmpty
            && clearedProperties.isEmpty
            && events == nil
            && driven == nil
            && !children.hasChange
    }

    /// This patch followed by a later one about the same element, as one message.
    /// Design: docs/design/core/identity-and-diffing.md#merging-patches
    func merging(_ later: HostPatch) -> HostPatch {
        // Built again, and complete when it says so.
        if later.replace {
            return later
        }

        var merged = self

        // An element this message brings arrives at its values: no transition, nothing
        // cleared.
        for (prop, value) in later.properties {
            merged.properties[prop] = value
            merged.transitions[prop] = fresh ? nil : later.transitions[prop]
            merged.clearedProperties.removeAll { $0 == prop }
        }

        for prop in later.clearedProperties {
            merged.properties[prop] = nil
            merged.transitions[prop] = nil

            if !fresh, !merged.clearedProperties.contains(prop) {
                merged.clearedProperties.append(prop)
            }
        }

        merged.clearedProperties.sort()

        merged.lazyContentChanged = lazyContentChanged || later.lazyContentChanged
        merged.lazyIdentity = later.lazyIdentity ?? lazyIdentity
        merged.animation = later.animation ?? animation
        merged.driven = later.driven ?? driven
        merged.events = later.events ?? events
        merged.children = HostChildrenUpdate.merging(children, with: later.children)

        return merged
    }
}

extension HostChildrenUpdate {
    /// Whether this carries any child update; an empty arrangement removes every child.
    var hasChange: Bool {
        switch self {
        case .unchanged:
            false
        case .changed(let patches):
            !patches.isEmpty
        case .arranged:
            true
        }
    }

    /// The child patches, sparse or arranged.
    var patches: [HostPatch] {
        switch self {
        case .unchanged:
            []
        case .changed(let patches), .arranged(let patches):
            patches
        }
    }

    /// The children of two patches about one element: the later list where it is
    /// arranged, each child merged; otherwise the earlier list, the later merged in.
    fileprivate static func merging(
        _ earlier: HostChildrenUpdate,
        with later: HostChildrenUpdate
    ) -> HostChildrenUpdate {
        switch later {
        case .unchanged:
            return earlier

        case .arranged(let laterPatches):
            let earlierPatches = earlier.patches
            return .arranged(laterPatches.map { child in
                earlierPatches.first { $0.id == child.id }
                    .map { $0.merging(child) } ?? child
            })

        case .changed(let laterPatches):
            var merged = earlier.patches

            for child in laterPatches {
                if let at = merged.firstIndex(where: { $0.id == child.id }) {
                    merged[at] = merged[at].merging(child)
                } else {
                    // A sparse list names only children that stand.
                    if case .arranged = earlier {
                        assertionFailure(
                            "a later patch names a child the earlier arrangement has not got")
                    }
                    merged.append(child)
                }
            }

            if case .arranged = earlier {
                return .arranged(merged)
            }

            return .changed(merged)
        }
    }
}
