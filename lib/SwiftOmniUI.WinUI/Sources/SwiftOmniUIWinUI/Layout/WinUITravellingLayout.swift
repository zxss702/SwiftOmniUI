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

    func beginArrangement(width: Double) {
        if let motion = takeArrivalMotion() { places.animation = motion }
        // Native layout may refine a patch more than once. Only the patch starts
        // a new motion; another arrangement preserves the motion already running.
        places.begin(width: width, refining: true)
    }

    /// Stands `item` at `place`, or on its way there.
    func place(_ item: WinUILayoutItem, at place: Rect) {
        places.place(item.view, mount: item.mount, at: place, values: item.values, fadeIn: item.fadeIn)
    }
}
