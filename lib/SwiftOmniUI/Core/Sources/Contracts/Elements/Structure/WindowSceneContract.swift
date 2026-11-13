// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// A window onto a page.
public enum WindowSceneContract: ElementContract {
    /// The node type the contract declares.
    public static let nodeType: NodeType = "WindowScene"

    /// It carries structure, not a platform control of its own.
    public static let layer: ElementLayer = .structure

    /// The window came to the front.
    public static let activated = ElementEvent<Self, Void>("activated", layer: .adaptive)

    /// The platform made the window.
    public static let created = ElementEvent<Self, Void>("created", layer: .adaptive)

    /// The window is showing behind another.
    public static let deactivated = ElementEvent<Self, Void>("deactivated", layer: .adaptive)

    /// The window is going.
    public static let destroying = ElementEvent<Self, Void>("destroying", layer: .adaptive)

    /// Whether the window stands above every application's windows, whatever
    /// application is in front.
    public static let alwaysOnTop = ElementProperty<Self, Bool>(
        "alwaysOnTop", layer: .adaptive, cleared: false)

    /// Whether the window stays out of what the system captures: a screenshot
    /// or recording sees through it to what stands behind.
    public static let excludesFromCapture = ElementProperty<Self, Bool>(
        "excludesFromCapture", layer: .adaptive, cleared: false)

    /// Whether the window floats above the application's other windows.
    public static let floatsOnTop = ElementProperty<Self, Bool>(
        "floatsOnTop", layer: .adaptive, cleared: false)

    /// How tall the window is, in device units.
    public static let height = ElementProperty<Self, Double>("height", layer: .native, moves: .height)

    /// Whether the window hides while another scene of the application is in
    /// front.
    public static let hidesWhenInactive = ElementProperty<Self, Bool>(
        "hidesWhenInactive", layer: .adaptive, cleared: false)

    /// Whether the user's presses pass through the window to what stands
    /// behind it, and the window never takes the keyboard's focus.
    public static let ignoresMouseEvents = ElementProperty<Self, Bool>(
        "ignoresMouseEvents", layer: .adaptive, cleared: false)

    /// Whether the user can make the window fill the screen.
    public static let isMaximizable = ElementProperty<Self, Bool>("isMaximizable", layer: .adaptive)

    /// Whether the user can put the window away.
    public static let isMinimizable = ElementProperty<Self, Bool>("isMinimizable", layer: .adaptive)

    /// Whether the window's material shows through it.
    public static let isTranslucent = ElementProperty<Self, Bool>("isTranslucent", layer: .adaptive)

    /// Whether the window is only its content: no frame of its own and no
    /// material under it - what its pages leave uncovered shows the desktop
    /// exactly, unblurred.
    public static let isTransparent = ElementProperty<Self, Bool>(
        "isTransparent", layer: .adaptive, cleared: false)

    /// The most height the window takes, in device units.
    public static let maximumHeight = ElementProperty<Self, Double>(
        "maximumHeight", layer: .native, moves: .height)

    /// The most width the window takes, in device units.
    public static let maximumWidth = ElementProperty<Self, Double>(
        "maximumWidth", layer: .native, moves: .width)

    /// The least height the window takes, in device units.
    public static let minimumHeight = ElementProperty<Self, Double>(
        "minimumHeight", layer: .native, moves: .height)

    /// The least width the window takes, in device units.
    public static let minimumWidth = ElementProperty<Self, Double>(
        "minimumWidth", layer: .native, moves: .width)

    /// A modal went without being told to, leaving this many presented.
    public static let modalPopped = ElementEvent<Self, Int>("modalPopped", layer: .adaptive)

    /// Where a new window's anchor lands on the screen's work area, the same
    /// anchor on the window - what a scene's `.defaultPosition` asks for.
    public static let defaultPosition = ElementProperty<Self, UnitPoint>(
        "defaultPosition", layer: .adaptive)

    /// How the window settles its size against its content - what a scene's
    /// `.windowResizability` asks for.
    public static let resizability = ElementProperty<Self, WindowResizability>(
        "resizability", layer: .adaptive)

    /// The window came back from out of sight.
    public static let resumed = ElementEvent<Self, Void>("resumed", layer: .adaptive)

    /// Where the window stands over the whole desktop, and how big it is
    /// there, in device pixels - counted from the desktop's own corner.
    ///
    ///     window.screenFrame = Rect(0, 0, 3840, 2160)
    ///
    /// What the four requests above cannot say: they count a place from the
    /// work area of the screen the window stands on, so they leave the
    /// system's own bars uncovered and reach no other screen, and they count
    /// in DIPs, which over a desktop of screens that differ are no one
    /// screen's. This asks for the desktop exactly as the platform counts it,
    /// and a window with no frame of its own is then the size it is placed
    /// at. `nil` leaves the window under those four.
    public static let screenFrame = ElementProperty<Self, Rect>("screenFrame", layer: .native)

    /// The window went out of sight.
    public static let stopped = ElementEvent<Self, Void>("stopped", layer: .adaptive)

    /// The window's title.
    public static let title = ElementProperty<Self, String>("title", layer: .native)

    /// How wide the window is, in device units.
    public static let width = ElementProperty<Self, Double>("width", layer: .native, moves: .width)

    /// What kind of window it is - the kind a scene declares it under.
    public static let windowType = ElementProperty<Self, WindowType>(
        "windowType", layer: .structure, cleared: false)

    /// The value a window of the kind was opened for, written down with it.
    public static let windowValue = ElementProperty<Self, String>(
        "windowValue", layer: .structure, cleared: false)

    /// Where the window stands across the screen, in device units.
    public static let x = ElementProperty<Self, Double>("x", layer: .structure)

    /// Where the window stands down the screen, in device units.
    public static let y = ElementProperty<Self, Double>("y", layer: .structure)

    /// Whether the host may keep this window for restoration on a later launch.
    public static let allowsRestoration = ElementProperty<Self, Bool>(
        "allowsRestoration", layer: .structure, cleared: true)

    /// The element's own members.
    public static let members: [any ContractMember] = [
        allowsRestoration, activated, alwaysOnTop, created, deactivated, destroying, excludesFromCapture, floatsOnTop,
        height, hidesWhenInactive, ignoresMouseEvents, isMaximizable,
        isMinimizable, isTranslucent, isTransparent, maximumHeight, maximumWidth, minimumHeight, minimumWidth, modalPopped,
        resizability, resumed, screenFrame, stopped, title, width, windowType, windowValue, x, y, defaultPosition,
    ]
}
