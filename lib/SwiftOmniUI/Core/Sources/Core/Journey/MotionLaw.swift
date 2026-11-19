// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The platform's C maths library, for the spring's `exp`, `sin` and `cos`.
#if canImport(Android)
import Android
#elseif canImport(Glibc)
import Glibc
#elseif canImport(CRT)
import CRT
#endif

// The two animation laws as numbers, in closed form in the time since an animation
// began. Every runtime animates with these; `MotionLawTests` holds them to
// their promises.
// Design: docs/design/core/journeys.md#animation-laws

/// Where an animation stands at one instant of its law.
@_spi(Host) public struct HostMotionSample: Equatable, Sendable {
    /// The value of each lane.
    public let value: [Double]

    /// How fast each lane is going, per millisecond.
    public let velocity: [Double]

    /// Whether the animation has arrived: every lane at its destination and still.
    public let rested: Bool
}

/// Precomputed time-dependent coefficients for an `Animation` at a given `elapsed` millisecond instant.
///
/// Dozens or hundreds of combined property and layout animations started in the same
/// transaction share one `(Animation, elapsed)` pair on every display tick. Computing
/// the transcendental basis (`exp`, `sin`, `cos`, `sqrt`, curve & slope) once in a
/// kernel reduces each lane evaluation to a few scalar multiplies and adds while keeping
/// bit-for-bit identical results with `HostMotionLaw.sample`.
@_spi(Host) public struct HostMotionKernel: Sendable {
    fileprivate enum Storage: Sendable {
        case landed
        case eased(
            length: Double,
            curve: Easing,
            progress: Double,
            amount: Double,
            climbOverLength: Double,
            h00: Double,
            h10Length: Double,
            h01: Double,
            d00OverLength: Double,
            d10: Double,
            d01OverLength: Double
        )
        case springCritical(
            frequency: Double,
            elapsed: Double,
            decay: Double
        )
        case springUnderdamped(
            damped: Double,
            dampFreq: Double,
            decay: Double,
            cosine: Double,
            sine: Double
        )
        case springOverdamped(
            first: Double,
            second: Double,
            span: Double,
            expFirst: Double,
            expSecond: Double
        )
    }

    fileprivate let storage: Storage

    /// Precomputes the evaluation kernel for `animation` at `elapsed` milliseconds.
    public init(_ animation: Animation, elapsed: Double) {
        switch animation.law {
        case .eased:
            let length = Double(animation.millis)
            guard length > 0, elapsed < length else {
                storage = .landed
                return
            }
            let progress = elapsed / length
            let amount = HostMotionLaw.ease(animation.curve, at: progress)
            let climbOverLength = HostMotionLaw.slope(animation.curve, at: progress) / length
            let h00 = ((2 * progress) - 3) * progress * progress + 1
            let h10 = ((progress - 2) * progress + 1) * progress
            let h01 = (3 - (2 * progress)) * progress * progress
            let d00 = (6 * progress * progress) - (6 * progress)
            let d10 = (3 * progress * progress) - (4 * progress) + 1
            let d01 = (6 * progress) - (6 * progress * progress)
            storage = .eased(
                length: length,
                curve: animation.curve,
                progress: progress,
                amount: amount,
                climbOverLength: climbOverLength,
                h00: h00,
                h10Length: h10 * length,
                h01: h01,
                d00OverLength: d00 / length,
                d10: d10,
                d01OverLength: d01 / length
            )

        case .spring:
            guard elapsed < HostMotionLaw.longest else {
                storage = .landed
                return
            }
            let response = Double(max(animation.millis, 1))
            let damping = max(animation.factor, 0.01)
            let frequency = 2 * Double.pi / response
            if abs(damping - 1) < 1e-6 {
                storage = .springCritical(
                    frequency: frequency,
                    elapsed: elapsed,
                    decay: exp(-frequency * elapsed)
                )
            } else if damping < 1 {
                let damped = frequency * sqrt(1 - (damping * damping))
                let dampFreq = damping * frequency
                storage = .springUnderdamped(
                    damped: damped,
                    dampFreq: dampFreq,
                    decay: exp(-dampFreq * elapsed),
                    cosine: cos(damped * elapsed),
                    sine: sin(damped * elapsed)
                )
            } else {
                let root = frequency * sqrt((damping * damping) - 1)
                let first = -(frequency * damping) + root
                let second = -(frequency * damping) - root
                storage = .springOverdamped(
                    first: first,
                    second: second,
                    span: first - second,
                    expFirst: exp(first * elapsed),
                    expSecond: exp(second * elapsed)
                )
            }
        }
    }

    /// Evaluates a single lane without allocating intermediate arrays unless needed.
    @inline(__always)
    public func evaluateLane(
        from: Double,
        destination target: Double,
        velocity initialSpeed: Double
    ) -> (value: Double, velocity: Double, rested: Bool) {
        switch storage {
        case .landed:
            return (target, 0, true)

        case let .eased(_, _, _, amount, climbOverLength, h00, h10Length, h01, d00OverLength, d10, d01OverLength):
            if initialSpeed == 0 {
                let delta = target - from
                return (from + (delta * amount), delta * climbOverLength, false)
            } else {
                let v = (h00 * from) + (h10Length * initialSpeed) + (h01 * target)
                let s = (d00OverLength * from) + (d10 * initialSpeed) + (d01OverLength * target)
                return (v, s, false)
            }

        case let .springCritical(frequency, elapsed, decay):
            let displacement = from - target
            let b = initialSpeed + (frequency * displacement)
            let term = displacement + (b * elapsed)
            let remaining = term * decay
            let derivative = (b - (frequency * term)) * decay
            if abs(remaining) <= HostMotionLaw.still && abs(derivative) <= HostMotionLaw.still {
                return (target, 0, true)
            }
            return (target + remaining, derivative, false)

        case let .springUnderdamped(damped, dampFreq, decay, cosine, sine):
            let a = from - target
            let b = (initialSpeed + (dampFreq * a)) / damped
            let combo = (a * cosine) + (b * sine)
            let remaining = decay * combo
            let derivative = decay * ((-dampFreq * combo) + (damped * ((b * cosine) - (a * sine))))
            if abs(remaining) <= HostMotionLaw.still && abs(derivative) <= HostMotionLaw.still {
                return (target, 0, true)
            }
            return (target + remaining, derivative, false)

        case let .springOverdamped(first, second, span, expFirst, expSecond):
            let displacement = from - target
            let c1 = (initialSpeed - (second * displacement)) / span
            let c2 = displacement - c1
            let term1 = c1 * expFirst
            let term2 = c2 * expSecond
            let remaining = term1 + term2
            let derivative = (term1 * first) + (term2 * second)
            if abs(remaining) <= HostMotionLaw.still && abs(derivative) <= HostMotionLaw.still {
                return (target, 0, true)
            }
            return (target + remaining, derivative, false)
        }
    }

    /// Evaluates an arbitrary lane vector using this precomputed kernel.
    public func sample(
        from: [Double],
        destination: [Double],
        velocity: [Double]
    ) -> HostMotionSample {
        let count = destination.count
        guard from.count == count, velocity.count == count else {
            return HostMotionSample(
                value: destination,
                velocity: Array(repeating: 0, count: count),
                rested: true
            )
        }
        if case .landed = storage {
            return HostMotionSample(
                value: destination,
                velocity: Array(repeating: 0, count: count),
                rested: true
            )
        }
        if count == 1 {
            let single = evaluateLane(from: from[0], destination: destination[0], velocity: velocity[0])
            if single.rested {
                return HostMotionSample(value: destination, velocity: [0], rested: true)
            }
            return HostMotionSample(value: [single.value], velocity: [single.velocity], rested: false)
        }

        var rested = true
        var speed = Array<Double>(unsafeUninitializedCapacity: count) { buffer, initialized in
            initialized = count
            for i in 0..<count { buffer[i] = 0 }
        }
        let value = Array<Double>(unsafeUninitializedCapacity: count) { valBuf, initialized in
            initialized = count
            for lane in 0..<count {
                let step = evaluateLane(
                    from: from[lane],
                    destination: destination[lane],
                    velocity: velocity[lane]
                )
                valBuf[lane] = step.value
                speed[lane] = step.velocity
                if !step.rested { rested = false }
            }
        }
        if rested {
            return HostMotionSample(
                value: destination,
                velocity: Array(repeating: 0, count: count),
                rested: true
            )
        }
        return HostMotionSample(value: value, velocity: speed, rested: false)
    }
}

/// The two animation laws, evaluated from the time since an animation began.
///
/// Time is in milliseconds, the unit of `Animation`'s numbers, so velocity is per
/// millisecond. A journey reports its velocity per second; an animator converts
/// where it reports.
@_spi(Host) public enum HostMotionLaw {
    /// How near its destination and how slow a lane is when it counts as arrived: in
    /// the value's own units, and per millisecond for the speed. A thousandth of a
    /// colour channel or of a point is below any display's resolution.
    public static let still = 0.001

    /// The longest a spring animates, in milliseconds. A spring has no stated end;
    /// this keeps any animation from holding a display clock awake for ever.
    public static let longest = 10_000.0

    /// Where an animation stands `elapsed` milliseconds after it began.
    ///
    /// An eased animation from a standstill follows its curve exactly. A lane that
    /// began moving follows the cubic Hermite of the same length instead, from the
    /// value and speed it had to its destination at a standstill. A spring settles
    /// each lane on its own, and the animation rests when all of them have.
    ///
    /// - Parameters:
    ///   - animation: The law and its numbers.
    ///   - elapsed: Milliseconds since the animation began.
    ///   - from: Where each lane began.
    ///   - destination: Where each lane is going.
    ///   - velocity: How fast each lane was going when it began, per
    ///     millisecond.
    /// - Returns: The value and velocity at that instant, and whether the
    ///   animation has arrived. Lanes that do not pair up land at once.
    public static func sample(
        _ animation: Animation,
        elapsed: Double,
        from: [Double],
        destination: [Double],
        velocity: [Double]
    ) -> HostMotionSample {
        guard from.count == destination.count, from.count == velocity.count else {
            return landed(destination)
        }
        return HostMotionKernel(animation, elapsed: elapsed).sample(
            from: from,
            destination: destination,
            velocity: velocity
        )
    }

    /// An animation at its destination, standing still.
    private static func landed(_ destination: [Double]) -> HostMotionSample {
        HostMotionSample(
            value: destination,
            velocity: Array(repeating: 0, count: destination.count),
            rested: true)
    }

    /// How far through the change an eased animation is when `progress` of its
    /// length has passed: 0 at the start and 1 at the end, and past 1 and back on the
    /// curves that overshoot.
    static func ease(_ curve: Easing, at progress: Double) -> Double {
        let value = min(max(progress, 0), 1)

        switch curve {
        case .linear:
            return value
        case .sineOut:
            return sin(value * .pi / 2)
        case .sineIn:
            return 1 - cos(value * .pi / 2)
        case .sineInOut:
            return (1 - cos(value * .pi)) / 2
        case .cubicIn:
            return value * value * value
        case .cubicOut:
            let shifted = value - 1
            return (shifted * shifted * shifted) + 1
        case .cubicInOut:
            if value < 0.5 { return 4 * value * value * value }
            let shifted = (2 * value) - 2
            return (shifted * shifted * shifted / 2) + 1
        case .bounceOut:
            return bounceOut(value)
        case .bounceIn:
            return 1 - bounceOut(1 - value)
        case .springIn:
            return value * value * ((2.70158 * value) - 1.70158)
        case .springOut:
            let shifted = value - 1
            return (shifted * shifted * ((2.70158 * shifted) + 1.70158)) + 1
        }
    }

    /// How steeply `curve` climbs at `progress`, per unit of progress: a central
    /// difference on the curve, a function of progress alone.
    static func slope(_ curve: Easing, at progress: Double) -> Double {
        let step = 1e-4
        let from = min(max(progress - step, 0), 1)
        let to = min(max(progress + step, 0), 1)
        guard to > from else { return 0 }
        return (ease(curve, at: to) - ease(curve, at: from)) / (to - from)
    }

    private static func bounceOut(_ value: Double) -> Double {
        if value < 1 / 2.75 {
            return 7.5625 * value * value
        }
        if value < 2 / 2.75 {
            let shifted = value - (1.5 / 2.75)
            return (7.5625 * shifted * shifted) + 0.75
        }
        if value < 2.5 / 2.75 {
            let shifted = value - (2.25 / 2.75)
            return (7.5625 * shifted * shifted) + 0.9375
        }

        let shifted = value - (2.625 / 2.75)
        return (7.5625 * shifted * shifted) + 0.984375
    }
}
