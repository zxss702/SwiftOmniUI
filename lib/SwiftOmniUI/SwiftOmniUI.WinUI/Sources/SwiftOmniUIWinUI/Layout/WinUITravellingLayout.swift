// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// A layout whose children travel to their places by the host layer's rule (`TravellingPlaces`).
/// Design: docs/design/host/animation.md#layout-animation
@MainActor
class WinUITravellingLayout: WinUILayoutView {
    /// Where the children travel to their places.
    let places = TravellingPlaces()

    /// The motion the last patch that named one brought, kept until an arrangement spends it.
    ///
    /// A run that holds its children by a window realizes the rows of a data change in a later
    /// patch, and that patch tells the element nothing of the timing the change arrived under.
    /// The arrangement that can place those rows is the one that must spend it, so it stands
    /// here in between.
    private var arrivalMotion: HostLayoutMotion?
    var onConsumeTransition: (() -> Void)?
    private var pendingPresentationFrame = false
    private var pendingPresentedLanes: AnimationLanes = []
    private var pendingPresentedItems: [UInt64: AnimationLanes] = [:]

    func followsPresentationFrame(lanes: AnimationLanes = [], sample: Bool = true, item: UInt64? = nil) {
        pendingPresentationFrame = pendingPresentationFrame || sample
        if let item { pendingPresentedItems[item, default: []].formUnion(lanes) }
        else { pendingPresentedLanes.formUnion(lanes) }
    }

    func takePresentedItems() -> [UInt64: AnimationLanes] {
        defer { pendingPresentedItems.removeAll(keepingCapacity: true) }
        return pendingPresentedItems
    }

    func takePresentedLanes() -> AnimationLanes {
        defer { pendingPresentedLanes = [] }
        return pendingPresentedLanes
    }

    func takePresentationFrame() -> Bool {
        defer { pendingPresentationFrame = false }
        isArrangingPresentation = WinUIView.allocatingNativeRoom == 0
            && (pendingPresentationFrame || isSamplingAllocatedRoom || receivesPresentedRoom
                || placingLayout?.isArrangingPresentation == true)
        return isArrangingPresentation
    }

    /// Keeps the motion a patch named. A patch that names none leaves the last one standing:
    /// the arrangement that will place the change is the one that spends it.
    func keepArrivalMotion(_ motion: HostLayoutMotion?) {
        if let motion { arrivalMotion = motion }
    }

    /// Takes the kept motion, whether or not the caller takes it up: the arrangement now under
    /// way is the last chance to spend it.
    func takeArrivalMotion() -> HostLayoutMotion? {
        defer { arrivalMotion = nil }
        return arrivalMotion
    }

    override var shouldArrangeInDestinationRoom: Bool {
        places.willAnimate(arrivalMotion: arrivalMotion)
            || items.contains { !$0.departing && $0.mount != 0 && (places.layoutMotion?.isTravelling(mount: $0.mount) ?? false) }
    }

    func beginArrangement(in bounds: Rect) {
        onConsumeTransition?()
        if let motion = takeArrivalMotion() { places.animation = motion }
        let followsViewport = receivesPresentedRoom
        // Native layout may refine a patch more than once. Only the patch starts
        // a new motion; another arrangement preserves the motion already running.
        places.begin(width: bounds.width, animating: !followsViewport, refining: true, height: bounds.height,
                     followingPresentation: takePresentationFrame(), presentedLanes: takePresentedLanes(),
                     presentedItems: takePresentedItems(), inheritedStart: inheritedArrangementStart)
    }

    private var inheritedArrangementStart: Double? {
        guard let parent = placingLayout as? WinUITravellingLayout, parent.isNativeArranging else { return nil }
        return parent.places.arrangementStartedAt ?? parent.inheritedArrangementStart
    }

    /// Stands `item` at `place`, or on its way there.
    func place(_ item: WinUILayoutItem, at place: Rect, arrivedFrom: Rect? = nil) {
        var resolvedOrigin = arrivedFrom
        if resolvedOrigin == nil, let key = item.matchedGeometry,
           let layoutMotion = places.layoutMotion, !layoutMotion.hasSeat(for: item.mount),
           let source = layoutMotion.matchedGeometrySource(for: key) {
            let sourceFrame = source.frame
            let containerOrigin = self.origin
            resolvedOrigin = Rect(
                x: sourceFrame.x - containerOrigin.x,
                y: sourceFrame.y - containerOrigin.y,
                width: sourceFrame.width,
                height: sourceFrame.height)
            WinUIDoorbell.afterPass { [weak layoutMotion] in
                layoutMotion?.clearMatchedGeometrySource(for: key, serial: source.serial)
            }
        }
        places.place(item.view, mount: item.mount, at: place, values: item.values,
                     fadeIn: item.fadeIn, arrivedFrom: resolvedOrigin)
    }
}
