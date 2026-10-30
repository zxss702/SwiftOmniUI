// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// A drag: a press moved past a distance, its phases reported as one value at a
// time - the SwiftUI spelling over the pan the host layer hears.
// Design: docs/design/types/gestures.md

/// What the user does with a finger on a view, kept simple for the one kind
/// SwiftOmniUI spells so far: a drag.
///
/// Attach one with `.gesture(_:)`:
///
///     ColorPicker(.cornflowerBlue)
///         .gesture(
///             DragGesture()
///                 .onChanged { value in offset = value.translation }
///                 .onEnded { _ in offset = .zero }
///         )
@preconcurrency @MainActor public protocol Gesture {}

/// A dragging motion - a press that has moved.
///
/// The gesture is reported through `.onChanged` and `.onEnded`, each handed a
/// `Value`: where the press began, where it is now, and how far it has come.
public struct DragGesture: Gesture {
    /// How far the press must move before the drag begins, in device units.
    public var minimumDistance: Double

    /// A drag beginning once the press has moved `minimumDistance`.
    public init(minimumDistance: Double = 10) {
        self.minimumDistance = minimumDistance
    }

    /// Where the drag stands at one report.
    public struct Value: Equatable, Sendable {
        /// Where the press went down, in the view's own coordinates.
        public var startLocation: Point

        /// Where the pointer is now, in the view's own coordinates.
        public var location: Point

        /// How far the pointer has moved since it went down: assigning it to a
        /// translation moves the view with the finger.
        public var translation: Size
    }

    /// Runs `action` each time the drag moves, once it has begun.
    public func onChanged(_ action: @escaping (DragGesture.Value) -> Void) -> ChangedDragGesture {
        ChangedDragGesture(minimumDistance: minimumDistance, changed: action)
    }

    /// Runs `action` as the drag ends, let go or taken away.
    public func onEnded(_ action: @escaping (DragGesture.Value) -> Void) -> ChangedDragGesture {
        ChangedDragGesture(minimumDistance: minimumDistance, ended: action)
    }
}

/// A drag with what runs as it moves and as it ends.
public struct ChangedDragGesture: Gesture {
    /// How far the press must move before the drag begins.
    var minimumDistance: Double

    /// What runs each time the drag moves, where one was named.
    var changed: ((DragGesture.Value) -> Void)?

    /// What runs as the drag ends, where one was named.
    var ended: ((DragGesture.Value) -> Void)?

    /// Runs `action` each time the drag moves, once it has begun.
    public func onChanged(_ action: @escaping (DragGesture.Value) -> Void) -> ChangedDragGesture {
        var copy = self
        copy.changed = action
        return copy
    }

    /// Runs `action` as the drag ends, let go or taken away.
    public func onEnded(_ action: @escaping (DragGesture.Value) -> Void) -> ChangedDragGesture {
        var copy = self
        copy.ended = action
        return copy
    }
}
