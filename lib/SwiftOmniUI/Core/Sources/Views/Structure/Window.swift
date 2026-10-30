// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// A window whose page is written in place - the one line of scene a
/// one-window application needs:
///
///     @main
///     struct NotesApp: App {
///         var body: some Scene { Window { MainPage() } }
///     }
///
/// The window's own declarations - a type that sizes, shows a sheet, answers
/// its lifecycle - are still written as a `WindowScene` of their own, which
/// `page` here stands in for.
public struct Window<Content: View>: WindowScene {
    /// The window's title, as `Window("设置", id: "setting")` names it.
    let title: String?

    /// The name `openWindow(id:)` reopens the window by once the user has
    /// closed it.
    let id: String?

    /// The page's view, rebuilt when a state the closure reads changes.
    let content: () -> Content

    /// A window showing what the closure builds.
    ///
    /// - Parameter content: the window's page - a view, or an arrangement such
    ///   as a `NavigationStack`, `TabView` or `NavigationSplitView`.
    public init(@ViewBuilder content: @escaping () -> Content) {
        title = nil
        id = nil
        self.content = content
    }

    /// A window showing what the closure builds, named as SwiftUI's
    /// `Window(_:id:)` names it:
    ///
    ///     Window("设置", id: "setting") { SettingsWindow() }
    ///
    /// - Parameters:
    ///   - title: the window's title.
    ///   - id: what a session's `openWindow(id:)` reopens it by; nil leaves it
    ///     to be the scene's main window only.
    public init(_ title: String, id: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.id = id
        self.content = content
    }

    /// The window's page: the closure's view, whatever a session's build asks.
    public var page: any Page { content() }
}

extension Window: WindowSceneAsks {
    var windowID: String? { id }
    var windowTitle: String? { title }
}

/// What a `Window` - or a modifier's wrapper over one - asks the platform
/// for of its own: its title, whether it resizes, where and how big it
/// opens, and the name `openWindow(id:)` finds it by.
///
/// A scene's `windows` reads these off the scene itself, so a modifier's
/// wrapper keeps answering for the window it wraps.
@MainActor protocol WindowSceneAsks {
    /// The name `openWindow(id:)` reopens the window by.
    var windowID: String? { get }

    /// The window's title.
    var windowTitle: String? { get }

    /// How the window settles its size against its content.
    var windowResizability: WindowResizability? { get }

    /// The size the window opens at, in device units.
    var windowSize: (width: Double, height: Double)? { get }

    /// Where the window opens on the screen.
    var windowPosition: UnitPoint? { get }
}

extension WindowSceneAsks {
    var windowID: String? { nil }
    var windowTitle: String? { nil }
    var windowResizability: WindowResizability? { nil }
    var windowSize: (width: Double, height: Double)? { nil }
    var windowPosition: UnitPoint? { nil }
}

/// A window scene with a scene modifier's ask over its own - how
/// `.defaultSize`, `.windowResizability`, `.windowIdealPlacement` and the
/// like, written on a `Window` or a `WindowScene`, land on that window alone
/// rather than on the scene's every window.
struct ModifiedWindowScene: WindowScene, WindowSceneAsks {
    /// The window scene the asks are over.
    let base: any WindowScene

    /// What the modifier asks.
    let edit: (inout Asks) -> Void

    /// What a window scene asks the platform for of its own, each nil where
    /// nothing is asked.
    struct Asks {
        var title: String?
        var resizability: WindowResizability?
        var size: (width: Double, height: Double)?
        var position: UnitPoint?
    }

    var page: any Page { base.page }

    private var asks: Asks {
        var asks = Asks()
        edit(&asks)
        return asks
    }

    var windowID: String? { (base as? WindowSceneAsks)?.windowID }
    var windowTitle: String? { asks.title ?? (base as? WindowSceneAsks)?.windowTitle }
    var windowResizability: WindowResizability? {
        asks.resizability ?? (base as? WindowSceneAsks)?.windowResizability
    }
    var windowSize: (width: Double, height: Double)? {
        asks.size ?? (base as? WindowSceneAsks)?.windowSize
    }
    var windowPosition: UnitPoint? {
        asks.position ?? (base as? WindowSceneAsks)?.windowPosition
    }
}
