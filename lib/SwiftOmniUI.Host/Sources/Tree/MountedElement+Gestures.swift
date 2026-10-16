// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore

/// What the user does to an element's view with a finger, a pen or the mouse, as the element's events - the same
/// on every host.
/// Design: docs/design/host/runtime.md#what-the-user-does-with-a-finger
extension MountedElement {
    /// What the element's handlers and channels ask to hear: taps, the pointer, a press dragged, a pinch. A pan asks
    /// for a press dragged by one pointer; one asking for more is not recognized.
    public var hearing: Hearing {
        var hearing: Hearing = []
        if handler(.tapGesture) != nil { hearing.insert(.taps) }
        if Self.pointerEvents.contains(where: { handler($0) != nil }) { hearing.insert(.pointer) }
        let drags = handler(.panUpdated) != nil || handler(.swiped) != nil
            || channel(.panXChannel) != nil || channel(.panYChannel) != nil
        if drags, (number(.panTouchCount) ?? 1) == 1 { hearing.insert(.drags) }
        if handler(.pinchUpdated) != nil { hearing.insert(.pinches) }
        return hearing
    }

    /// The user's input the view heard, as the element's events: a tap each time a run reaches the count asked
    /// for - at once for a press assistive technology made; the pointer where it is; a press dragged moving the
    /// states it carries, a swipe as it ends far enough; a pinch's step.
    public func hear(_ input: HeardInput, in runtime: HostRuntime) {
        if case .pointer(.pointerExited, _) = input {
            // Clear a hover that began before the scope became disabled.
        } else if !isEnabled { return }
        switch input {
        case .tap(let run):
            let count = max(1, Int(number(.tapCount) ?? 1))
            if run == 0 || run % count == 0 { send(.tapGesture, [], in: runtime) }
        case .pointer(let event, let point):
            let said: [HostValue] = event == .pointerEntered || event == .pointerExited ? [] : [.numbers([point.x, point.y])]
            send(event, said, in: runtime)
        case .drag(let phase, let x, let y, let at, let from):
            dragged(phase, x: x, y: y, at: at, from: from, in: runtime)
        case .pinch(let phase, let scale, let at):
            send(.pinchUpdated, [.enumeration(phase.rawValue), .number(scale), .numbers([at.x, at.y])], in: runtime)
        }
    }

    private static let pointerEvents: [Event] = [
        .pointerEntered, .pointerExited, .pointerMoved, .pointerPressed, .pointerReleased,
    ]

    /// The state a press dragged carries along an axis, where one does.
    private func channel(_ property: Prop) -> Int32? {
        number(property).flatMap { $0 == 0 ? nil : Int32($0) }
    }

    /// A press dragged moves the states it carries by how far it has come, from where they stood as it began, and
    /// says so, in one of the user's transactions; ended, it is a swipe where it went far enough.
    private func dragged(_ phase: GesturePhase, x: Double, y: Double, at: Point, from: Point, in runtime: HostRuntime) {
        let across = channel(.panXChannel)
        let down = channel(.panYChannel)
        if phase == .started {
            dragStart = Point(
                x: across.flatMap(runtime.standingGestureValue(state:)) ?? 0,
                y: down.flatMap(runtime.standingGestureValue(state:)) ?? 0)
        }
        runtime.performUserTransaction {
            if phase == .running {
                if let across { runtime.takeGestureValue(dragStart.x + x, state: across) }
                if let down { runtime.takeGestureValue(dragStart.y + y, state: down) }
            }
            send(
                .panUpdated,
                [
                    .enumeration(phase.rawValue), .number(x), .number(y),
                    .numbers([from.x, from.y]), .numbers([at.x, at.y]),
                ],
                in: runtime)
        }

        guard phase == .completed, handler(.swiped) != nil else { return }
        let listening = SwipeDirection(rawValue: value(.swipeDirection)?.enumeration ?? SwipeDirection.all.rawValue)
        if let direction = SwipeDirection.swiped(x: x, y: y, listening: listening, threshold: number(.swipeThreshold) ?? 40) {
            send(.swiped, [.enumeration(direction.rawValue)], in: runtime)
        }
    }
}
