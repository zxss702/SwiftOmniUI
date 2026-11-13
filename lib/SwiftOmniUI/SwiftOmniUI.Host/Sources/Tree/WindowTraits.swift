// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore

/// What a window's element says of the window it is, the same on every host: whether the user may maximize and
/// minimize it - nil where it says nothing, which leaves the toolkit's own - whether the desktop shows through it,
/// and whether it floats over the application's other windows now.
/// Design: docs/design/host/tree.md#a-windows-traits
@_spi(Host) public struct WindowTraits: Equatable, Sendable {
    /// Whether the user may maximize the window, where said.
    public var isMaximizable: Bool?

    /// Whether the user may minimize the window, where said.
    public var isMinimizable: Bool?

    /// Whether the desktop shows through the window.
    public var isTranslucent: Bool

    /// Whether the window floats over the application's other windows: it says so, and the application is in front.
    public var floatsOnTop: Bool

    /// Whether the window stands above every application's windows, whatever application is in front.
    public var alwaysOnTop: Bool

    /// Whether the user's presses pass through the window, and it never takes the keyboard's focus.
    public var ignoresMouseEvents: Bool

    /// Whether the window stays out of what the system captures.
    public var excludesFromCapture: Bool

    /// Whether the window is only its content: no frame of its own, no material under it.
    public var isTransparent: Bool

    /// How the window settles its size against its content, where said - `WindowResizability`'s number.
    public var resizability: Int32?

    /// What `window` says now, standing in `lifecycle`; a trait it leaves unsaid is false, but for the two the
    /// toolkit keeps.
    @MainActor public init(of window: MountedElement, in lifecycle: ApplicationLifecycle) {
        isMaximizable = window.value(.isMaximizable)?.bool
        isMinimizable = window.value(.isMinimizable)?.bool
        isTranslucent = window.value(.isTranslucent)?.bool == true
        floatsOnTop = lifecycle.floats(window)
        alwaysOnTop = window.value(.alwaysOnTop)?.bool == true
        ignoresMouseEvents = window.value(.ignoresMouseEvents)?.bool == true
        excludesFromCapture = window.value(.excludesFromCapture)?.bool == true
        isTransparent = window.value(.isTransparent)?.bool == true
        resizability = window.value(.resizability)?.enumeration
    }
}
