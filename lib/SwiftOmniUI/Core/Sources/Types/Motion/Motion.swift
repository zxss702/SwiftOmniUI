// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// How a value animates when it changes: one vocabulary for the application, an
// element, a state and a single write.
// Design: docs/design/types/animation.md#one-vocabulary-in-four-places

/// How a value animates when it changes.
///
/// A plain change arrives immediately. An animation says how a change moves
/// when a view, transaction, or application asks for one:
///
///     VStack { … }.animation(.spring(response: 0.26))
///
///     try await $fade.journey.move(to: 0.1, .easeOut(duration: 0.4))
///
/// `nil` where an `Animation?` is asked for applies a change at once. `.custom`
/// hands the animation to an engine of your own. `.easeInOut`,
/// `.spring(response:dampingFraction:)` and their kin name a timing law and its
/// numbers.
///
/// Design: docs/design/types/animation.md#two-laws
public struct Animation: Equatable, Sendable {
    /// Which timing law an animation follows. This library's own.
    @_spi(Host) public enum Law: Int32, Sendable {
        /// A stated duration on a stated curve.
        case eased = 0

        /// A mass on a spring - no duration, only a response.
        case spring = 1
    }

    /// The timing law this animation follows.
    @_spi(Host) public let law: Law

    /// Milliseconds: how long an eased animation takes, or a spring's response.
    @_spi(Host) public let millis: UInt32

    /// The curve an eased animation follows.
    @_spi(Host) public let curve: Easing

    /// A spring's damping; 0 for an eased animation.
    @_spi(Host) public let factor: Double

    /// Whether this animation is the one its element resolves to rather than one
    /// of its own.
    @_spi(Host) public let isInherited: Bool

    /// Whether an application engine animates the value instead of the host;
    /// see `custom`.
    @_spi(Host) public let isCustom: Bool

    /// The animation the element resolves to: its own, else the application's.
    ///
    /// What a write means when it names no animation, so a plain assignment and
    /// `move(to:)` agree about the animation and differ only in being awaited.
    @_spi(Host) public static let inherited = Animation(
        law: .eased, millis: 0, curve: .cubicOut, factor: 0, isInherited: true, isCustom: false)

    /// No animation: the change is applied at once.
    @_spi(Host) public static let none = Animation(
        law: .eased, millis: 0, curve: .cubicOut, factor: 0, isInherited: false, isCustom: false)

    /// The animation is yours: a write moves only the destination, the host
    /// animates nothing, and an engine of your own writes where the value is
    /// and how fast it is going, frame by frame, reading the destination back.
    ///
    ///     @State(animation: .custom) private var ball = 0.0
    ///
    ///     ColorPicker()
    ///         .offset(y: ball)
    ///         .engine(following: $ball) { cycle in
    ///             let journey = $ball.journey
    ///             let pull = (journey.destination - journey.value) * 0.2
    ///             journey.velocity += pull
    ///             journey.value += journey.velocity * cycle.elapsed / 1000
    ///             return abs(pull) > 0.01 ? .again : .wait
    ///         }
    ///
    /// Unlike an ordinary animation, a write changes only where the value is
    /// going; where it is stays put until the engine moves it. Declare it on
    /// the state, since which side animates a state is settled when the state
    /// first reaches the host.
    ///
    /// Design: docs/design/types/animation.md#custom-animates-in-an-engine
    public static let custom = Animation(
        law: .eased, millis: 0, curve: .cubicOut, factor: 0, isInherited: false, isCustom: true)

    /// An animation of a stated duration on a stated curve, in milliseconds -
    /// the shape every public constructor writes.
    ///
    /// - Parameters:
    ///   - length: how long it takes, in milliseconds.
    ///   - curve: how it spends that time.
    /// - Returns: the animation.
    @_spi(Host) public static func eased(_ length: UInt, _ curve: Easing = .cubicOut) -> Animation {
        Animation(
            law: .eased,
            millis: UInt32(truncatingIfNeeded: length),
            curve: curve,
            factor: 0,
            isInherited: false,
            isCustom: false)
    }

    /// A mass on a spring from a response in milliseconds and a damping -
    /// `spring(response:dampingFraction:)` in the unit this library counts.
    @_spi(Host) public static func spring(milliseconds response: UInt, damping: Double = 1) -> Animation {
        Animation(
            law: .spring,
            millis: UInt32(truncatingIfNeeded: max(response, 1)),
            curve: .linear,
            factor: max(damping, 0.05),
            isInherited: false,
            isCustom: false)
    }

    /// Whether this animation animates nothing - the value simply arrives.
    var isNothing: Bool {
        !isInherited && !isCustom && law == .eased && millis == 0
    }

    /// This animation, or `fallback` where this is the inherited one.
    func resolved(against fallback: Animation) -> Animation {
        isInherited ? fallback : self
    }

    /// A conventional 200-millisecond `.cubicOut` animation, used when an
    /// animation is requested without an explicit timing law.
    @_spi(Host) public static let standard = Animation.eased(200, .cubicOut)
}

extension Animation {
    /// The animation the library uses where none is named: a short ease-out.
    public static var `default`: Animation { .standard }

    /// This animation run faster - the time it takes divided by `speed`:
    /// `.snappy.speed(2)` lands in half the time.
    ///
    ///     withAnimation(.snappy.speed(2)) { … }
    public func speed(_ speed: Double) -> Animation {
        Animation(
            law: law, millis: UInt32(truncatingIfNeeded: UInt(max(1, Double(millis) / max(speed, 0.001)))),
            curve: curve, factor: factor, isInherited: isInherited, isCustom: isCustom)
    }
}

// MARK: - Eased

extension Animation {
    /// A linear animation over `duration` seconds.
    ///
    ///     .animation(.linear(duration: 0.3))
    public static func linear(duration: Double) -> Animation {
        .eased(UInt(duration * 1000), .linear)
    }

    /// A linear animation of the usual length.
    public static var linear: Animation { .linear(duration: 0.35) }

    /// An animation slow at the start - a cubic curve - over `duration`
    /// seconds.
    public static func easeIn(duration: Double) -> Animation {
        .eased(UInt(duration * 1000), .cubicIn)
    }

    /// Slow at the start, of the usual length.
    public static var easeIn: Animation { .easeIn(duration: 0.35) }

    /// An animation slow at the end - a cubic curve - over `duration` seconds:
    /// the usual choice for something arriving.
    public static func easeOut(duration: Double) -> Animation {
        .eased(UInt(duration * 1000), .cubicOut)
    }

    /// Slow at the end, of the usual length.
    public static var easeOut: Animation { .easeOut(duration: 0.35) }

    /// An animation slow at both ends - a cubic curve - over `duration`
    /// seconds.
    public static func easeInOut(duration: Double) -> Animation {
        .eased(UInt(duration * 1000), .cubicInOut)
    }

    /// Slow at both ends, of the usual length.
    public static var easeInOut: Animation { .easeInOut(duration: 0.35) }
}

// MARK: - Springs

extension Animation {
    /// A spring that settles in about `duration` seconds, `bounce` saying how
    /// much it overshoots: 0 for none, more for a springier landing.
    ///
    ///     .animation(.spring(duration: 0.4, bounce: 0.2))
    public static func spring(duration: Double = 0.5, bounce: Double = 0.0, blendDuration: Double = 0) -> Animation {
        _ = blendDuration
        return .spring(milliseconds: UInt(max(duration, 0.001) * 1000), damping: max(1 - bounce, 0.05))
    }

    /// A mass on a spring, answering a change rather than timing it.
    ///
    ///     .animation(.spring(response: 0.26))
    ///
    /// It has no stated duration: a spring settles when it is done, and one
    /// whose destination changes mid-animation carries on from the speed it
    /// had. That makes it right for anything the user can interrupt - a card
    /// being dragged, a value still being chosen.
    ///
    /// - Parameters:
    ///   - response: how quickly it answers, in seconds. Smaller is snappier.
    ///   - dampingFraction: 1 comes to rest without overshooting; below 1
    ///     overshoots and oscillates, which is rarely what a user expects.
    ///   - blendDuration: how long two animations merge over - unwritten: this
    ///     library's springs blend for free.
    /// - Returns: the animation.
    @_disfavoredOverload
    public static func spring(response: Double = 0.5, dampingFraction: Double = 0.825, blendDuration: Double = 0) -> Animation {
        _ = blendDuration
        return .spring(milliseconds: UInt(max(response, 0.001) * 1000), damping: dampingFraction)
    }

    /// A spring of the usual feel.
    public static var spring: Animation { .spring() }

    /// A spring for something the user's finger is on: quick, gently damped.
    public static var interactiveSpring: Animation { .interactiveSpring() }

    /// `interactiveSpring` of a stated length.
    public static func interactiveSpring(duration: Double = 0.15, extraBounce: Double = 0.0, blendDuration: Double = 0.25) -> Animation {
        .spring(duration: duration, bounce: 0.28 + extraBounce, blendDuration: blendDuration)
    }

    /// A spring with no bounce - smooth to its destination.
    public static var smooth: Animation { .smooth() }

    /// `smooth` of a stated length.
    public static func smooth(duration: Double = 0.5, extraBounce: Double = 0.0) -> Animation {
        .spring(duration: duration, bounce: extraBounce)
    }

    /// A quick spring with a little bounce.
    public static var snappy: Animation { .snappy() }

    /// `snappy` of a stated length.
    public static func snappy(duration: Double = 0.5, extraBounce: Double = 0.0) -> Animation {
        .spring(duration: duration, bounce: 0.15 + extraBounce)
    }

    /// A spring that bounces.
    public static var bouncy: Animation { .bouncy() }

    /// `bouncy` of a stated length.
    public static func bouncy(duration: Double = 0.5, extraBounce: Double = 0.0) -> Animation {
        .spring(duration: duration, bounce: 0.3 + extraBounce)
    }
}

// MARK: - Springs by physics

extension Animation {
    /// A spring described by its physics: `mass`, `stiffness` and `damping`.
    ///
    /// The response and damping it works out to are what the host animates;
    /// `initialVelocity` is a property of the moving value, which this
    /// library's springs keep by carrying on from the speed they had.
    public static func interpolatingSpring(mass: Double = 1.0, stiffness: Double, damping: Double, initialVelocity: Double = 0.0) -> Animation {
        _ = initialVelocity
        let m = max(mass, 0.001), k = max(stiffness, 0.001)
        let response = 2 * .pi * (m / k).squareRoot()
        let dampingFraction = damping / (2 * (k * m).squareRoot())
        return .spring(milliseconds: UInt(max(response, 0.001) * 1000), damping: max(dampingFraction, 0.05))
    }

    /// An interpolating spring of a stated `duration` and `bounce`.
    public static func interpolatingSpring(duration: Double = 0.5, bounce: Double = 0.0, initialVelocity: Double = 0.0) -> Animation {
        _ = initialVelocity
        return .spring(duration: duration, bounce: bounce)
    }

    /// An interpolating spring of the usual feel.
    public static var interpolatingSpring: Animation { .interpolatingSpring() }
}
