// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The tree an author writes: a `Node` is one element as written this render and
// is thrown away after it. Its key and handler ids belong to the element it
// describes (Tree.swift).
// Design: docs/design/core/identity-and-diffing.md#keys

/// A value in SwiftOmniUI's tree and at the host boundary. `.themed` stays in the
/// renderer until it picks the half in force.
public enum PropValue: Equatable, Sendable {
    /// Text someone wrote - a label's words, a placeholder, a url, an SVG path. A
    /// closed vocabulary is `.enumeration`, a name is `.name`, and a value with
    /// parts is `.values`.
    case string(String)

    /// One member of a closed vocabulary, as its number (the vocabularies under Types) - a bit
    /// set such as `FontAttributes` too.
    case enumeration(Int32)

    /// A value that is not there, said out loud: for a position in an act's
    /// arguments or in a list, where absence cannot be left out.
    case nothing

    /// A name from an open vocabulary - a style key, a visual state, a font family,
    /// a radio group. It crosses as the session's number for it.
    case name(String)

    /// A number. Everything numeric crosses as a Double.
    case number(Double)

    /// True or false.
    case bool(Bool)

    /// A fixed-length list of numbers - a structured value such as `EdgeInsets`, as
    /// left, top, right, bottom.
    case numbers([Double])

    /// A list of strings. What a Picker is given to choose from.
    case strings([String])

    /// Bytes as they stand - a file's contents read or written.
    case bytes([UInt8])

    /// A colour: four sRGB channels from 0 to 255, alpha included (Color.swift).
    case color(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)

    /// A list of values of any kind, for a value whose parts differ in shape - a
    /// brush (Brush.swift).
    case values([PropValue])

    /// A value with a half for each color scheme, resolved by the differ as the element is
    /// built. Never handed to a host.
    /// Design: docs/design/core/identity-and-diffing.md#themes
    indirect case themed(light: PropValue, dark: PropValue)

    /// Whether this value has components a host may animate; a host snaps any pair
    /// it cannot interpolate.
    var moves: Bool {
        switch self {
        case .number, .color, .numbers, .values: true
        default: false
        }
    }

    /// Which kind of value this is where the value itself says: a colour.
    var kind: AnimationValues {
        switch self {
        case .color, .values: .colour
        default: []
        }
    }

    /// Whether this value has a half for each color scheme anywhere in it.
    var isThemed: Bool {
        switch self {
        case .themed: true
        case .values(let values): values.contains { $0.isThemed }
        default: false
        }
    }

    /// This value with the half in force picked - a read of the color scheme.
    /// The conformance harness uses the same resolution for its expected native values.
    @_spi(Host) public func resolvingColorScheme() -> PropValue {
        switch self {
        case .themed(let light, let dark):
            (StandardEnvironment.appInfo.colorScheme == .dark ? dark : light).resolvingColorScheme()
        case .values(let values):
            .values(values.map { $0.resolvingColorScheme() })
        default:
            self
        }
    }

    /// The text, when this value is text - nil for any other kind. What an
    /// `onEvent` handler reads a TextField's new text with, and what the few
    /// places that read a property back off a node use.
    public var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// The number, when this value is one - nil for any other kind, so text is
    /// never read as a quantity.
    public var number: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    /// The member's number, when this value is one of a closed vocabulary -
    /// nil for any other kind, including a plain number, so nothing reads a
    /// font size as an alignment.
    public var enumeration: Int32? {
        if case .enumeration(let value) = self { return value }
        return nil
    }

    /// The name, when this value is one - nil for any other kind, text included.
    public var name: String? {
        if case .name(let value) = self { return value }
        return nil
    }

    /// The number as a whole one, when this value is a number - what an index
    /// or a position payload is read with. Rounds nothing: 2.0 answers 2, and
    /// text answers nil.
    public var int: Int? {
        if case .number(let value) = self { return Int(value) }
        return nil
    }

    /// True or false, when this value is one - nil for any other kind.
    public var bool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    /// The list of numbers, when this value is one - a frame report's eight
    /// coordinates, a selection's positions, a point's pair.
    public var numbers: [Double]? {
        if case .numbers(let value) = self { return value }
        return nil
    }

    /// The list of strings, when this value is one - what a Picker is given to
    /// choose from.
    public var strings: [String]? {
        if case .strings(let value) = self { return value }
        return nil
    }

    /// The bytes, when this value is a run of them - a file's contents.
    public var bytes: [UInt8]? {
        if case .bytes(let value) = self { return value }
        return nil
    }

    /// The four channels, when this value is a colour - nil for any other
    /// kind, so nothing mistakes a number for one.
    public var color: (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)? {
        if case .color(let red, let green, let blue, let alpha) = self {
            return (red: red, green: green, blue: blue, alpha: alpha)
        }
        return nil
    }

    /// The values, when this value is a list of them - see `.values`.
    public var values: [PropValue]? {
        if case .values(let value) = self { return value }
        return nil
    }
}

extension [PropValue] {
    /// The value at `index`, or nil when the list is shorter - how a value of an
    /// application's own reads the parts it crossed as:
    ///
    ///     init?(propValue: PropValue) {
    ///         guard let parts = propValue.values,
    ///               let latitude = parts.value(0)?.number,
    ///               let longitude = parts.value(1)?.number else { return nil }
    ///
    ///         self.init(latitude: latitude, longitude: longitude)
    ///     }
    public func value(_ index: Int = 0) -> PropValue? {
        indices.contains(index) ? self[index] : nil
    }
}

/// What a SwiftOmniUI event runs. It may await, and usually does not:
///
///     Button("Save").onClicked { saved = true }
///     Button("Open").onClicked { path.append(.details) }
///
/// It runs on `@MainActor`, the UI thread's actor: a handler that never awaits
/// finishes before the event returns, and one that awaits resumes in a later
/// turn. What it throws is reported to the host.
public typealias EventHandler = nonisolated(nonsending) () async throws -> Void

/// What an event that carries values runs - one parameter for each, in the order
/// the event declares them. An event with nothing to say takes an `EventHandler`.
///
///     TextField("").onTextChanged { text in query = text }
///     .onEvent(NotesContract.batteryChanged) { level, charging in … }
public typealias ValueEventHandler<each Value> = nonisolated(nonsending) (repeat each Value) async throws -> Void

/// One element of the UI tree: its type, properties, children and handlers.
///
/// Every element ends up as one, made from its contract, and a `Node` is itself
/// an `Element`, so one goes into any builder - which is how an application
/// describes a control it registered with a host:
///
///     struct Marker: View {
///         var node = Node(contract: MarkerContract.self)
///
///         func title(_ value: String) -> Self {
///             setValue(MarkerContract.title, value)
///         }
///     }
///
/// A type no host resolves draws the unknown-control marker rather than hiding
/// the rest of the interface.
public struct Node {
    /// The element's SwiftOmniUI type token, such as `.text`,
    /// `.vStack`, or an application's own registered type.
    public internal(set) var type: NodeType

    /// Who this element is, when the author says so - `.id("row-7")`. An element that
    /// keeps its key keeps its control, with its focus, caret and scroll offset;
    /// a collection's rows need one.
    public var id: String?

    /// The owning lazy source row, independent of a view's explicit identity.
    var lazyIdentity: String?

    /// The aim put on this view with `.aim(_:)`: a box the differ fills with the
    /// element's key. It takes no part in matching and never crosses.
    var aim: AimBox?

    /// The readings asked for with `.samples(_:into:_:)`, for the differ to put on
    /// the values they read. Never crosses (Sampling.swift).
    var samples: [(image: HostStorage, into: ObjectIdentifier, asks: Asks, take: @Sendable () -> Void)] = []

    /// The objects `.environment()` wrote here, in writing order, provided to this
    /// element and its subtree by type. Never crosses.
    var environments: [(key: ObjectIdentifier, object: AnyObject)] = []

    /// The keyed values `.environment(\.key, _)` wrote here, provided to this
    /// element and its subtree, nearer writes winning. Never crosses.
    var environmentValues = EnvironmentValues()

    /// What `.focusedValue` publishes while the focus is here. Never crosses.
    var focusedValues = FocusedValues()

    /// What `.focusedSceneValue` publishes scene-wide. Never crosses.
    var sceneFocusedValues = FocusedValues()

    /// What this element holds for its life, where it asks for something - a page's
    /// session (ElementSession.swift). Never crosses.
    var session: ElementSession?

    /// Where this node was written among its siblings - the builder path: which
    /// statement, which branch. Never crosses; the differ matches children by it.
    /// Design: docs/design/core/identity-and-diffing.md#keys
    var key: String?

    /// The element's properties, by token.
    var props: [Prop: PropValue]

    /// Inherited members retained for content built after its parent was written.
    struct InheritedMember: Equatable {
        let owner: ObjectIdentifier
        let value: PropValue
        var isDefault = false
    }
    var inheritedMembers: [Prop: InheritedMember] = [:]
    var hasExplicitFontBasis = false

    /// Nested nodes: the slot children modifiers append. A container's own content
    /// waits in its producer until the differ describes the element.
    public var children: [Node]

    /// A fixed frame owns view modifiers while its content keeps control members.
    var isFrameWrapper = false

    /// The container's content, run when the differ describes this element; nil once
    /// run.
    /// Design: docs/design/core/identity-and-diffing.md#containers-run-their-own-content
    var producer: (() -> [Node])?

    /// A transparent fragment's content before it is expanded. Node modifiers keep this
    /// source, so a lazy container can still ask for individual rows through them.
    enum LazyContent {
        case rows(any LazyRows)
        case elements([Element])
    }
    var lazyContent: LazyContent?

    /// Only this state changing can reuse a lazy container's prepared source.
    var lazyWindow: ObjectIdentifier?

    /// A viewport-only materialization can name retained rows before calling
    /// their builders. Values are their existing manual ids, including explicit ids.
    var lazyProducer: (([String: String]) -> [Node])?
    var lazyRowReadings: LazyRowReadings?

    /// Runs the producer, if pending, filing its nodes ahead of the slots. Idempotent.
    mutating func materialize(reusing rows: [String: String] = [:]) {
        lazyContent = nil
        if let make = lazyProducer {
            lazyProducer = nil
            producer = nil
            children = make(rows) + children
        } else if let make = producer {
            producer = nil
            children = make() + children
        }
        for (property, member) in inheritedMembers {
            for index in children.indices {
                children[index].inherit(property, member: member)
            }
        }
    }

    /// The visual states it declares, its style's merged in by the differ; and what
    /// `.onVisualStateChanged` runs (DeclaredState.swift).
    var visualStates: [DeclaredState] = []
    var visualStateListeners: [VisualStateListener] = []

    /// Each event's handler; the ids belong to the element, assigned by the differ.
    var events: [Event: EventHandler]

    /// The properties driven by a state and how each crosses - what `.opacity($fade)`
    /// records instead of a value (StateAttachment.swift).
    var driven: [Prop: StateRegistration] = [:]

    /// Whether this element reports its own frame, so its own size never animates.
    var reportsFrame: Bool {
        events[.frameChanged] != nil || events[.namedFramesChanged] != nil
            || events[.safeAreaInsetsChanged] != nil || driven[.frame] != nil
    }

    /// Whether this layout's children take their sizes at once: it or one of them is
    /// measured.
    var childSizesArrive: Bool {
        reportsFrame || children.contains(where: \.reportsFrame)
    }

    /// How this element's values animate - what `.animation(_:)` wrote - or nil for the
    /// application's. Per node, never inherited (Animation.swift).
    var animation: AnimationPlan?

    /// The values `.onChanged` watches, in written order (Changes.swift).
    var watches: [Watch] = []

    /// What `.onAppear` runs, in written order (Lifetime.swift).
    var created: [EventHandler] = []

    /// What `.onDisappear` runs, in written order.
    var destroying: [EventHandler] = []

    /// The pages `.navigationDestination` registered on this node: a page
    /// factory per presented value's type, and one an item binding drives.
    /// The enclosing navigation stack reads them from its root. Never crosses.
    var destinations: [ObjectIdentifier: (Any) -> Node] = [:]
    var itemDestination: ItemDestination?

    /// The `.preference`/`.anchorPreference` writes this node offers upward,
    /// in written order. Folded by the differ, never crossing the wire
    /// (Preferences.swift).
    var preferenceSeeds: [PreferenceSeed] = []

    /// The `.onPreferenceChange` listeners this node carries, in written
    /// order; the differ fires each whose key's folded answer moved.
    var preferenceObservers: [PreferenceObserver] = []

    /// The `.transformPreference` rewrites of what this node's subtree
    /// answers, applied after its own and its children's offers fold.
    var preferenceTransforms: [PreferenceTransform] = []

    /// A custom text renderer `.textRenderer` attached. A code object riding
    /// the node like `destinations` do - never crosses the wire; the prop
    /// `textRenderer` carries the `"custom"` marker hosts declare against.
    var textRenderer: (any TextRenderer)?

    /// The report a `Text.Layout` reads: shared by the `Text.LayoutKey` seed
    /// the element offers, the handler that hears `textLayoutChanged`, and
    /// `.customAttribute`, which writes the attributes a report puts back on
    /// its runs. Never crosses.
    var textLayoutBox: TextLayoutBox?

    /// A custom `Layout` object the element arranges its children by. A code
    /// object like `textRenderer` - registered with the differ so a host can
    /// pull it by the element's id; nothing of it crosses.
    var customLayout: LayoutBox?

    /// The `.layoutValue` tags this child carries for a custom `Layout`,
    /// by the key's identity; pulled by a host building `LayoutSubview`s.
    var layoutValues: [ObjectIdentifier: Any] = [:]

    /// A page `.navigationDestination(item:)` presents while its item is set.
    /// Design: docs/design/views/pages.md#navigation-destinations
    struct ItemDestination {
        /// The pushed page's node, or nil while the item is nil.
        var make: () -> Node?

        /// What a way back off the pushed page runs - clears the item.
        var dismiss: @Sendable () -> Void
    }

    /// The engines this element runs, in written order; the differ registers them
    /// under numbers the element keeps (Engine.swift).
    var engines: [EngineDeclaration] = []

    /// Set on a placeholder for a composed view whose body is not built yet
    /// (Stateful.swift).
    var stateful: Stateful?

    /// The stateful shells `.built` expanded to reach this node, kept so their
    /// `@State` boxes outlive the tree; a render keeps them on its record.
    var keptState: [Stateful] = []

    /// Adds a handler beside any the event already has, never instead of it.
    /// Design: docs/design/core/identity-and-diffing.md#handlers-and-their-ids
    mutating func addHandler(_ event: Event, _ handler: @escaping EventHandler) {
        let existing = events[event]

        events[event] = {
            try await existing?()
            try await handler()
        }
    }

    /// A node of a type with its parts already made - what `Node(contract:)` and the
    /// library's structure are written over.
    init(
        type: NodeType,
        id: String? = nil,
        props: [Prop: PropValue] = [:],
        children: [Node] = [],
        events: [Event: EventHandler] = [:]
    ) {
        self.type = type
        self.id = id
        self.props = props
        self.children = children
        self.events = events
    }

    /// A node of an element's own type: how every element's view begins.
    ///
    ///     struct TrafficLight: View {
    ///         var node = Node(contract: TrafficLightContract.self)
    ///     }
    ///
    /// - Parameters:
    ///   - contract: the element's contract, which names its node type.
    ///   - id: who this element is, when the author says so. Nil leaves it to
    ///     be identified by where it was written.
    ///   - children: the nodes under it, in order. Empty for a leaf control.
    public init<Declaration: ElementContract>(
        contract: Declaration.Type,
        id: String? = nil,
        children: [Node] = []
    ) {
        self.init(type: Declaration.nodeType, id: id, children: children)
    }
}

/// Anything that describes itself as a UI tree. A view is a value; SwiftOmniUI reads
/// `node` whenever it needs the element's description.
@preconcurrency @MainActor public protocol Element {
    /// This view as a node, read afresh on every render.
    var node: Node { get }
}

/// A `Node` is an `Element`, so raw nodes and controls mix in one builder.
extension Node: Element {
    /// Itself - a node already is what a view describes.
    public var node: Node { self }
}
