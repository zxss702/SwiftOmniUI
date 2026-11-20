// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore

/// What an animation moves: a state's channel, a described property, or a layout's place.
@_spi(Host) public enum AnimationTarget: Hashable, Comparable {
    /// One independently traveling run of lanes in the state with this number.
    case state(Int32, run: Int)

    /// A property a patch described, on one mounted element.
    case described(DescribedKey)

    /// The place a layout gave the mounted element with this key.
    case placed(UInt64)

    /// States first, then described properties, then places; each in key order.
    public static func < (left: Self, right: Self) -> Bool {
        switch (left, right) {
        case (.state(let a, let one), .state(let b, let other)): return (a, one) < (b, other)
        case (.described(let a), .described(let b)): return a < b
        case (.placed(let a), .placed(let b)): return a < b
        default: return left.rank < right.rank
        }
    }

    private var rank: Int {
        switch self {
        case .state: return 0
        case .described: return 1
        case .placed: return 2
        }
    }
}

/// One running animation of a value, pure in the time handed to it.
/// Design: docs/design/host/animation.md#one-animator
@_spi(Host) public struct RunningAnimation: Equatable {
    /// Where each lane began.
    public let from: [Double]

    /// Where each lane is going.
    public let destination: [Double]

    /// Each lane's speed when it began, per millisecond.
    public let velocity: [Double]

    /// The timing it runs under.
    public let animation: Animation

    /// When it began, in the frame clock's milliseconds.
    public let began: Double

    /// A measurement correction can continue from a sampled presentation
    /// without extending the original business animation's deadline.
    public let segmentBegan: Double

    /// A animation from `from` to `destination`, begun at `began`.
    public init(from: [Double], destination: [Double], velocity: [Double], animation: Animation, began: Double,
                segmentBegan: Double? = nil) {
        self.from = from
        self.destination = destination
        self.velocity = velocity
        self.animation = animation
        self.began = began
        self.segmentBegan = segmentBegan ?? began
    }

    /// Each lane's value and speed at `now`, and whether it has arrived.
    public func position(at now: Double) -> (value: [Double], velocity: [Double], rested: Bool) {
        let duration = Double(animation.millis)
        let remaining = began + duration - segmentBegan
        if animation.law == .eased && (remaining <= 0 || now >= began + duration)
            || animation.law == .spring && now - began >= HostMotionLaw.longest {
            return (destination, Array(repeating: 0, count: destination.count), true)
        }
        let rate = animation.law == .eased ? duration / remaining : 1
        let elapsed = max(0, now - segmentBegan) * rate
        return sample(using: HostMotionKernel(animation, elapsed: elapsed), rate: rate)
    }

    fileprivate func timingKey(at now: Double) -> AnimatorKernelKey? {
        let duration = Double(animation.millis)
        let remaining = began + duration - segmentBegan
        if animation.law == .eased && (remaining <= 0 || now >= began + duration)
            || animation.law == .spring && now - began >= HostMotionLaw.longest {
            return nil
        }
        let rate = animation.law == .eased ? duration / remaining : 1
        return AnimatorKernelKey(
            animation: animation,
            elapsed: max(0, now - segmentBegan) * rate,
            rate: rate
        )
    }

    @inline(__always)
    fileprivate func sample(
        using kernel: HostMotionKernel,
        rate: Double
    ) -> (value: [Double], velocity: [Double], rested: Bool) {
        if rate == 1 {
            let result = kernel.sample(from: from, destination: destination, velocity: velocity)
            return (result.value, result.velocity, result.rested)
        }
        let scaledIn = velocity.map { $0 / rate }
        let result = kernel.sample(from: from, destination: destination, velocity: scaledIn)
        if result.rested {
            return (result.value, result.velocity, true)
        }
        return (result.value, result.velocity.map { $0 * rate }, false)
    }

    /// Whether it starts where it ends, standing still: nothing to animate.
    public var arrives: Bool {
        zip(from, destination).allSatisfy { abs($0 - $1) < HostMotionLaw.still }
            && velocity.allSatisfy { abs($0) < HostMotionLaw.still }
    }
}

private struct AnimatorKernelKey: Equatable {
    let animation: Animation
    let elapsed: Double
    let rate: Double
}

/// Where one animation stands after the animator advances.
@_spi(Host) public struct AnimationStep {
    /// What the animation moves.
    public let target: AnimationTarget

    /// Each lane's value.
    public let value: [Double]

    /// Each lane's speed, per millisecond.
    public let velocity: [Double]

    /// Whether the animation arrived; an arrived animation has left the animator.
    public let rested: Bool
}

/// The runtime's one animator: every animation, advanced together in target order.
/// Design: docs/design/host/animation.md#one-animator
@_spi(Host) @MainActor public final class Animator {
    private(set) var sampledAt: Double?
    private var animations: [AnimationTarget: RunningAnimation] = [:]
    private var sortedTargets: [AnimationTarget] = []
    private var targetsDirty = false
    private var cachedKernels: [(key: AnimatorKernelKey, kernel: HostMotionKernel)] = []

    /// A animator with no animation under way.
    public init() {}

    /// Whether any animation is under way.
    public var isMoving: Bool { !animations.isEmpty }

    /// The animation under way for `target`.
    public func animation(for target: AnimationTarget) -> RunningAnimation? { animations[target] }

    /// Starts `animation` for `target`, in place of any animation it had.
    public func start(_ animation: RunningAnimation, for target: AnimationTarget) {
        if animations.updateValue(animation, forKey: target) == nil {
            sortedTargets.append(target)
            targetsDirty = true
        }
    }

    /// Ends `target`'s animation where it stands.
    public func halt(_ target: AnimationTarget) {
        animations.removeValue(forKey: target)
    }

    /// Advances every animation to `now` in target order; with less animation, each one arrives.
    public func advance(to now: Double, reducesMotion: Bool = false) -> [AnimationStep] {
        sampledAt = now
        guard !animations.isEmpty else {
            if !sortedTargets.isEmpty {
                sortedTargets.removeAll(keepingCapacity: true)
                targetsDirty = false
            }
            return []
        }

        if targetsDirty {
            sortedTargets = animations.keys.sorted()
            targetsDirty = false
        }

        var steps: [AnimationStep] = []
        steps.reserveCapacity(animations.count)
        cachedKernels.removeAll(keepingCapacity: true)
        var lastKey: AnimatorKernelKey?
        var lastKernel: HostMotionKernel?

        var writeIndex = 0
        for readIndex in sortedTargets.indices {
            let target = sortedTargets[readIndex]
            guard let animation = animations[target] else { continue }

            let position: (value: [Double], velocity: [Double], rested: Bool)
            if reducesMotion {
                position = (animation.destination, Array(repeating: 0, count: animation.destination.count), true)
            } else if let key = animation.timingKey(at: now) {
                let kernel: HostMotionKernel
                if lastKey == key, let hit = lastKernel {
                    kernel = hit
                } else if let hit = cachedKernels.first(where: { $0.key == key })?.kernel {
                    lastKey = key
                    lastKernel = hit
                    kernel = hit
                } else {
                    let built = HostMotionKernel(key.animation, elapsed: key.elapsed)
                    if cachedKernels.count < 16 {
                        cachedKernels.append((key, built))
                    }
                    lastKey = key
                    lastKernel = built
                    kernel = built
                }
                position = animation.sample(using: kernel, rate: key.rate)
            } else {
                position = (animation.destination, Array(repeating: 0, count: animation.destination.count), true)
            }

            if position.rested {
                animations.removeValue(forKey: target)
            } else {
                sortedTargets[writeIndex] = target
                writeIndex += 1
            }
            steps.append(AnimationStep(
                target: target,
                value: position.value,
                velocity: position.velocity,
                rested: position.rested
            ))
        }

        if writeIndex < sortedTargets.count {
            sortedTargets.removeSubrange(writeIndex..<sortedTargets.count)
        }

        return steps
    }

    /// Keeps only the animations whose target `keep` still has.
    public func retain(where keep: (AnimationTarget) -> Bool) {
        animations = animations.filter { keep($0.key) }
        targetsDirty = true
    }
}
