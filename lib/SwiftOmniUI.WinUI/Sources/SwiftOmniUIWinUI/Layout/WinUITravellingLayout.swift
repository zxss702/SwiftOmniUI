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
    private var pendingPresentationFrame = false
    private struct GeometryDriver {
        weak var element: MountedElement?
        var properties: Set<Prop>
    }
    private var geometryDrivers: [UInt64: GeometryDriver] = [:]

    func followsPresentationFrame() { pendingPresentationFrame = true }

    /// Ownership lasts as long as the geometry channel, including content
    /// patches arriving between its frames. A one-frame marker cannot express
    /// that dependency and lets a second layout animation take over mid-flight.
    func followPresentation(of element: MountedElement, properties: Set<Prop>) {
        guard !properties.isEmpty else { return }
        let previous = geometryDrivers[element.mount]?.properties ?? []
        geometryDrivers[element.mount] = GeometryDriver(element: element, properties: previous.union(properties))
        pendingPresentationFrame = true
    }

    func takePresentationFrame() -> Bool {
        defer { pendingPresentationFrame = false }
        var active = false
        for (mount, driver) in geometryDrivers {
            guard let element = driver.element, let animator = element.winUI.host?.runtime.animator else {
                geometryDrivers[mount] = nil
                continue
            }
            let properties = driver.properties.filter { property in
                if let binding = element.driven[property], binding.mode != .in {
                    return animator.animation(for: .state(binding.state)) != nil
                }
                return animator.animation(for: .described(DescribedKey(mount: mount, property: property))) != nil
            }
            if properties.isEmpty { geometryDrivers[mount] = nil }
            else {
                geometryDrivers[mount] = GeometryDriver(element: element, properties: properties)
                active = true
            }
        }
        return pendingPresentationFrame || active
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

    func beginArrangement(in bounds: Rect) {
        if let motion = takeArrivalMotion() { places.animation = motion }
        // Native layout may refine a patch more than once. Only the patch starts
        // a new motion; another arrangement preserves the motion already running.
        places.begin(width: bounds.width, refining: true, height: bounds.height,
                     followingPresentation: takePresentationFrame())
    }

    /// Stands `item` at `place`, or on its way there.
    func place(_ item: WinUILayoutItem, at place: Rect) {
        places.place(item.view, mount: item.mount, at: place, values: item.values, fadeIn: item.fadeIn)
    }
}
