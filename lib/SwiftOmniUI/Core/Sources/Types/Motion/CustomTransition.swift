// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// SwiftUI's custom `Transition` protocol: `body(content:phase:)` describes how
// a view looks at `.willAppear`, `.identity`, and `.didDisappear`. Probing the
// three discrete phases once distils the custom transition into `AnyTransition`
// so the host animates all combined drawing properties on its display clock
// with zero per-frame view rebuilds.

/// Discrete lifecycle stages passed to a `Transition` implementation.
public enum TransitionPhase: Hashable, Sendable {
    /// The view is being inserted and has not yet reached its resting state.
    case willAppear

    /// The view is mounted at its normal resting state.
    case identity

    /// The view is being removed toward its final disappearing state.
    case didDisappear

    /// Whether this phase represents the normal resting state.
    public var isIdentity: Bool { self == .identity }

    /// Numeric phase indicator matching SwiftUI: `-1` on `.willAppear`,
    /// `0` on `.identity`, and `1` on `.didDisappear`.
    public var value: Double {
        switch self {
        case .willAppear: -1.0
        case .identity: 0.0
        case .didDisappear: 1.0
        }
    }
}

/// Metadata describing behavioral traits of a `Transition`.
public struct TransitionProperties: Equatable, Sendable {
    /// Whether the transition includes spatial or scaling motion beyond a fade.
    public var hasMotion: Bool

    public init(hasMotion: Bool = true) {
        self.hasMotion = hasMotion
    }
}

/// Placeholder representing the target view inside `Transition.body(content:phase:)`.
public struct PlaceholderContentView<Value>: View {
    let probe: Node

    init(probe: Node) {
        self.probe = probe
    }

    public var node: Node { probe }
}

/// A description of view changes applied when a view appears and disappears,
/// aligned with SwiftUI's `Transition` protocol.
///
///     struct BlurSlideTransition: Transition {
///         func body(content: Content, phase: TransitionPhase) -> some View {
///             content
///                 .opacity(phase.isIdentity ? 1 : 0)
///                 .blur(radius: phase.isIdentity ? 0 : 8)
///                 .offset(y: phase == .willAppear ? 32 : (phase == .didDisappear ? -16 : 0))
///                 .scaleEffect(phase.isIdentity ? 1 : 0.94)
///         }
///     }
@preconcurrency @MainActor public protocol Transition {
    /// The view type produced for a phase.
    associatedtype Body: View

    /// Placeholder content passed into `body(content:phase:)`.
    typealias Content = PlaceholderContentView<Self>

    /// Describes the visual modifiers applied at `phase`.
    @ViewBuilder func body(content: Self.Content, phase: TransitionPhase) -> Self.Body

    /// Behavioral traits of this transition.
    static var properties: TransitionProperties { get }
}

extension Transition {
    public static var properties: TransitionProperties {
        TransitionProperties()
    }

    /// Combines this transition with `other` so all components animate together.
    public func combined<T: Transition>(with other: T) -> CombinedCustomTransition<Self, T> {
        CombinedCustomTransition(first: self, second: other)
    }

    /// Attaches an explicit `Animation` law to this transition.
    public func animation(_ animation: Animation?) -> AnimatedCustomTransition<Self> {
        AnimatedCustomTransition(base: self, animation: animation)
    }
}

/// Two `Transition` values composed in order.
public struct CombinedCustomTransition<First: Transition, Second: Transition>: Transition {
    public let first: First
    public let second: Second

    public init(first: First, second: Second) {
        self.first = first
        self.second = second
    }

    public static var properties: TransitionProperties {
        TransitionProperties(hasMotion: First.properties.hasMotion || Second.properties.hasMotion)
    }

    public func body(content: Content, phase: TransitionPhase) -> some View {
        let step = first.body(
            content: PlaceholderContentView<First>(probe: content.probe),
            phase: phase
        ).node
        second.body(
            content: PlaceholderContentView<Second>(probe: step),
            phase: phase
        )
    }
}

/// A `Transition` carrying an explicit `Animation` override.
public struct AnimatedCustomTransition<Base: Transition>: Transition {
    public let base: Base
    public let animationOverride: Animation?

    public init(base: Base, animation: Animation?) {
        self.base = base
        self.animationOverride = animation
    }

    public static var properties: TransitionProperties { Base.properties }

    public func body(content: Content, phase: TransitionPhase) -> some View {
        base.body(content: PlaceholderContentView<Base>(probe: content.probe), phase: phase)
    }
}

// MARK: - Built-in SwiftUI Transition Types

public struct IdentityTransition: Transition, Hashable, Sendable {
    public static var properties: TransitionProperties { TransitionProperties(hasMotion: false) }
    public init() {}
    public func body(content: Content, phase: TransitionPhase) -> some View { content }
}

public struct OpacityTransition: Transition, Hashable, Sendable {
    public static var properties: TransitionProperties { TransitionProperties(hasMotion: false) }
    public init() {}
    public func body(content: Content, phase: TransitionPhase) -> some View {
        content.opacity(phase.isIdentity ? 1 : 0)
    }
}

public struct ScaleTransition: Transition, Hashable, Sendable {
    public let scale: Double
    public let anchor: UnitPoint

    public init(_ scale: Double = 0, anchor: UnitPoint = .center) {
        self.scale = scale
        self.anchor = anchor
    }

    nonisolated public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.scale == rhs.scale && lhs.anchor == rhs.anchor
    }

    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(scale)
        hasher.combine(anchor.x)
        hasher.combine(anchor.y)
    }

    public func body(content: Content, phase: TransitionPhase) -> some View {
        content.scaleEffect(phase.isIdentity ? 1 : scale, anchor: anchor)
    }
}

public struct OffsetTransition: Transition, Hashable, Sendable {
    public let offset: Point

    public init(_ offset: Point) {
        self.offset = offset
    }

    nonisolated public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.offset == rhs.offset
    }

    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(offset.x)
        hasher.combine(offset.y)
    }

    public func body(content: Content, phase: TransitionPhase) -> some View {
        content.offset(x: phase.isIdentity ? 0 : offset.x, y: phase.isIdentity ? 0 : offset.y)
    }
}

public struct MoveTransition: Transition, Hashable, Sendable {
    public let edge: Edge

    public init(edge: Edge) {
        self.edge = edge
    }

    public func body(content: Content, phase: TransitionPhase) -> some View { content }
}

public struct PushTransition: Transition, Hashable, Sendable {
    public let edge: Edge

    public init(edge: Edge) {
        self.edge = edge
    }

    public func body(content: Content, phase: TransitionPhase) -> some View { content }
}

public struct BlurReplaceTransition: Transition, Hashable, Sendable {
    public enum Configuration: Hashable, Sendable {
        case downUp
        case upUp
    }

    public let configuration: Configuration

    public init(configuration: Configuration = .downUp) {
        self.configuration = configuration
    }

    public func body(content: Content, phase: TransitionPhase) -> some View {
        let scale: Double = switch (configuration, phase) {
        case (_, .identity): 1.0
        case (.downUp, .willAppear): 0.96
        case (.downUp, .didDisappear): 1.04
        case (.upUp, _): 0.96
        }
        content
            .opacity(phase.isIdentity ? 1 : 0)
            .blur(radius: phase.isIdentity ? 0 : 8)
            .scaleEffect(scale)
    }
}

extension Transition where Self == IdentityTransition {
    public static var identity: IdentityTransition { IdentityTransition() }
}

extension Transition where Self == OpacityTransition {
    public static var opacity: OpacityTransition { OpacityTransition() }
}

extension Transition where Self == ScaleTransition {
    public static var scale: ScaleTransition { ScaleTransition() }
    public static func scale(_ scale: Double, anchor: UnitPoint = .center) -> ScaleTransition {
        ScaleTransition(scale, anchor: anchor)
    }
}

extension Transition where Self == OffsetTransition {
    public static func offset(_ offset: Point) -> OffsetTransition { OffsetTransition(offset) }
    public static func offset(x: Double = 0, y: Double = 0) -> OffsetTransition {
        OffsetTransition(Point(x, y))
    }
}

extension Transition where Self == MoveTransition {
    public static func move(edge: Edge) -> MoveTransition { MoveTransition(edge: edge) }
    public static var slide: MoveTransition { MoveTransition(edge: .leading) }
}

extension Transition where Self == PushTransition {
    public static func push(from edge: Edge) -> PushTransition { PushTransition(edge: edge) }
}

extension Transition where Self == BlurReplaceTransition {
    public static var blurReplace: BlurReplaceTransition { BlurReplaceTransition() }
    public static func blurReplace(_ configuration: BlurReplaceTransition.Configuration) -> BlurReplaceTransition {
        BlurReplaceTransition(configuration: configuration)
    }
}

// MARK: - Distillation into AnyTransition

@MainActor private enum CustomTransitionCache {
    struct HashKey: Hashable {
        let type: ObjectIdentifier
        let value: AnyHashable
    }

    static var stateless: [ObjectIdentifier: AnyTransition] = [:]
    static var hashed: [HashKey: AnyTransition] = [:]
}

extension AnyTransition {
    /// Wraps a custom `Transition` in `AnyTransition` by sampling its discrete
    /// `.willAppear`, `.identity`, and `.didDisappear` phases once.
    @MainActor public init<T: Transition>(_ transition: T) {
        if let move = transition as? MoveTransition {
            self = .move(edge: move.edge)
            return
        }
        if let push = transition as? PushTransition {
            self = .push(from: push.edge)
            return
        }
        if MemoryLayout<T>.size == 0 {
            let key = ObjectIdentifier(T.self)
            if let cached = CustomTransitionCache.stateless[key] {
                self = cached
                return
            }
            let built = Self.distill(transition)
            if CustomTransitionCache.stateless.count >= 256 {
                CustomTransitionCache.stateless.removeAll(keepingCapacity: true)
            }
            CustomTransitionCache.stateless[key] = built
            self = built
            return
        }
        if let hashable = transition as? any Hashable {
            let key = CustomTransitionCache.HashKey(
                type: ObjectIdentifier(T.self),
                value: AnyHashable(hashable))
            if let cached = CustomTransitionCache.hashed[key] {
                self = cached
                return
            }
            let built = Self.distill(transition)
            if CustomTransitionCache.hashed.count >= 256 {
                CustomTransitionCache.hashed.removeAll(keepingCapacity: true)
            }
            CustomTransitionCache.hashed[key] = built
            self = built
            return
        }
        self = Self.distill(transition)
    }

    @MainActor private static func distill<T: Transition>(_ transition: T) -> AnyTransition {
        if let animated = transition as? any AnimatedTransitionUnwrapping {
            return animated.unwrappedTransition
        }
        if let combined = transition as? any CombinedTransitionUnwrapping {
            return combined.unwrappedTransition
        }
        let probe = Self.transitionProbeNode
        let identityNode = transition.body(
            content: PlaceholderContentView<T>(probe: probe),
            phase: .identity
        ).node
        let willAppearNode = transition.body(
            content: PlaceholderContentView<T>(probe: probe),
            phase: .willAppear
        ).node
        let didDisappearNode = transition.body(
            content: PlaceholderContentView<T>(probe: probe),
            phase: .didDisappear
        ).node

        let identityProps = Self.probeProps(of: identityNode)
        let insertionProps = Self.probeProps(of: willAppearNode)
        let removalProps = Self.probeProps(of: didDisappearNode)

        return AnyTransition(
            insertion: Self.phase(from: insertionProps, relativeTo: identityProps),
            removal: Self.phase(from: removalProps, relativeTo: identityProps)
        )
    }
}

@MainActor private protocol AnimatedTransitionUnwrapping {
    var unwrappedTransition: AnyTransition { get }
}

extension AnimatedCustomTransition: AnimatedTransitionUnwrapping {
    var unwrappedTransition: AnyTransition {
        AnyTransition(base).animation(animationOverride)
    }
}

@MainActor private protocol CombinedTransitionUnwrapping {
    var unwrappedTransition: AnyTransition { get }
}

extension CombinedCustomTransition: CombinedTransitionUnwrapping {
    var unwrappedTransition: AnyTransition {
        AnyTransition(first).combined(with: AnyTransition(second))
    }
}

extension VisualElementProperties {
    /// Attaches a custom `Transition` to this element.
    @MainActor public func transition<T: Transition>(_ transition: T) -> Modified {
        self.transition(AnyTransition(transition))
    }
}

extension View {
    /// Attaches a custom `Transition` to this view.
    @_disfavoredOverload
    @MainActor public func transition<T: Transition>(_ transition: T) -> ModifiedContent {
        self.transition(AnyTransition(transition))
    }
}
