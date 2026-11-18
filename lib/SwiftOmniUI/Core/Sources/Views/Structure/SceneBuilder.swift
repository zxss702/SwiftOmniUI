// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// The builder an `App`'s `body` is written with: the scenes of the body, or
/// an `if` choosing between two.
///
///     var body: some Scene {
///         Window("欢迎页", id: "welcome") { WelcomePage() }
///         WindowGroup(for: URL.self) { $url in EditorWindow(url: url) }
///     }
///
/// SwiftUI reads each entry as a scene of its own; SwiftOmniUI merges their
/// window declarations, retaining each window's launch and restoration policies.
@resultBuilder
public enum SceneBuilder {
    /// A scene passes through as itself.
    public static func buildExpression<Content: Scene>(_ expression: Content) -> Content {
        expression
    }

    /// An existential scene boxes into a concrete `Scene` for parameter-pack blocks.
    @_disfavoredOverload
    public static func buildExpression(_ expression: any Scene) -> some Scene {
        let carried = Carry(expression)
        return MainActor.assumeIsolated { Carry(AnyScene(base: carried.value)) }.value
    }

    /// The one scene the body is.
    public static func buildBlock<Content: Scene>(_ scene: Content) -> Content {
        scene
    }

    /// The scenes of a multi-scene body.
    @_disfavoredOverload
    public static func buildBlock<each Content: Scene>(
        _ content: repeat each Content
    ) -> TupleScene {
        var list: [any Scene] = []
        for item in repeat each content {
            list.append(item)
        }
        let carried = Carry(list)
        return MainActor.assumeIsolated {
            Carry(TupleScene(scenes: carried.value))
        }.value
    }

    /// An `if` branch without an `else`.
    public static func buildOptional<Content: Scene>(_ scene: Content?) -> TupleScene {
        let carried = Carry(scene.map { [$0 as any Scene] } ?? [])
        return MainActor.assumeIsolated {
            Carry(TupleScene(scenes: carried.value))
        }.value
    }

    /// An `if` branch's scene.
    public static func buildEither<Content: Scene>(first scene: Content) -> ConditionalScene {
        let carried = Carry(scene)
        return MainActor.assumeIsolated { Carry(ConditionalScene(wrapped: carried.value)) }.value
    }

    /// An `else` branch's scene.
    public static func buildEither<Content: Scene>(second scene: Content) -> ConditionalScene {
        let carried = Carry(scene)
        return MainActor.assumeIsolated { Carry(ConditionalScene(wrapped: carried.value)) }.value
    }
}

/// One of two scenes an `if` in an app's `body` chose: whichever stands is the
/// scene, the other is not there.
public struct ConditionalScene: Scene {
    /// The branch taken.
    let wrapped: any Scene

    /// The windows of whichever scene was chosen.
    public var windows: Windows { wrapped.windows }
}

/// The scenes an app's `body` declares, merged without losing window policies.
/// Named windows stay independent; the legacy unnamed main window remains
/// the scene's main, and all groups answer `openWindow` together.
///
/// Window defaults stay with the scene that declared them; commands and
/// offered environments collect across the scenes.
public struct TupleScene: Scene {
    /// The scenes, in the order the body wrote them.
    let scenes: [any Scene]

    /// The windows of every scene together.
    public var windows: Windows {
        var groups: [WindowGroup] = []
        var main: WindowScene?
        var mainLaunch: SceneLaunchBehavior = .automatic
        var mainRestoration: SceneRestorationBehavior = .automatic
        var environments: [(key: ObjectIdentifier, object: AnyObject)] = []
        var environmentEdits: [(inout EnvironmentValues) -> Void] = []
        var commands: [any Commands] = []

        for scene in scenes {
            // An object's `.environment` wrapper hands its object down as the
            // merge goes by it.
            var scene = scene
            while let offered = scene as? OfferingScene {
                environments.append((key: offered.key, object: offered.object))
                scene = offered.base
            }

            let windows = scene.windows
            if let window = windows.main,
                main == nil || (mainLaunch == .suppressed && windows.launchBehavior != .suppressed)
                    || (mainLaunch != .presented && windows.launchBehavior == .presented) {
                main = window
                mainLaunch = windows.launchBehavior
                mainRestoration = windows.restorationBehavior
                if windows.defaultSize != nil || windows.defaultPosition != nil || windows.resizability != nil {
                    let own = window as? WindowSceneAsks
                    main = ModifiedWindowScene(base: window) {
                        $0.size = own?.windowSize ?? windows.defaultSize
                        $0.position = own?.windowPosition ?? windows.defaultPosition
                        $0.resizability = own?.windowResizability ?? windows.resizability
                    }
                }
            }
            groups += windows.groups.map { group in
                var group = group
                group.defaultSize = group.defaultSize ?? windows.defaultSize
                group.defaultPosition = group.defaultPosition ?? windows.defaultPosition
                group.resizability = group.resizability ?? windows.resizability
                return group
            }
            environments += windows.environments
            environmentEdits += windows.environmentEdits
            commands += windows.commands
        }

        var merged = Windows(groups: groups, main: main)
        merged.launchBehavior = mainLaunch
        merged.restorationBehavior = mainRestoration
        merged.environments = environments
        merged.environmentEdits = environmentEdits
        merged.commands = commands
        return merged
    }
}
