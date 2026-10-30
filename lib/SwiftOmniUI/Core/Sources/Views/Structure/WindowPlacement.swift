// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// Where a window opens on the screen and the size it opens at - what
/// `.defaultPlacement` carries onto a scene, its `Windows`, or a
/// `WindowGroup`:
///
///     Windows { … } main: { MainWindow() }
///         .defaultPlacement(WindowPlacement(position: .topLeading, size: Size(400, 300)))
///
/// `position`'s fractions across and down the screen's work area land the
/// same fractions across and down the window: `.center` puts the window's
/// middle at the work area's middle, `.topLeading` its top left corner at
/// the work area's. A `.zero` `size` asks nothing of the size - the
/// platform's own stands - and `.automatic` asks nothing at all.
public struct WindowPlacement: Equatable, Sendable {
    /// Where the anchor lands: the fraction across and down the work area
    /// the same fraction across and down the window sits at.
    public var position: UnitPoint

    /// The size the window opens at, in device units; `.zero` for the
    /// platform's own.
    public var size: Size

    /// Whether it asks anything at all: `.automatic` leaves the place and
    /// the size to the platform, as never having asked does.
    var isAutomatic = false

    /// A placement: the window anchored as `position` names, `size` its size
    /// where it is not `.zero`.
    ///
    /// - Parameters:
    ///   - position: where the window's anchor lands on the work area.
    ///   - size: the size it opens at, in device units; `.zero` for the
    ///     platform's own.
    public init(position: UnitPoint = .center, size: Size = .zero) {
        self.position = position
        self.size = size
    }

    /// No ask at all: the platform's own place and size.
    public static var automatic: WindowPlacement {
        var placement = WindowPlacement()
        placement.isAutomatic = true
        return placement
    }

    /// The window's middle at the work area's middle.
    public static let center = WindowPlacement(position: .center)

    /// The middle of the window's top edge at the middle of the work area's.
    public static let top = WindowPlacement(position: .top)

    /// The middle of the window's bottom edge at the middle of the work
    /// area's.
    public static let bottom = WindowPlacement(position: .bottom)

    /// The middle of the window's left edge at the middle of the work
    /// area's.
    public static let leading = WindowPlacement(position: .leading)

    /// The middle of the window's right edge at the middle of the work
    /// area's.
    public static let trailing = WindowPlacement(position: .trailing)

    /// The window's top left corner at the work area's.
    public static let topLeading = WindowPlacement(position: .topLeading)

    /// The window's top right corner at the work area's.
    public static let topTrailing = WindowPlacement(position: .topTrailing)

    /// The window's bottom left corner at the work area's.
    public static let bottomLeading = WindowPlacement(position: .bottomLeading)

    /// The window's bottom right corner at the work area's.
    public static let bottomTrailing = WindowPlacement(position: .bottomTrailing)

    /// A placement by its anchor alone: `.center` centers the window, the
    /// size the platform's own.
    ///
    ///     WindowPlacement(.center)
    public init(_ position: UnitPoint) {
        self.init(position: position)
    }

    /// The position it asks, nil where it asks nothing of the place - what a
    /// window's `defaultPosition` becomes.
    var anchor: UnitPoint? { isAutomatic ? nil : position }

    /// The size it asks, nil for `.zero` or where it asks nothing - what a
    /// window's `defaultSize` becomes.
    var extent: Size? { !isAutomatic && size != .zero ? size : nil }
}

/// The content a window's placement is asked about - on SwiftUI the view
/// filling the window. A `windowIdealPlacement` closure is answered with
/// one of these so the same spelling compiles under SwiftOmniUI, where the
/// placement resolves once at scene build and the root view is not
/// consulted.
public struct WindowLayoutRoot: Sendable {
    /// The one content root a placement is asked about.
    public init() {}
}

/// The displays and windows a `windowIdealPlacement` closure may account
/// for. SwiftOmniUI's own resolution happens before any window stands, so
/// the context a closure is handed is empty; closures reading it ask the
/// placement questions this model does not pose.
public struct WindowPlacementContext: Sendable {
    /// The context at scene build: no displays, no windows beside.
    public init() {}
}
