// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// A scene's windows: its main window, and the groups of windows it may open
/// beside it.
///
///     Windows {
///         WindowGroup(.fonts) { FontsWindow() }
///     } main: {
///         if loading { LoadingWindow() } else { MainWindow() }
///     }
///
/// The main window is the scene on screen: it opens with the scene, and the
/// user closing it ends the scene and every window of its groups. It is one
/// window whatever type it is written as - the `if` above changes what that
/// window shows.
public struct Windows {
    /// The kinds of window the scene may open beside its main one.
    var groups: [WindowGroup]

    /// The main window, or nil where the scene is only groups - its windows
    /// open as `openWindow` asks, none of its own.
    let main: WindowScene?

    /// The main window's policies; named windows keep their own on their groups.
    var launchBehavior: SceneLaunchBehavior = .automatic
    var restorationBehavior: SceneRestorationBehavior = .automatic

    /// What `.environment(_:)` offered every window of the scene.
    var environments: [(key: ObjectIdentifier, object: AnyObject)] = []

    /// What `.environment(_:_:)` wrote every window of the scene, applied to
    /// each window's environment values as it builds.
    var environmentEdits: [(inout EnvironmentValues) -> Void] = []

    /// The commands every window of the scene offers - `.commands` on the
    /// scene and on its `Windows` collect them here.
    var commands: [any Commands] = []

    /// The size the scene's windows open at, in device units; nil for the
    /// platform's own.
    var defaultSize: (width: Double, height: Double)? = nil

    /// Where the scene's windows open on the screen, the anchor landing the
    /// same way on window and work area; nil for the platform's own choice.
    var defaultPosition: UnitPoint? = nil

    /// How the scene's windows settle their size against their content; nil
    /// for the platform's ordinary sizing.
    var resizability: WindowResizability? = nil

    /// A main window, and the groups of windows the scene may open beside it.
    ///
    /// - Parameters:
    ///   - groups: one `WindowGroup` per kind of window, and an `if` for a kind
    ///     only some scenes declare.
    ///   - main: the main window - an `if` choosing between two is allowed,
    ///     and swaps what the one window shows.
    public init(
        @WindowGroupBuilder _ groups: () -> [WindowGroup],
        @WindowBuilder main: () -> WindowScene
    ) {
        self.groups = groups()
        self.main = main()
    }

    /// A main window and nothing to open beside it.
    ///
    /// - Parameter main: the main window.
    public init(@WindowBuilder main: () -> WindowScene) {
        self.init({}, main: main)
    }

    /// The groups of windows the scene may open, and no main window - what a
    /// `WindowGroup` alone in a scene's body declares.
    ///
    /// - Parameter groups: one `WindowGroup` per kind of window.
    public init(@WindowGroupBuilder _ groups: () -> [WindowGroup]) {
        self.groups = groups()
        main = nil
    }

    /// Groups and a main window already built - what merging several scenes
    /// into one writes.
    @MainActor init(groups: [WindowGroup], main: WindowScene?) {
        self.groups = groups
        self.main = main
    }

    /// Offers an object to every window of the scene, resolved by type the way
    /// `.environment` on a view is - how a session's windows share one context:
    ///
    ///     @State private var nav = Navigation()
    ///
    ///     var windows: Windows {
    ///         Windows { … } main: { MainWindow() }
    ///             .environment(nav)
    ///     }
    public func environment<Value: AnyObject>(_ object: Value) -> Windows {
        var copy = self
        copy.environments.append((key: ObjectIdentifier(Value.self), object: object))
        return copy
    }

    /// Writes an environment value into every window of the scene, resolved
    /// by key path the way `.environment(_:_:)` on a view is.
    public func environment<Value>(
        _ keyPath: WritableKeyPath<EnvironmentValues, Value>, _ value: Value
    ) -> Windows {
        var copy = self
        copy.environmentEdits.append { $0[keyPath: keyPath] = value }
        return copy
    }

    /// How the scene's windows settle their size against their content -
    /// `.contentSize` has each take the size its content asks for and no
    /// other:
    ///
    ///     Windows { … } main: { MainWindow() }
    ///         .windowResizability(.contentSize)
    ///
    /// The scene's default: its main window settles so, and so does the
    /// window of a group that does not say its own.
    public func windowResizability(_ resizability: WindowResizability) -> Windows {
        var copy = self
        copy.resizability = resizability
        return copy
    }

    /// Where the scene's windows open: `position`'s fractions across and
    /// down the screen's work area land the same fractions across and down
    /// the window - `.center` centers it, `.topLeading` its top left corner
    /// at the work area's.
    ///
    /// The scene's default: its main window opens there, and so does the
    /// window of a group that does not say its own.
    ///
    ///     Windows { … } main: { MainWindow() }
    ///         .defaultPosition(.center)
    public func defaultPosition(_ position: UnitPoint) -> Windows {
        var copy = self
        copy.defaultPosition = position
        return copy
    }

    /// Where the scene's windows open, the fractions outright.
    public func defaultPosition(x: Double, y: Double) -> Windows {
        defaultPosition(UnitPoint(x: x, y: y))
    }

    /// Where the scene's windows open and the size they open at, in one
    /// ask - a placement's anchor, and its size where it is not `.zero`.
    /// `.automatic` asks nothing at all.
    public func defaultPlacement(_ placement: WindowPlacement) -> Windows {
        var copy = self
        copy.defaultPosition = placement.anchor
        copy.defaultSize = placement.extent.map { (width: $0.width, height: $0.height) }
        return copy
    }

    /// The size the scene's windows open at, in device units - the scene's
    /// default, a group's own winning where it says one:
    ///
    ///     Windows { … } main: { MainWindow() }
    ///         .defaultSize(width: 1280, height: 800)
    ///
    /// The platform's own size stands where none is asked for, and a size
    /// the user later gives a window is its own.
    public func defaultSize(width: Double, height: Double) -> Windows {
        var copy = self
        copy.defaultSize = (width: width, height: height)
        return copy
    }

    /// The size the scene's windows open at, as one value.
    public func defaultSize(_ size: Size) -> Windows {
        defaultSize(width: size.width, height: size.height)
    }
}

/// A `Windows` value written where a scene is asked for: an app's `body` can
/// be built straight from its windows.
extension Windows: Scene {
    /// The scene of these windows: this value itself.
    public var windows: Windows { self }
}
