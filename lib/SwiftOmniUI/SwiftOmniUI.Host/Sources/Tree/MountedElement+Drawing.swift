// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore

/// How an element's view is drawn over where its layout put it, the same on every host.
/// Design: docs/design/host/tree.md#drawn-over-its-place
extension MountedElement {
    /// The properties that move, turn and scale the view where its layout put it.
    public static let transformProperties: Set<Prop> = [
        .translationX, .translationY, .rotation, .rotationX, .rotationY, .scale, .scaleX, .scaleY, .pivotX, .pivotY,
    ]

    /// How the view is moved, turned and scaled: `scale` multiplies both axes on top of `scaleX` and `scaleY`, and
    /// it turns about its middle where the tree says no pivot.
    public var drawingTransform: HostDrawingTransform {
        let hasDriven = !driven.isEmpty
        let tree = self.tree
        let hasMotion = tree?.hasPropertyMotions(on: mount) == true

        @inline(__always)
        func read(_ property: Prop) -> Double? {
            if hasDriven, let binding = driven[property], binding.mode != .in {
                return resolvedValue(property)?.number
            }
            if hasMotion, let presented = tree?.presentedPropertyNumberUnchecked(mount: mount, property: property) {
                return presented
            }
            return properties[property]?.number
        }

        let scale = read(.scale) ?? 1
        let fallbackPivot = hasMotion ? activeTransitionPivot : nil
        return HostDrawingTransform(
            translationX: read(.translationX) ?? 0,
            translationY: read(.translationY) ?? 0,
            rotation: read(.rotation) ?? 0,
            rotationX: read(.rotationX) ?? 0,
            rotationY: read(.rotationY) ?? 0,
            scaleX: scale * (read(.scaleX) ?? 1),
            scaleY: scale * (read(.scaleY) ?? 1),
            pivotX: read(.pivotX) ?? fallbackPivot?.x ?? 0.5,
            pivotY: read(.pivotY) ?? fallbackPivot?.y ?? 0.5)
    }

    /// The layout's own placing run, where a state drives one: it moves the children without changing what the
    /// layout measures.
    public var ownPlacementRun: Set<Prop> {
        driven[.area]?.kind == .placement ? [.area] : []
    }

    /// The places an engine gives the layout's children, one each; nil while no state drives them.
    public var placement: HostPlacementRun? {
        guard !ownPlacementRun.isEmpty, let carried = carriedValue(.area) else { return nil }
        return HostBoundary.placements(from: carried)
    }
}
