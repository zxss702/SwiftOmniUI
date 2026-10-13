// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The structure every host shows: App, Scene, WindowScene, Page.
// Design: docs/design/views/pages.md#app-scene-window-page

/// The application at the root of a SwiftOmniUI tree.
///
/// Handed to `stateUIUseApp` once, at startup; the host then connects the
/// platform's application and scene lifecycle to it.
///
/// It declares its scene and nothing else. What the whole application is - its
/// styles, how its values move, what it keeps between launches - is its
/// `ApplicationSession`, written where the application is made:
///
///     @main
///     struct NotesApp: App {
///         @Environment private var application: ApplicationSession
///
///         init() {
///             application.styles = AppStyles.sheet
///             application.persistentKeys = [.lastNote]
///         }
///
///         var body: some Scene { Window { MainPage() } }
///     }
///
/// Write it in `init`: the kept state's keys are read as the application
/// registers, before the first view is built. The standard environment - the
/// device, the display, the locale - is known there already.
@preconcurrency @MainActor public protocol App {
    /// What each session of the application is: its main window, the windows
    /// it opens beside it, and the state they share. See `Scene`.
    ///
    ///     var body: some Scene { Window { MainPage() } }        // one window
    ///     var body: some Scene { EditorScene().environment(library) }
    ///
    /// The platform makes as many sessions as the user asks for.
    associatedtype Body: Scene
    @SceneBuilder var body: Body { get }

    /// Made with nothing - the application's own initializer is where its
    /// session is written.
    init()
}

extension App {
    /// What `@main` calls: registers the application with the host, whose own
    /// entry connects the platform's lifecycle to it.
    ///
    /// A host that loads the app as a native library finds
    /// `swiftomniui_app_register` instead, and calls `stateUIUseApp` itself.
    public static func main() {
        stateUIUseApp(Self())
    }
}

/// A window onto a page.
///
///     struct MainWindow: WindowScene {
///         var page: any Page { MainPage() }
///     }
///
/// A type you declare, never a value you chain onto: `page` is its one
/// requirement, and it may hold `@State` of its own. What the window is as it
/// runs - its title, its frame, its title bar, the pages presented over it,
/// its lifecycle - is its `WindowSession`, in the environment of everything in
/// it:
///
///     struct MainPage: View {
///         @Environment private var window: WindowSession
///
///         var body: some View {
///             VStack { … }
///                 .onAppear {
///                     window.title = "My App"
///                     window.width = 1200
///                 }
///         }
///     }
///
/// A scene with several kinds of window declares each kind once and names
/// them in its `Windows`. What every view in a window needs is offered above
/// it, with `.environment(_:)` on the scene or on its `Windows`.
public protocol WindowScene: Element, Scene {
    /// What the window shows: a `NavigationStack`, a `TabView`, a
    /// `NavigationSplitView`, or any other view - usually a `ContentView` of the
    /// application's own. Read again when a state it read changes.
    var page: any Page { get }
}

extension WindowScene {
    /// A window alone is a scene of one window:
    /// `var body: some Scene { MainWindow() }`. A window named for
    /// `openWindow(id:)` is also the group that name reopens once the user
    /// has closed it.
    public var windows: Windows {
        var groups: [WindowGroup] = []
        if let asks = self as? WindowSceneAsks, let id = asks.windowID {
            groups.append(WindowGroup(WindowType(id)) { self })
        }
        return Windows(groups: groups, main: self)
    }

    /// The window as a node: its page, and what hangs off it - its title bar
    /// and the pages presented over it.
    public var node: Node {
        let request = ElementSession(WindowSession.self) { WindowSession() }

        var node = composed { request.held(as: WindowSession.self) }
        node.session = request
        return node
    }

    /// The same, for a window of a scene: the session it keeps.
    /// Design: docs/design/views/pages.md#a-window-is-a-placeholder
    func node(session: WindowSession) -> Node {
        var node = composed { session }

        // On the placeholder, so the window's own `@Environment` resolves it too.
        node.environments.append((key: ObjectIdentifier(WindowSession.self), object: session))

        return node
    }

    private func composed(session: @escaping () -> WindowSession) -> Node {
        Node.composed(self, type: String(reflecting: Self.self)) {
            let session = session()
            let overlay = Node.overlay(session.overlays)

            // Its page, the title bar and modal stack, the overlay: one order.
            // Design: docs/design/views/pages.md#the-children-of-a-window
            var node = Node(
                contract: WindowSceneContract.self,
                children: [Node.page(page)] + session.slots + (overlay.map { [$0] } ?? []))
            node.props = session.props
            node.environmentValues[keyPath: \.dismiss] = session.dismissal

            // What the window asks of its own - its title, size, place, how it
            // resizes - over anything the session already wrote.
            if let asks = self as? WindowSceneAsks {
                if let title = asks.windowTitle {
                    node.write(WindowSceneContract.title, title)
                }
                if let resizability = asks.windowResizability {
                    node.write(WindowSceneContract.resizability, resizability)
                }
                if let size = asks.windowSize {
                    node.write(WindowSceneContract.width, size.width)
                    node.write(WindowSceneContract.height, size.height)
                }
                if let position = asks.windowPosition {
                    node.write(WindowSceneContract.defaultPosition, position)
                }
            }

            // One handler per lifecycle report, never iterated from a collection.
            // Design: docs/design/views/pages.md#lifecycle-reports-one-by-one
            node.addHandler(WindowSceneContract.created.token) { session.phase = .created }
            node.addHandler(WindowSceneContract.activated.token) { session.phase = .activated }
            node.addHandler(WindowSceneContract.deactivated.token) { session.phase = .deactivated }
            node.addHandler(WindowSceneContract.stopped.token) { session.phase = .stopped }
            node.addHandler(WindowSceneContract.resumed.token) { session.phase = .resumed }
            node.addHandler(WindowSceneContract.destroying.token) { session.phase = .destroying }

            if let stack = session.modalStack { node.addHandler(WindowSceneContract.modalPopped.token, stack.popped) }

            return node
        }
    }
}

extension Node {
    /// What a window lays over its page and the pages presented over it: one ZStack of its overlays, each under
    /// its key, so a layer keeps its elements as the others come and go; nil for none.
    /// Design: docs/design/views/pages.md#the-children-of-a-window
    static func overlay(_ overlays: WindowOverlays) -> Node? {
        guard !overlays.layers.isEmpty else { return nil }

        var stack = ZStack().letsInputThrough(true).node
        stack.children = overlays.layers.map { key, view in
            var node = view.node
            node.key = key.name
            if let written = overlays.environments[key] {
                node.environmentValues = node.environmentValues.overlaid(with: written)
            }
            return node
        }
        return Node(contract: OverlayContract.self, children: [stack])
    }
}

/// What a container shows as a screen: a window's `page`, a navigation
/// stack's root and destinations, a tab, either half of a split view, a
/// sheet.
///
/// Nobody conforms to it by hand. Every view is a page, and so is each
/// arrangement - `NavigationStack`, `TabView`, `NavigationSplitView` - which is not a
/// view and so stands only where a page stands.
///
/// A view shown as a page holds a `PageSession`, in the environment of
/// everything in it, carrying what the screen is - its title, its buttons,
/// its menus, its lifecycle:
///
///     struct MainPage: View {
///         @Environment private var page: PageSession
///
///         var body: some View {
///             VStack { … }
///                 .onAppear { page.title = "Home" }
///         }
///     }
///
/// What `.onAppear` writes arrives with the page. A page asks things of the
/// container showing it through the same session, `page.hasNavigationBar =
/// false`; the bar's look belongs to the arrangement drawing it. An
/// arrangement is told its title and icon by modifier, from `PageElement`.
@preconcurrency @MainActor public protocol Page: Element {}

/// An arrangement: a page this library declares, shown as it is.
protocol PageArrangement: Page {}

/// The node types the arrangements make, for recognizing one once a modifier
/// has wrapped its view in a `ModifiedContent`.
private let pageArrangements: Set<NodeType> = [
    NavigationSplitViewContract.nodeType,
    NavigationStackContract.nodeType,
    TabViewContract.nodeType,
]

extension Node {
    /// A view shown as a screen: an arrangement as it is, any other view on a
    /// page element of its own, which holds the view's `PageSession`.
    /// Design: docs/design/views/pages.md#a-page-around-a-view
    @MainActor static func page(_ shown: any Page) -> Node {
        // A modifier on an arrangement makes a `ModifiedContent`, whose node
        // still is the arrangement's - the arrangement shows as it is.
        let content = shown.node
        if shown is any PageArrangement || pageArrangements.contains(content.type) { return content }
        let kind = (content.stateful?.viewType ?? content.type.name) + (content.id.map { "#\($0)" } ?? "")
        let request = ElementSession(PageSession.self) { PageSession() }

        var node = composed(ShownView(content: content), type: "SwiftOmniUICore.Page(\(kind))") {
            page(around: content, session: request.held(as: PageSession.self))
        }

        // The destinations `.navigationDestination` registered on the
        // content ride on the page: the stack holding it reads them off its
        // root before the placeholder is built.
        node.itemDestination = content.itemDestination
        node.destinations.merge(content.destinations) { own, _ in own }
        node.session = request
        return node
    }

    /// The page: the session's properties, its content first - so a page
    /// gaining a title view does not move its content - then what hangs off it.
    /// A `.navigationTitle` or `.badge` written on the content's root names the
    /// page itself, where the session has not already.
    private static func page(around content: Node, session: PageSession) -> Node {
        var node = Node(contract: PageContract.self, children: [content] + session.slots)
        node.props = session.props
        for member in [
            PageElementContract.title.token, PageElementContract.titleKey.token,
            PageElementContract.badge.token,
            PageElementContract.subtitle.token, PageElementContract.subtitleKey.token,
            PageElementContract.document.token,
            PageElementContract.preferredColumnWidth.token,
            PageElementContract.presentationDetents.token,
            PageElementContract.presentationDragIndicator.token,
            PageElementContract.interactiveDismissDisabled.token,
            PageElementContract.toolbarVisibility.token,
            PageElementContract.toolbarBackground.token,
            PageElementContract.windowBackground.token,
            PageContract.hasBackButton.token,
        ] where node.props[member] == nil {
            node.props[member] = content.props[member]
        }

        node.addHandler(PageContract.appearing.token) { session.phase = .appearing }
        node.addHandler(PageContract.disappearing.token) { session.phase = .disappearing }
        node.addHandler(PageContract.navigatedTo.token) { session.phase = .navigatedTo }
        node.addHandler(PageContract.navigatingFrom.token) { session.phase = .navigatingFrom }
        node.addHandler(PageContract.navigatedFrom.token) { session.phase = .navigatedFrom }

        return node
    }
}

/// The view a page shows, held as a node so the view is compared on its own.
private struct ShownView {
    let content: Node
}

// Design: docs/design/views/pages.md#the-application-is-named-once
/// Names the application to the host.
///
/// The one line an app writes outside its own interface, in the function the
/// host calls by name at startup, in the app's own module:
///
///     @_cdecl("swiftomniui_app_register")
///     public func swiftomniui_app_register() {
///         stateUIUseApp(HelloWorldApp())
///     }
///
/// - Parameter application: the application, made here with a fresh
///   application session and kept for the life of the process, so `@State`
///   declared on it outlives every window.
@_spi(Host) public func stateUIUseApp(_ application: @autoclosure () -> any App) {
    Renderer.shared.setApplication(application())
}
