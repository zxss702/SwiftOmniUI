// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore

/// A view a layout places, at a rectangle in its layout's coordinates, y growing down.
@_spi(Host) @MainActor public protocol PlacedView: AnyObject {
    /// The rectangle the view stands at.
    var placedFrame: Rect { get set }

    /// Where the view's place travels, told as it sets out, and nil once it stands: a view laying out words lays
    /// them out at that size while its place travels, never at the sizes it passes through.
    /// Design: docs/design/host/animation.md#words-at-their-destination
    func travels(to destination: Rect?)
}

extension PlacedView {
    /// Nothing of the view's own follows where its place travels.
    public func travels(to destination: Rect?) {}
}

/// How one arrangement of a layout places its children.
@_spi(Host) public struct Arrangement {
    /// The timing children animate and fade in under.
    public var law: Animation

    /// Which sides of a changed place animate; none where every child arrives.
    public var lanes: AnimationLanes

    /// Whether a child that joins the layout fades in.
    public var fades: Bool

    /// Whether business geometry feedback requires the complete frame to arrive.
    public var framesRead: Bool

    /// An arrangement that animates `lanes` under `law`, fading in a joining child when `fades`.
    public init(
        law: Animation = .none, lanes: AnimationLanes = [],
        fades: Bool = false, framesRead: Bool = false
    ) {
        self.law = law
        self.lanes = lanes
        self.fades = fades
        self.framesRead = framesRead
    }
}

/// The places layouts give their children, animated there instead of jumped to.
/// Design: docs/design/host/animation.md#layout-animation
@_spi(Host) @MainActor public final class LayoutMotion {
    /// The place a layout gave one child; the view is held weakly.
    private struct Seat {
        weak var view: (any PlacedView)?
        var standing: Rect?
    }

    private let animator: Animator
    private let now: () -> Double
    private let reducesMotion: () -> Bool
    private var seats: [UInt64: Seat] = [:]

    /// The application's animation, which a layout that says nothing of its own animates under.
    public var applicationMotion: Animation = .none

    /// Called when an animation starts, so the frame clock is held while it runs.
    public var onStart: () -> Void = {}

    /// Layout animation whose animations `animator` advances, on `now`'s time.
    public init(animator: Animator, now: @escaping () -> Double, reducesMotion: @escaping () -> Bool) {
        self.animator = animator
        self.now = now
        self.reducesMotion = reducesMotion
    }

    /// How an arrangement places a layout's children: `said` when a patch reached the layout,
    /// `resized` when its own width changed, `framesRead` when a frame under it is read.
    public func arrangement(said: Bool, resized: Bool, animation: HostLayoutMotion?, framesRead: Bool) -> Arrangement {
        let lanes = animation?.lanes ?? .all

        guard said, !lanes.isEmpty, let law = law(of: animation)
        else { return Arrangement(framesRead: framesRead) }

        return Arrangement(law: law, lanes: resized || framesRead ? [] : lanes,
                           fades: true, framesRead: framesRead)
    }

    /// The timing `animation` resolves to, or nil where nothing animates.
    public func law(of animation: HostLayoutMotion?) -> Animation? {
        let law = animation.map { $0.animation.isInherited ? applicationMotion : $0.animation } ?? applicationMotion
        return Self.moves(law) && !reducesMotion() ? law : nil
    }

    /// Stands `view` at `target`, or on its way there; `stated` are the sides it sizes itself.
    public func place(
        _ view: any PlacedView,
        mount: UInt64,
        at target: Rect,
        stated: AnimationLanes,
        fadeIn: ((Animation, Rect) -> Void)?,
        arrivedFrom: Rect? = nil,
        anchorOffset: Point = .zero,
        in arrangement: Arrangement
    ) {
        guard mount != 0 else {
            view.placedFrame = target
            return
        }
        // Joining rows (including a matched-geometry arrival) have no old
        // presentation in this viewport to compensate.
        let anchorOffset = seats[mount] == nil ? Point.zero : anchorOffset

        // A child with no seat yet is already where it belongs - unless a
        // `matchedGeometry` match left it a frame to fly from; one joining a
        // standing layout fades in.
        if seats[mount] == nil {
            seats[mount] = Seat(view: view)
            guard let arrivedFrom, !arrangement.lanes.isEmpty, Self.isReal(arrivedFrom) else {
                view.placedFrame = target
                if arrangement.fades { fadeIn?(arrangement.law, target) }
                return
            }
            view.placedFrame = arrivedFrom
        }

        let seat = seats[mount]!
        seats[mount]?.view = view
        let key = AnimationTarget.placed(mount)
        let destination = Self.lanes(target)
        let running = animator.animation(for: key)

        // The same place asked for again keeps its animation rather than starting it over.
        if let running, running.destination == destination, !arrangement.framesRead, anchorOffset == .zero {
            if let standing = seat.standing { view.placedFrame = standing }
            return
        }

        // A correction to a stationary side does not finish another side's journey.
        // Keep its original timing while the corrected sides arrive immediately.
        if let running, arrangement.lanes.isEmpty, !arrangement.framesRead, anchorOffset == .zero,
           destination.indices.allSatisfy({ running.destination[$0] == destination[$0]
               || (running.from[$0] == running.destination[$0] && running.velocity[$0] == 0) }) {
            var from = running.from
            for index in destination.indices where running.destination[index] != destination[index] {
                from[index] = destination[index]
            }
            let moved = RunningAnimation(from: from, destination: destination,
                                         velocity: running.velocity, animation: running.animation,
                                         began: running.began)
            let standing = Self.rect(moved.position(at: now()).value)
            animator.start(moved, for: key)
            seats[mount]?.standing = standing
            view.travels(to: target)
            view.placedFrame = standing
            return
        }

        let from = seat.standing ?? view.placedFrame
        // A scroll anchor changes the viewport origin, not the row's layout destination.
        // Compensate the sampled presentation and bend toward the newly computed place.
        // A measurement-only pass keeps the running law and sampled velocity.
        let correctingAnchor = anchorOffset != .zero && running != nil
            && !arrangement.framesRead && !reducesMotion()
        var lanes = arrangement.lanes
        var law = arrangement.law
        if correctingAnchor, lanes.isEmpty, let running {
            law = running.animation
            for (index, lane) in Self.order.enumerated()
                where running.from[index] != running.destination[index] || running.velocity[index] != 0 {
                lanes.insert(lane)
            }
            if anchorOffset.x != 0 { lanes.insert(.x) }
            if anchorOffset.y != 0 { lanes.insert(.y) }
        }
        lanes.subtract(stated)

        guard !lanes.isEmpty, Self.isReal(from), Self.isReal(target) else {
            arrive(view, at: target, mount: mount)
            return
        }

        // A running animation bends from where it has reached, at the speed it has.
        let position = running?.position(at: now())
        var start = position?.value ?? Self.lanes(from)
        var velocity = position?.velocity ?? [0, 0, 0, 0]
        start[0] += anchorOffset.x
        start[1] += anchorOffset.y

        for (index, lane) in Self.order.enumerated() where !lanes.contains(lane) {
            start[index] = destination[index]
            velocity[index] = 0
        }

        let animation = RunningAnimation(from: start, destination: destination, velocity: velocity, animation: law, began: now())

        guard !animation.arrives else {
            arrive(view, at: target, mount: mount)
            return
        }

        let standing = Self.rect(start)
        animator.start(animation, for: key)
        seats[mount]?.standing = standing
        view.travels(to: target)
        view.placedFrame = standing
        onStart()
    }

    /// Stands each animating child where the animator put it.
    public func follow(_ steps: [AnimationStep]) {
        for step in steps {
            guard case .placed(let mount) = step.target else { continue }

            let standing = Self.rect(step.value)
            seats[mount]?.standing = step.rested ? nil : standing
            if step.rested { seats[mount]?.view?.travels(to: nil) }
            seats[mount]?.view?.placedFrame = standing
        }
    }

    /// Translates the coordinate system itself. Existing animation starts and destinations
    /// move together, preserving elapsed time. Scroll anchors instead use `place`'s offset.
    public func shift(mounts: [UInt64], by offset: Point) {
        guard offset != .zero else { return }
        for mount in mounts {
            guard let seat = seats[mount], let view = seat.view else { continue }
            var frame = seat.standing ?? view.placedFrame
            frame.x += offset.x
            frame.y += offset.y
            let key = AnimationTarget.placed(mount)
            if let running = animator.animation(for: key) {
                var start = running.from
                var destination = running.destination
                start[0] += offset.x
                start[1] += offset.y
                destination[0] += offset.x
                destination[1] += offset.y
                animator.start(RunningAnimation(from: start, destination: destination,
                                                velocity: running.velocity, animation: running.animation,
                                                began: running.began), for: key)
                seats[mount]?.standing = frame
                view.travels(to: Self.rect(destination))
            }
            view.placedFrame = frame
        }
    }

    /// Forgets the place of an element that leaves the tree.
    public func remove(mount: UInt64) {
        seats[mount] = nil
        animator.halt(.placed(mount))
    }

    private func arrive(_ view: any PlacedView, at target: Rect, mount: UInt64) {
        animator.halt(.placed(mount))
        seats[mount]?.standing = nil
        view.travels(to: nil)
        view.placedFrame = target
    }

    /// Whether a timing animates anything: neither a snap nor an engine's own.
    private static func moves(_ animation: Animation) -> Bool {
        !animation.isInherited && !animation.isCustom && animation.factor.isFinite
            && !(animation.law == .eased && animation.millis == 0)
    }

    private static func isReal(_ rect: Rect) -> Bool {
        rect.width > 0 && rect.height > 0
    }

    /// A place's lanes in animation order: across, down, wide, tall.
    private static let order: [AnimationLanes] = [.x, .y, .width, .height]

    private static func lanes(_ rect: Rect) -> [Double] {
        [rect.x, rect.y, rect.width, rect.height]
    }

    private static func rect(_ lanes: [Double]) -> Rect {
        Rect(x: lanes[0], y: lanes[1], width: lanes[2], height: lanes[3])
    }
}
