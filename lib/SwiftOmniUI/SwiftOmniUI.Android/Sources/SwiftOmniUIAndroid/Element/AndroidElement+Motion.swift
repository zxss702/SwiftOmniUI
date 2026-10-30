// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// The element's part in its layout's animation: fading in as it joins, and a change of visibility crossed,
/// both by the host layer's rule.
/// Design: docs/design/platforms/android/animation.md#joining-and-leaving
extension AndroidElement {
    /// Hands a travelling layout what its children travel under, and tells it a patch reached it.
    func configureLayoutMotion() {
        guard let layout = view as? AndroidTravellingLayout else { return }

        layout.places.layoutMotion = host?.runtime.layoutMotion
        layout.places.animation = element.animation
        layout.places.framesRead = element.framesRead
        layout.places.patchArrived()
    }

    /// Whether the element fades in as it joins a standing layout, by the host layer's rule.
    var fadesIn: Bool {
        view != nil && element.fadesIn(presentsOpacity: TransitionSurface.presents(.opacity, on: type))
    }

    /// Fades the element in as it joins a layout already standing, by the host layer's rule; `room`
    /// is the place it lands at.
    func fadeIn(under animation: Animation, room: Rect) {
        guard fadesIn, let view else { return }
        element.fadeIn(view, room: room, under: animation)
    }

    /// The room its view last stood at, which a removal `move` measures by.
    var departingRoom: Rect? {
        view?.placedFrame
    }

    /// Crosses a change of visibility by the host layer's rule; as a fade out ends, the layout closes over it.
    func crossVisibility() {
        guard let view else { return }
        element.crossVisibility(view) { [weak self] in
            (self?.layoutParent?.view as? AndroidTravellingLayout)?.places.patchArrived()
            self?.layoutParent?.arrangeChildren()
        }
    }
}

extension AndroidView: FadingView {}
