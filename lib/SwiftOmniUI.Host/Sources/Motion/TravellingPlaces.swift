// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore

/// One layout's children travelling to their places, the same on every host: as an arrangement begins, it decides
/// once for every child whether the places a patch or a new width gave them animate, and each child then stands at
/// its place or on its way there.
/// Design: docs/design/host/animation.md#layout-animation
@_spi(Host) @MainActor public final class TravellingPlaces {
    /// Where the children's places animate; nil places them at once.
    public weak var layoutMotion: LayoutMotion?

    /// The layout's own animation, as its patches said it; nil while it says nothing of its own.
    public var animation: HostLayoutMotion?

    /// Whether this layout's frame, or any frame under it, is read.
    public var framesRead = false

    /// Whether a patch reached the layout since its last arrangement.
    private var patched = false

    /// The width of the last arrangement; nil before the first.
    private var arrangedWidth: Double?
    private var arrangedHeight: Double?

    private var arrangement = Arrangement()
    private var presentedItems: [UInt64: AnimationLanes] = [:]
    private var commitsArrangement = true
    private var anchorOffset = Point.zero

    /// A layout not arranged yet.
    public init() {}

    /// Notes that a patch reached the layout: its next arrangement places what the patch changed.
    public func patchArrived() {
        patched = true
    }

    /// Starts an arrangement `width` wide, deciding once for every child how it is placed: what a patch said
    /// travels, what a new width gave arrives - as does everything while a frame under it is read.
    /// `anchorOffset` compensates a changed viewport origin without moving any layout destination.
    /// An unfinished layout places native views without consuming its patch or registering animation seats.
    public func begin(width: Double, animating: Bool = true, anchorOffset: Point = .zero, refining: Bool = false,
                      consumingPatch: Bool = true, height: Double? = nil, followingPresentation: Bool = false,
                      presentedLanes: AnimationLanes = [], presentedItems: [UInt64: AnimationLanes] = [:]) {
        let said = consumingPatch && patched && arrangedWidth != nil
        commitsArrangement = consumingPatch
        let resized = (arrangedWidth.map { abs($0 - width) > 0.5 } ?? false)
            || (height.flatMap { height in arrangedHeight.map { abs($0 - height) > 0.5 } } ?? false)
        if consumingPatch {
            patched = false
            arrangedWidth = width
            arrangedHeight = height
        }
        self.anchorOffset = resized || framesRead ? .zero : anchorOffset
        self.presentedItems = presentedItems

        arrangement = layoutMotion?.arrangement(
            said: said && animating, resized: resized, animation: animation, framesRead: framesRead) ?? Arrangement()
        // Described geometry owns only the axes that depend on it. The same
        // business patch can still animate unrelated layout lanes and fades.
        arrangement.lanes.subtract(presentedLanes)
        arrangement.refines = refining && !(said && animating) && !resized && !framesRead && presentedLanes.isEmpty
        // A business patch can move other children independently of a
        // described geometry channel. Only its subsequent samples translate
        // those journeys without starting a second animation.
        arrangement.followsPresentation = followingPresentation && !said
    }

    /// Stands `view`, the mounted element `mount`'s, at `place`, or on its way there; its `values` say which sides
    /// it sizes itself, and `fadeIn` fades it in as it joins a standing layout.
    public func place(
        _ view: any PlacedView, mount: UInt64, at place: Rect, values: LayoutValues,
        fadeIn: ((Animation, Rect) -> Void)?,
        arrivedFrom: Rect? = nil
    ) {
        guard commitsArrangement, let layoutMotion else {
            view.placedFrame = place
            return
        }

        var stated: AnimationLanes = []
        if values.width != nil { stated.insert(.width) }
        if values.height != nil { stated.insert(.height) }
        var placement = arrangement
        let presented = presentedItems[mount] ?? []
        placement.lanes.subtract(presented)
        placement.refines = placement.refines && presented.isEmpty
        layoutMotion.place(view, mount: mount, at: place, stated: stated,
                           fadeIn: fadeIn, arrivedFrom: arrivedFrom,
                           anchorOffset: anchorOffset, in: placement)
    }
}
