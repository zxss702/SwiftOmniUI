// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore

/// A native view whose showing and opacity the host layer's visibility rule moves.
@_spi(Host) @MainActor public protocol FadingView: AnyObject {
    /// Whether the view is shown.
    var isShown: Bool { get }

    /// The opacity the view stands at.
    var opacity: Double { get }

    /// Shows or hides the view.
    func setShown(_ shown: Bool)

    /// Stands the view at `opacity`.
    func setOpacity(_ opacity: Double)
}

/// An element's showing, the same on every host: fading in as it joins a standing layout, and a change of its
/// visibility crossed - out, fading and then hidden; back from where it stands; in from nothing.
/// Design: docs/design/host/animation.md#showing-and-hiding
extension MountedElement {
    /// Whether the element stands shown: as the tree says, or while it fades
    /// out, or while it rides its removal transition.
    public var standsShown: Bool {
        isLeaving || isDeparting || value(.isVisible)?.bool != false
    }

    /// Whether the element fades in as it joins a standing layout: it was described
    /// with a transition, or its view `presentsOpacity` and no state owns it.
    public func fadesIn(presentsOpacity: Bool) -> Bool {
        transition != nil || (presentsOpacity && driven[.opacity] == nil)
    }

    /// Fades the element in on `view` as it joins a layout already standing, under `animation`; an opacity already on its
    /// way keeps its animation.
    public func fadeIn(_ view: some FadingView, under animation: Animation) {
        guard let tree, tree.presentedPropertyValue(mount: mount, property: .opacity) == nil else { return }

        tree.receiveProperty(
            mount: mount, property: .opacity, standing: .number(0), target: resolvedValue(.opacity) ?? .number(1),
            animation: animation)
        view.setOpacity(value(.opacity)?.number ?? 1)
    }

    /// Crosses a change of visibility on `view`, already shown, under the element's own animation or the application's:
    /// hidden, it fades out and then hides, and `closed` lets its layout close over it; shown again as it fades, it
    /// comes back from where it stands; shown from nothing, it fades in. Where nothing moves, nothing crosses.
    public func crossVisibility<View: FadingView>(_ view: View, closed: @escaping () -> Void) {
        guard let tree else { return }

        let law = tree.layoutMotion.law(of: animation)
        let opacity = resolvedValue(.opacity) ?? .number(1)
        if value(.isVisible)?.bool == false {
            guard view.isShown, !isLeaving, let law else { return }
            isLeaving = true
            let started = tree.receiveProperty(
                mount: mount, property: .opacity, standing: .number(view.opacity), target: .number(0), animation: law,
                landed: { [weak self, weak view] in
                    guard let self, let view else { return }
                    self.crossed(view, closed: closed)
                })
            if !started { isLeaving = false }
        } else if isLeaving {
            isLeaving = false
            tree.receiveProperty(
                mount: mount, property: .opacity, standing: .number(view.opacity), target: opacity, animation: law)
        } else if !view.isShown, let law {
            tree.receiveProperty(mount: mount, property: .opacity, standing: .number(0), target: opacity, animation: law)
            view.setOpacity(value(.opacity)?.number ?? 1)
        }
    }

    /// The fade out ended, landed or cut short: the view goes, and its layout closes over it.
    private func crossed(_ view: some FadingView, closed: () -> Void) {
        guard isLeaving else { return }

        isLeaving = false
        view.setShown(standsShown)
        view.setOpacity(value(.opacity)?.number ?? 1)
        closed()
    }
}

// MARK: - Transitions

extension MountedElement {
    /// The transition the element was described with; nil for none.
    public var transition: AnyTransition? {
        resolvedValue(.transition).flatMap(AnyTransition.init(propValue:))
    }

    /// Fades the element in as it joins a layout already standing - the
    /// transition it was described with where it has one, the plain opacity
    /// crossing where it has not; `room` is the place the layout gave it, which
    /// a `move` measures its slide by.
    public func fadeIn(_ view: some FadingView, room: Rect? = nil, under animation: Animation) {
        guard let transition else { fadeIn(view, under: animation); return }
        guard let tree else { return }

        let law = transition.animation ?? animation
        for (property, standing) in phaseValues(transition.insertion, room: room) {
            _ = tree.receiveProperty(
                mount: mount, property: property, standing: standing,
                target: resolvedValue(property) ?? resting(of: property), animation: law)
        }
    }

    /// Begins the removal transition if one is described and anything animates:
    /// the element stays mounted and shown while it goes, and `leave()`s itself
    /// - `closed` lets the parent drop its view - as the last component lands.
    /// Answers whether it goes by transition (else it should leave at once).
    ///
    /// `room` is the place its view last stood at, which a `move` measures by.
    public func depart(room: Rect?, closed: @escaping () -> Void) -> Bool {
        guard !isDeparting, let tree, let transition else { return false }
        let components = phaseValues(transition.removal, room: room)
        guard !components.isEmpty,
              let law = transition.animation ?? tree.layoutMotion.law(of: animation)
        else { return false }

        isDeparting = true
        native.departureChanged()
        departureSerial += 1
        let serial = departureSerial
        var pending = components.count
        for (property, target) in components {
            let started = tree.receiveProperty(
                mount: mount, property: property,
                standing: value(property) ?? resting(of: property),
                target: target, animation: law, retainingTarget: true) { [weak self] in
                    pending -= 1
                    // A departure a patch turned around - or another since -
                    // lands its components anyway; only this one's last lets
                    // the element go.
                    guard pending == 0, let self,
                          self.isDeparting, self.departureSerial == serial
                    else { return }
                    self.isDeparting = false
                    self.leave()
                    closed()
                }
            if !started { pending -= 1 }
        }
        if pending == 0 {
            isDeparting = false
            native.departureChanged()
            return false
        }
        return true
    }

    /// A departure reversed mid-flight: a patch described the element again.
    /// Each removal component rides back to the value the tree says.
    func revive() {
        guard isDeparting, let transition else { return }
        isDeparting = false

        guard let tree else { return }
        native.departureChanged()
        let law = transition.animation ?? tree.layoutMotion.law(of: animation) ?? .standard
        for (property, _) in phaseValues(transition.removal, room: nil) {
            _ = tree.receiveProperty(
                mount: mount, property: property, standing: value(property),
                target: resolvedValue(property) ?? resting(of: property), animation: law)
        }
    }

    /// The values a phase's components stand at, by property - a component the
    /// element already drives stays the state's.
    private func phaseValues(_ phase: AnyTransition.Phase, room: Rect?) -> [(Prop, HostValue)] {
        var values: [(Prop, HostValue)] = []
        var offset = phase.offset ?? Point(0, 0)
        if let move = phase.move {
            let across = room?.width ?? 0, down = room?.height ?? 0
            switch move {
            case .leading: offset = Point(offset.x - across, offset.y)
            case .trailing: offset = Point(offset.x + across, offset.y)
            case .top: offset = Point(offset.x, offset.y - down)
            case .bottom: offset = Point(offset.x, offset.y + down)
            }
        }

        if let opacity = phase.opacity, driven[.opacity] == nil {
            values.append((.opacity, .number(opacity)))
        }
        if phase.offset != nil || phase.move != nil {
            if driven[.translationX] == nil { values.append((.translationX, .number(offset.x))) }
            if driven[.translationY] == nil { values.append((.translationY, .number(offset.y))) }
        }
        if let scaleX = phase.scaleX, driven[.scaleX] == nil { values.append((.scaleX, .number(scaleX))) }
        if let scaleY = phase.scaleY, driven[.scaleY] == nil { values.append((.scaleY, .number(scaleY))) }
        if let pivot = phase.pivot {
            values.append((.pivotX, .number(pivot.x)))
            values.append((.pivotY, .number(pivot.y)))
        }
        if let blur = phase.blur, driven[.blur] == nil { values.append((.blur, .number(blur))) }
        // A transition only waits for components the native half presents.
        // Unsupported effects must not run an invisible animation or keep a
        // departed branch alive after its visible components finished.
        return values.filter { native.animates($0.0) }
    }

    /// The value a transition property rests at where the element says none.
    private func resting(of property: Prop) -> HostValue {
        switch property {
        case .opacity, .scaleX, .scaleY: .number(1)
        case .pivotX, .pivotY: .number(0.5)
        default: .number(0)
        }
    }
}
