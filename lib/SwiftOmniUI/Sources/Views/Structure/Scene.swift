// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// How an application is laid out in windows.
// Design: docs/design/views/pages.md#scenes

/// One session of the application: its main window, the windows it opens
/// beside it, and the state they share.
///
///     struct EditorScene: Scene {
///         @State private var document = Document()
///
///         var windows: Windows {
///             Windows {
///                 WindowGroup(.fonts) { FontsWindow() }
///             } main: {
///                 EditorWindow()
///             }
///             .environment(document)
///         }
///     }
///
/// A window is a scene of one window - what an application with nothing to
/// open beside it writes: `var body: some Scene { MainWindow() }`.
///
/// A scene holds `@State` once per session: a second *File ▸ New WindowScene* is a
/// second instance with state of its own. What every session shares belongs
/// to the `App` and reaches a scene through `.environment(_:)`.
/// Opening and closing its windows is its `SceneSession`'s, in the
/// environment of every view in it.
@preconcurrency @MainActor public protocol Scene {
    /// The scene's windows: its main one, and the groups it may open beside
    /// it. Read again when a state it read changes.
    var windows: Windows { get }
}

extension Scene {
    /// Chooses whether this scene opens automatically at launch or reactivation.
    /// Explicit `openWindow` calls are unaffected by `.suppressed`.
    public func defaultLaunchBehavior(_ behavior: SceneLaunchBehavior) -> some Scene {
        PlacedScene(base: self) { windows in
            var windows = windows
            windows.launchBehavior = behavior
            windows.groups = windows.groups.map { group in
                var group = group
                group.launchBehavior = behavior
                return group
            }
            return windows
        }
    }

    /// Controls whether windows of this scene may be restored on a later launch.
    public func restorationBehavior(_ behavior: SceneRestorationBehavior) -> some Scene {
        PlacedScene(base: self) { windows in
            var windows = windows
            windows.restorationBehavior = behavior
            windows.groups = windows.groups.map { group in
                var group = group
                group.restorationBehavior = behavior
                return group
            }
            return windows
        }
    }

    /// Offers an object to every window of every session of this scene,
    /// resolved by type the way `.environment` on a view is.
    ///
    ///     var body: some Scene { GalleryScene().environment(library) }
    ///
    /// A nearer `.environment()` of the same type - on `Windows`, or on a
    /// view inside - overrides it for its own branch.
    public func environment<Value: AnyObject>(_ object: Value) -> Scene {
        OfferingScene(base: self, key: ObjectIdentifier(Value.self), object: object)
    }

    /// Writes an environment value into every window of every session of
    /// this scene, resolved by key path the way `.environment(_:_:)` on a
    /// view is.
    public func environment<Value>(
        _ keyPath: WritableKeyPath<EnvironmentValues, Value>, _ value: Value
    ) -> some Scene {
        PlacedScene(base: self) { $0.environment(keyPath, value) }
    }

    /// Where the scene's windows open: `position`'s fractions across and
    /// down the screen's work area land the same fractions across and down
    /// the window - `.center` centers it, `.topLeading` its top left corner
    /// at the work area's.
    ///
    /// The scene's default: its main window opens there, and so does the
    /// window of a group that does not say its own. Written on a `Window` or
    /// a `WindowScene` the ask is that window's own.
    ///
    ///     var body: some Scene { EditorScene().defaultPosition(.center) }
    public func defaultPosition(_ position: UnitPoint) -> some Scene {
        if let scene = self as? WindowScene {
            return AnyScene(base: ModifiedWindowScene(base: scene) { $0.position = position })
        }
        return AnyScene(base: PlacedScene(base: self) { $0.defaultPosition(position) })
    }

    /// Where the scene's windows open, the fractions outright.
    public func defaultPosition(x: Double, y: Double) -> Scene {
        defaultPosition(UnitPoint(x: x, y: y))
    }

    /// Where the scene's windows open and the size they open at, in one
    /// ask - a placement's anchor, and its size where it is not `.zero`.
    /// `.automatic` asks nothing at all.
    ///
    ///     var body: some Scene { EditorScene().defaultPlacement(.topLeading) }
    public func defaultPlacement(_ placement: WindowPlacement) -> some Scene {
        if let scene = self as? WindowScene {
            return AnyScene(base: ModifiedWindowScene(base: scene) {
                $0.position = placement.anchor
                $0.size = placement.extent.map { (width: $0.width, height: $0.height) }
            })
        }
        return AnyScene(base: PlacedScene(base: self) { $0.defaultPlacement(placement) })
    }

    /// Where the scene's main window opens, as the closure asks it: the
    /// SwiftUI `windowIdealPlacement` spelling, whose closure is handed the
    /// window's content and a placement context. SwiftOmniUI resolves the
    /// placement once as the scene builds - the content and context it hands
    /// stand empty - so a closure answering where the window should sit, as
    /// `WindowPlacement(.center)` does, lands the same on every platform.
    ///
    ///     var body: some Scene {
    ///         Window("欢迎页", id: "welcome") { WelcomePage() }
    ///             .windowIdealPlacement { content, context in WindowPlacement(.center) }
    ///     }
    public func windowIdealPlacement(
        _ makePlacement: @escaping (WindowLayoutRoot, WindowPlacementContext) -> WindowPlacement
    ) -> some Scene {
        defaultPlacement(makePlacement(WindowLayoutRoot(), WindowPlacementContext()))
    }

    /// The size the scene's windows open at, in device units - the scene's
    /// default, a group's own winning where it says one. Written on a
    /// `Window` or a `WindowScene` the ask is that window's own:
    ///
    ///     var body: some Scene { Window { MainPage() }.defaultSize(width: 800, height: 600) }
    public func defaultSize(width: Double, height: Double) -> some Scene {
        if let scene = self as? WindowScene {
            return AnyScene(base: ModifiedWindowScene(base: scene) {
                $0.size = (width: width, height: height)
            })
        }
        return AnyScene(base: PlacedScene(base: self) { $0.defaultSize(width: width, height: height) })
    }

    /// The size the scene's windows open at, as one value.
    public func defaultSize(_ size: Size) -> Scene {
        defaultSize(width: size.width, height: size.height)
    }

    /// How the scene's windows settle their size against their content -
    /// `.contentSize` has each take the size its content asks for and no
    /// other:
    ///
    ///     var body: some Scene { Window { MainPage() }.windowResizability(.contentSize) }
    ///
    /// Written on a `Window` or a `WindowScene` the ask is that window's
    /// own; written on any other scene it is the default every window of it
    /// falls back on.
    public func windowResizability(_ resizability: WindowResizability) -> some Scene {
        if let scene = self as? WindowScene {
            return AnyScene(base: ModifiedWindowScene(base: scene) { $0.resizability = resizability })
        }
        return AnyScene(base: PlacedScene(base: self) { $0.windowResizability(resizability) })
    }
}

/// A scene with an object offered to everything in it.
struct OfferingScene: Scene {
    /// The scene the object is offered to.
    let base: any Scene

    /// The type the object answers for.
    let key: ObjectIdentifier

    /// The object.
    let object: AnyObject

    var windows: Windows { base.windows }
}

/// A scene whose `Windows` is edited before the tree reads it - how a
/// modifier written on `Windows` stands on a scene of any shape. The edit
/// runs as `windows` is read, inside the scene's own build, so what the
/// wrapped scene's state says is what is edited.
struct PlacedScene: Scene {
    /// The scene the edit lands on.
    let base: any Scene

    /// What the scene's windows becomes.
    let edit: (Windows) -> Windows

    var windows: Windows { edit(base.windows) }
}

/// A scene as one concrete value: what a modifier answering a window's own
/// `WindowScene` or a scene of any other shape returns as `some Scene` - the
/// opaque result needs one underlying type, and this boxes either.
struct AnyScene: Scene {
    /// The scene, whatever it was.
    let base: any Scene

    var windows: Windows { base.windows }
}

/// The automatic presentation policy of a scene, matching SwiftUI.
public struct SceneLaunchBehavior: Sendable, Equatable {
    private let value: Int
    public static let automatic = Self(value: 0)
    public static let presented = Self(value: 1)
    public static let suppressed = Self(value: 2)
}

/// Whether the system may restore a scene's windows on a later launch.
public struct SceneRestorationBehavior: Sendable, Equatable {
    private let value: Int
    public static let automatic = Self(value: 0)
    public static let disabled = Self(value: 1)
}
