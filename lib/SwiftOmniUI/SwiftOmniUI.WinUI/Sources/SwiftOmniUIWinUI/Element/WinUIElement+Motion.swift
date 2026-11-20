// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// The element's part in its layout's animation: fading in as it joins, and a change of visibility crossed,
/// both by the host layer's rule.
/// Design: docs/design/host/animation.md#layout-animation
extension WinUIElement {
    /// Hands a travelling layout what its children travel under, and tells it a patch reached it.
    func configureLayoutMotion() {
        guard let layout = view as? WinUITravellingLayout else { return }

        // Keep this dependency in the regular layout flow. Scrollers and lazy
        // viewports allocate their own content, and overlays already use the
        // actual allocation for their decorations.
        switch layout {
        case is WinUIGridView, is WinUIStackView, is WinUIZStackView, is WinUICustomLayoutView:
            layout.usesPresentedRoom = element.isGeometryReader || element.children.contains { child in
                !child.isDeparting && child.bool(.isLayoutDecoration) != true
                    && (child.winUI.view as? WinUILayoutView)?.usesPresentedRoom == true
            }
        default:
            break
        }

        layout.places.layoutMotion = host?.runtime.layoutMotion
        layout.places.animation = element.animation
        layout.onConsumeTransition = { [weak element] in element?.consumePlacementTransition() }
        layout.keepArrivalMotion(element.animation)
        layout.places.framesRead = element.framesRead
        layout.places.patchArrived(departureStartedAt: element.departureStartedAt)
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
            (self?.layoutParent?.view as? WinUITravellingLayout)?.places.patchArrived()
            self?.layoutParent?.arrangeChildren()
        }
    }
}

extension WinUIView: FadingView {}
