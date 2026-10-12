// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// How an element arrives and goes: the values a host crosses an element from
// when it is inserted and to when it is removed - the SwiftUI vocabulary.
// Design: docs/design/types/animation.md#transitions

/// How a view looks as it is inserted and as it is removed.
///
/// A transition is a pair of visual deltas: the way in (`insertion`) and the
/// way out (`removal`), each naming which of the element's drawn properties
/// differ from how it stands:
///
///     Text("Ready").transition(.blur.combined(with: .offset(x: 48, y: 80)))
///
/// Inserted, the element arrives as the insertion phase says and animates to
/// where it stands; removed, it animates to the removal phase and goes, all
/// under the layout's animation or the one `.animation(_:)` names.
///
/// `move` slides by the element's own room: the host reads the frame the
/// layout gave it, so the same transition fits a small badge and a wide panel.
public struct AnyTransition: Equatable, Sendable {
    /// One half of a transition - how the element differs at the edge of its
    /// arrival, or where it goes by the end of its leaving.
    @_spi(Host) public struct Phase: Equatable, Sendable {
        /// The opacity the phase stands at, where said: `nil` keeps the element's.
        public var opacity: Double?

        /// The offset the phase stands at, where said.
        public var offset: Point?

        /// The scale the phase stands at across, where said.
        public var scaleX: Double?

        /// The scale the phase stands at down, where said.
        public var scaleY: Double?

        /// The point the scale hangs from, as a fraction across and down.
        public var pivot: UnitPoint?

        /// The blur the phase stands at, where said.
        public var blur: Double?

        /// The edge a `move` slides along - the element's own room across.
        public var move: Edge?

        /// A phase that changes nothing.
        public init() {}
    }

    /// How the element differs as it is inserted.
    @_spi(Host) public var insertion: Phase

    /// How the element differs as it is removed.
    @_spi(Host) public var removal: Phase

    /// The animation the crossing takes, where one is named - else the layout's.
    @_spi(Host) public var animation: Animation?

    /// A transition of the two phases, and the animation they cross under.
    @_spi(Host) public init(insertion: Phase, removal: Phase, animation: Animation? = nil) {
        self.insertion = insertion
        self.removal = removal
        self.animation = animation
    }
}

// MARK: - The spellings

extension AnyTransition {
    /// The transition that changes nothing: the element simply appears.
    ///
    ///     Text("Ready").transition(.identity)
    public static var identity: AnyTransition {
        AnyTransition(insertion: Phase(), removal: Phase())
    }

    /// Fades: arrives at 0 and leaves at 0.
    public static var opacity: AnyTransition {
        var phase = Phase()
        phase.opacity = 0
        return AnyTransition(insertion: phase, removal: phase)
    }

    /// Blurs: arrives blurred and clears, leaves blurring, radius 8 where said
    /// otherwise - the blur SCE's panels and popovers take.
    ///
    ///     Text("Ready").transition(.blur)
    public static var blur: AnyTransition {
        var phase = Phase()
        phase.blur = 8
        phase.opacity = 0
        return AnyTransition(insertion: phase, removal: phase)
    }

    /// Moved by a stated offset, both ways.
    ///
    ///     .transition(.offset(x: -48, y: 80))
    public static func offset(_ offset: Point) -> AnyTransition {
        var phase = Phase()
        phase.offset = offset
        return AnyTransition(insertion: phase, removal: phase)
    }

    /// Moved by `x` across and `y` down, both ways.
    public static func offset(x: Double = 0, y: Double = 0) -> AnyTransition {
        .offset(Point(x, y))
    }

    /// Sized by `scale` about `anchor`, both ways.
    ///
    ///     .transition(.scale(scale: 0.8, anchor: .top))
    public static func scale(scale: Double, anchor: UnitPoint = .center) -> AnyTransition {
        .scale(x: scale, y: scale, anchor: anchor)
    }

    /// Sized by `x` and `y` about `anchor`, both ways: `x` or `y` alone keeps
    /// the other axis where it stands.
    public static func scale(x: Double = 1, y: Double = 1, anchor: UnitPoint = .center) -> AnyTransition {
        var phase = Phase()
        phase.scaleX = x
        phase.scaleY = y
        phase.pivot = anchor
        return AnyTransition(insertion: phase, removal: phase)
    }

    /// Sized by `anchor` alone - `.scale(anchor: .leading)` - the SCE spelling.
    public static func scale(anchor: UnitPoint) -> AnyTransition {
        .scale(scale: 0, anchor: anchor)
    }

    /// Slides in and out by the element's own room along `edge`:
    /// `.move(edge: .trailing)` on a panel at the right clears its width.
    public static func move(edge: Edge) -> AnyTransition {
        var phase = Phase()
        phase.move = edge
        return AnyTransition(insertion: phase, removal: phase)
    }

    /// Slides along the leading edge - the SwiftUI shorthand.
    public static var slide: AnyTransition { .move(edge: .leading) }

    /// The transition a pair of modifiers describe: `active` is how the
    /// element differs at the edge, `identity` where it stands - the drawn
    /// properties the two write differently cross.
    ///
    ///     .transition(.modifier(active: Blurred(), identity: Plain()))
    ///
    /// A modifier that composes instead - wraps the view in an overlay, a
    /// background, another layout - describes no delta the host can cross;
    /// the properties it leaves on the view itself are the ones that move.
    ///
    /// - Parameters:
    ///   - active: The modifier whose look the element crosses from and to.
    ///   - identity: The modifier whose look the element rests at.
    @MainActor public static func modifier<M: ViewModifier>(active: M, identity: M) -> AnyTransition {
        let activeProps = props(of: active)
        let identityProps = props(of: identity)

        var phase = Phase()
        for (prop, value) in activeProps where identityProps[prop] != value {
            switch prop {
            case .opacity:
                phase.opacity = value.number
            case .blur:
                phase.blur = value.number
            case .scale:
                phase.scaleX = value.number
                phase.scaleY = value.number
            case .scaleX:
                phase.scaleX = value.number
            case .scaleY:
                phase.scaleY = value.number
            case .translationX:
                phase.offset = Point(
                    x: value.number ?? 0, y: phase.offset?.y ?? 0)
            case .translationY:
                phase.offset = Point(
                    x: phase.offset?.x ?? 0, y: value.number ?? 0)
            case .pivotX:
                phase.pivot = UnitPoint(
                    x: value.number ?? 0.5, y: phase.pivot?.y ?? 0.5)
            case .pivotY:
                phase.pivot = UnitPoint(
                    x: phase.pivot?.x ?? 0.5, y: value.number ?? 0.5)
            default:
                break
            }
        }
        return AnyTransition(insertion: phase, removal: phase)
    }

    /// The properties `modifier` leaves on a view it is applied to - how it
    /// differs read flat. The probe is a `Rectangle`: an element with a node
    /// of its own for the modifier to write on, found again by its type.
    @MainActor private static func props<M: ViewModifier>(of modifier: M) -> [Prop: PropValue] {
        var node = modifier.body(content: _ViewModifier_Content(view: AnyView(Rectangle()))).node
        node.materialize()
        return props(of: node, as: Rectangle().node.type)
    }

    /// The properties on the first node of `type` in the tree - the probe's.
    private static func props(of node: Node, as type: NodeType) -> [Prop: PropValue] {
        var node = node
        node.materialize()
        if node.type == type { return node.props }
        for child in node.children {
            let found = props(of: child, as: type)
            if !found.isEmpty || child.type == type { return found }
        }
        return [:]
    }

    /// Both halves - the second transition's phases over the first's, so the
    /// pieces each names move together:
    ///
    ///     .blur.combined(with: .offset(y: -48))
    public func combined(with other: AnyTransition) -> AnyTransition {
        AnyTransition(
            insertion: insertion.combined(with: other.insertion),
            removal: removal.combined(with: other.removal),
            animation: other.animation ?? animation)
    }

    /// A transition whose two halves differ - one way in, another out.
    ///
    ///     .asymmetric(insertion: .offset(y: -48), removal: .opacity)
    public static func asymmetric(insertion: AnyTransition, removal: AnyTransition) -> AnyTransition {
        AnyTransition(
            insertion: insertion.insertion,
            removal: removal.removal,
            animation: insertion.animation ?? removal.animation)
    }

    /// The animation this transition crosses under, over the layout's:
    ///
    ///     .transition(.blur.animation(.snappy))
    public func animation(_ animation: Animation?) -> AnyTransition {
        var copy = self
        copy.animation = animation
        return copy
    }
}

extension AnyTransition.Phase {
    /// This phase with `other`'s named parts over its own.
    func combined(with other: AnyTransition.Phase) -> AnyTransition.Phase {
        var phase = self
        if let value = other.opacity { phase.opacity = (phase.opacity ?? 1) * value }
        if let value = other.offset {
            phase.offset = Point(
                (phase.offset?.x ?? 0) + value.x, (phase.offset?.y ?? 0) + value.y)
        }
        if let value = other.scaleX { phase.scaleX = (phase.scaleX ?? 1) * value }
        if let value = other.scaleY { phase.scaleY = (phase.scaleY ?? 1) * value }
        if let value = other.pivot { phase.pivot = value }
        if let value = other.blur { phase.blur = (phase.blur ?? 0) + value }
        if let value = other.move { phase.move = value }
        return phase
    }
}

// MARK: - Crossing

extension AnyTransition {
    /// The component tags in a phase's encoding.
    private enum Component: Int32 {
        case opacity = 1, offset = 2, scale = 3, blur = 4, move = 5
    }
}

extension AnyTransition.Phase: HostRepresentable {
    /// The phase, as it crosses: only the parts it names.
    public var propValue: PropValue {
        var parts: [PropValue] = []
        if let opacity {
            parts.append(.values([.enumeration(AnyTransition.Component.opacity.rawValue), .number(opacity)]))
        }
        if let offset {
            parts.append(.values([
                .enumeration(AnyTransition.Component.offset.rawValue), .number(offset.x), .number(offset.y)]))
        }
        if scaleX != nil || scaleY != nil || pivot != nil {
            parts.append(.values([
                .enumeration(AnyTransition.Component.scale.rawValue),
                .number(scaleX ?? 1), .number(scaleY ?? 1),
                .number(pivot?.x ?? 0.5), .number(pivot?.y ?? 0.5)]))
        }
        if let blur {
            parts.append(.values([.enumeration(AnyTransition.Component.blur.rawValue), .number(blur)]))
        }
        if let move {
            parts.append(.values([
                .enumeration(AnyTransition.Component.move.rawValue), .enumeration(Int32(move.rawValue))]))
        }
        return .values(parts)
    }

    /// The phase back from what crossed.
    /// - Parameter propValue: what the host sent.
    public init?(propValue: PropValue) {
        guard case .values(let parts) = propValue else { return nil }
        self.init()

        for part in parts {
            guard case .values(let fields) = part,
                  case .enumeration(let tag)? = fields.first,
                  let component = AnyTransition.Component(rawValue: tag)
            else { continue }

            switch (component, fields.count) {
            case (.opacity, 2): opacity = fields[1].number
            case (.offset, 3):
                if let x = fields[1].number, let y = fields[2].number { offset = Point(x, y) }
            case (.scale, 5):
                scaleX = fields[1].number
                scaleY = fields[2].number
                if let x = fields[3].number, let y = fields[4].number { pivot = UnitPoint(x: x, y: y) }
            case (.blur, 2): blur = fields[1].number
            case (.move, 2):
                if let raw = fields[1].enumeration.flatMap({ Int8(truncatingIfNeeded: $0) }) {
                    move = Edge(rawValue: raw)
                }
            default: continue
            }
        }
    }
}

extension AnyTransition: HostRepresentable {
    /// The transition, as it crosses: the two phases and the animation.
    public var propValue: PropValue {
        .values([insertion.propValue, removal.propValue, animation.map(Self.animationValue) ?? .nothing])
    }

    /// The transition back from what crossed.
    /// - Parameter propValue: what the host sent.
    public init?(propValue: PropValue) {
        guard case .values(let parts) = propValue, parts.count == 3,
              let insertion = Phase(propValue: parts[0]), let removal = Phase(propValue: parts[1])
        else { return nil }

        self.init(insertion: insertion, removal: removal, animation: Self.animation(from: parts[2]))
    }

    /// An animation as it crosses inside a transition: law, length, curve,
    /// factor, and whether the host or an engine of the view's own moves it.
    private static func animationValue(_ animation: Animation) -> PropValue {
        .numbers([
            Double(animation.law.rawValue), Double(animation.millis),
            Double(animation.curve.rawValue), animation.factor,
            animation.isInherited ? 1 : 0, animation.isCustom ? 1 : 0])
    }

    /// The animation back, nil where `.nothing` crossed.
    private static func animation(from propValue: PropValue) -> Animation? {
        guard case .numbers(let fields) = propValue, fields.count == 6,
              let law = Animation.Law(rawValue: Int32(fields[0])),
              let curve = Easing(rawValue: Int32(fields[2]))
        else { return nil }

        return Animation(
            law: law, millis: UInt32(truncatingIfNeeded: UInt(max(fields[1], 0))),
            curve: curve, factor: fields[3], isInherited: fields[4] != 0, isCustom: fields[5] != 0)
    }
}
