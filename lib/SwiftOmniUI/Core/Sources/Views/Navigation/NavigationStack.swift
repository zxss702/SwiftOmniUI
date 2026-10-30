// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The navigation stack: what is on the native stack is an array the author
// holds, and a back gesture the user completes shortens it.

// Design: docs/design/views/pages.md#the-stack-is-the-state

/// A page holding a native stack of pages, with a bar and a back affordance.
///
///     enum Route: Hashable {
///         case details(String)
///     }
///
///     struct MainWindow: WindowScene {
///         @State private var path: [Route] = []
///
///         var page: any Page {
///             NavigationStack($path) {
///                 HomePage(path: $path)
///             } destination: { route in
///                 switch route {
///                 case .details(let id): DetailsPage(id: id)
///                 }
///             }
///         }
///     }
///
///     struct HomePage: View {
///         @Binding var path: [Route]
///         @Environment private var page: PageSession
///
///         var content: any View {
///             Button("Open the first")
///                 .onClicked { path.append(.details("first")) }
///                 .onAppear { page.title = "Home" }
///         }
///     }
///
/// Push is `path.append(_:)`, pop is `path.removeLast()`, back to the root is
/// `path = []`, and a back gesture the user completes shortens the path. Hand
/// the root page the binding: a page that pushes has to be able to write it.
///
/// The first closure is the root, always there. The second is asked for a page
/// per element of `path`, in order; a `switch` over the route type makes the
/// compiler check that every route has a page.
///
/// The path can live anywhere a `Binding` can - `@State` on the window, as
/// above, or a model offered with `.environment(_:)` that names the moves:
///
///     final class Router {
///         @State var path: [Route] = []
///
///         func open(_ id: String) { path.append(.details(id)) }
///         func home() { path = [] }
///     }
///
///     NavigationStack(router.$path) { RoutedHomePage() } destination: { … }
///
/// A route may repeat: `[.level(1), .level(2), .level(2)]` holds two different
/// `.level(2)` pages. A route must be a value whose distinct values describe
/// differently (`String(describing:)`), so a class does not qualify.
///
/// `.onChange(of: path)` observes every committed arrival and departure. The
/// title on the bar belongs to the top page; `.title` and `.icon` on the
/// stack name the whole stack where another container presents it.
public struct NavigationStack: VisualElement, BarElement, PageElement, PageArrangement {
    /// The node this page describes.
    public var node: Node

    /// The node, as every element answers it.

    /// A stack over `path`, with `root` under it and `destination` above.
    ///
    /// - Parameter path: what is on the stack, ABOVE the root - the author's
    ///   own type, borrowed two-way. A completed back gesture truncates it.
    /// - Parameter root: the page under everything, built once and kept.
    /// - Parameter destination: the page for one route, asked in path order.
    public init<Route: Hashable>(
        _ path: Binding<[Route]>,
        root: @escaping () -> any Page,
        destination: @escaping (Route) -> any Page
    ) {
        let links = ElementSession(NavigationLinks.self) { NavigationLinks() }

        node = Node(contract: NavigationStackContract.self)
        node.session = links
        node.producer = {
            let store = Self.links(in: links)
            let (root, declared) = DeclaredDestinations.collect {
                Self.identified(Node.page(root()), as: Self.rootIdentity)
            }
            var children: [Node] = [root]

            for (depth, route) in path.wrappedValue.enumerated() {
                let page = declared.typed[ObjectIdentifier(Swift.type(of: route))]
                    .map { DestinationPage(node: $0(route)) as any Page }
                    ?? destination(route)
                var pushed = Self.identified(
                    Node.page(page), as: Self.identity(depth: depth, route: route))

                // `\.dismiss` inside a pushed page backs the stack out of it.
                pushed.environmentValues[keyPath: \.dismiss] = DismissAction { [path] in
                    path.wrappedValue = Array(path.wrappedValue.prefix(depth))
                }

                children.append(pushed)
            }

            children.append(contentsOf: store.pushed)
            return children
        }
        Self.offersPushes(on: &node, through: links)

        // The platform's way back, once committed, reports how deep the stack
        // now is above the root; the path only ever shortens to match.
        // Design: docs/design/views/pages.md#a-pop-report-only-shortens
        node.addHandler(NavigationStackContract.popped.token) {
            guard let depth = EventBuffer.current.value()?.int else { return }

            let routes = path.wrappedValue
            let store = links.held(as: NavigationLinks.self)
            if depth >= 0, depth < routes.count {
                path.wrappedValue = Array(routes.prefix(depth))
                store.pop(to: 0)
            } else if depth >= routes.count {
                store.pop(to: depth - routes.count)
            }
        }
    }

    /// A stack whose pushed pages come from the destinations registered on
    /// `root` - SwiftUI's
    /// `NavigationStack(path:) { … .navigationDestination(for:) { … } }`:
    ///
    ///     NavigationStack(path: $path) {
    ///         AgentView()
    ///             .navigationDestination(for: FilePage.self) {
    ///                 FileEdittingView(filePage: $0)
    ///             }
    ///     }
    ///
    /// A `\.dismiss` inside a pushed page backs the stack out of it, and a
    /// route registering no destination pushes an empty page - the stack's
    /// depth still says where it stands.
    public init<Route: Hashable>(
        path: Binding<[Route]>,
        root: @escaping () -> any Page
    ) {
        let links = ElementSession(NavigationLinks.self) { NavigationLinks() }
        var itemOnStack = false
        var itemDismiss: (@Sendable () -> Void)?

        node = Node(contract: NavigationStackContract.self)
        node.session = links
        node.producer = {
            let store = Self.links(in: links)
            let (rootNode, declared) = DeclaredDestinations.collect {
                Self.identified(Node.page(root()), as: Self.rootIdentity)
            }
            var children: [Node] = [rootNode]

            let destinations = Self.destinations(on: rootNode, plus: declared)
            for (depth, route) in path.wrappedValue.enumerated() {
                let made = destinations[ObjectIdentifier(Swift.type(of: route))]?(route)
                    ?? EmptyView().node
                var pushed = Self.identified(
                    Node.page(DestinationPage(node: made)), as: Self.identity(depth: depth, route: route))

                pushed.environmentValues[keyPath: \.dismiss] = DismissAction { [path] in
                    path.wrappedValue = Array(path.wrappedValue.prefix(depth))
                }
                children.append(pushed)
            }

            itemOnStack = false
            if let pushed = Self.itemDestinationPage(from: rootNode, declared: declared.item) {
                children.append(pushed)
                itemOnStack = true
            }
            itemDismiss = declared.item?.dismiss ?? rootNode.itemDestination?.dismiss
                ?? rootNode.children.compactMap(\.itemDestination?.dismiss).first

            children.append(contentsOf: store.pushed)
            return children
        }
        Self.offersPushes(on: &node, through: links)

        // A back gesture past the path's depth drops the item-driven page and
        // the pages links pushed: the path holds the pushed routes, the pages
        // above them all are the one an item presents, then the links'.
        node.addHandler(NavigationStackContract.popped.token) {
            guard let depth = EventBuffer.current.value()?.int else { return }

            let routes = path.wrappedValue
            let store = links.held(as: NavigationLinks.self)
            if depth >= 0, depth < routes.count {
                path.wrappedValue = Array(routes.prefix(depth))
                itemDismiss?()
                store.pop(to: 0)
            } else if depth == routes.count {
                itemDismiss?()
                store.pop(to: 0)
            } else {
                store.pop(to: depth - routes.count - (itemOnStack ? 1 : 0))
            }
        }
    }

    /// A stack of one page - what SwiftUI's `NavigationStack { … }` says
    /// where no path is bound. A `.navigationDestination(item:)` on `root`
    /// still pushes and pops its page.
    public init(root: @escaping () -> any Page) {
        let links = ElementSession(NavigationLinks.self) { NavigationLinks() }
        var itemOnStack = false
        var itemDismiss: (@Sendable () -> Void)?

        node = Node(contract: NavigationStackContract.self)
        node.session = links
        node.producer = {
            let store = Self.links(in: links)
            let (rootNode, declared) = DeclaredDestinations.collect {
                Self.identified(Node.page(root()), as: Self.rootIdentity)
            }
            var children: [Node] = [rootNode]

            itemOnStack = false
            if let pushed = Self.itemDestinationPage(from: rootNode, declared: declared.item) {
                children.append(pushed)
                itemOnStack = true
            }
            itemDismiss = declared.item?.dismiss ?? rootNode.itemDestination?.dismiss
                ?? rootNode.children.compactMap(\.itemDestination?.dismiss).first

            children.append(contentsOf: store.pushed)
            return children
        }
        Self.offersPushes(on: &node, through: links)

        // With no path the only things to pop are the item-driven page and
        // the pages links pushed, in that order from the bottom.
        node.addHandler(NavigationStackContract.popped.token) {
            guard let depth = EventBuffer.current.value()?.int else { return }

            let store = links.held(as: NavigationLinks.self)
            if depth <= (itemOnStack ? 1 : 0) {
                itemDismiss?()
            }
            store.pop(to: max(0, depth - (itemOnStack ? 1 : 0)))
        }
    }

    /// The `NavigationLink` pages' store this stack's session holds, read so
    /// the element is built again when it changes.
    private static func links(in session: ElementSession) -> NavigationLinks {
        let store = session.held(as: NavigationLinks.self)
        Renderer.shared.stateRead(store)
        return store
    }

    /// Offers `\.pushPage` to the stack's subtree - the `NavigationLink`s in
    /// it push their destinations onto the store `links` answers.
    private static func offersPushes(on node: inout Node, through links: ElementSession) {
        node.environmentValues[keyPath: \.pushPage] = PushPageAction { [links] page in
            links.held(as: NavigationLinks.self).push(page)
        }
    }

    /// The destinations `.navigationDestination` registered on the page - its
    /// own, or its content's where the modifier wrapped it inside.
    private static func destinations(
        on rootNode: Node, plus declared: DeclaredDestinations
    ) -> [ObjectIdentifier: (Any) -> Node] {
        var found = declared.typed
        found.merge(rootNode.destinations) { own, _ in own }
        for child in rootNode.children {
            found.merge(child.destinations) { own, _ in own }
        }
        return found
    }

    /// The page an item-driven `.navigationDestination` on `rootNode`
    /// presents, or nil while its item is nil.
    private static func itemDestinationPage(from rootNode: Node, declared: Node.ItemDestination?) -> Node? {
        let itemDestination = declared ?? rootNode.itemDestination
            ?? rootNode.children.compactMap(\.itemDestination).first
        guard let made = itemDestination?.make() else { return nil }

        var pushed = Self.identified(
            Node.page(DestinationPage(node: made)), as: "item")
        let dismissItem = itemDestination?.dismiss
        pushed.environmentValues[keyPath: \.dismiss] = DismissAction {
            dismissItem?()
        }
        return pushed
    }

    /// The destinations `.navigationDestination` declared while a view
    /// expression was evaluated - collected around a stack's `root()` call,
    /// so a registration wrapped by `.alert` or another composed view still
    /// reaches the stack whose content carries it.
    struct DeclaredDestinations {
        var typed: [ObjectIdentifier: (Any) -> Node] = [:]
        var item: Node.ItemDestination?

        /// The collection active while a stack describes its root; nil at
        /// any other time, so a declaration finds its nearest stack.
        nonisolated(unsafe) static var collecting: DeclaredDestinations?

        /// Runs `describe` with collection on and hands back what it heard.
        static func collect<T>(_ describe: () -> T) -> (T, DeclaredDestinations) {
            let outside = collecting
            collecting = DeclaredDestinations()
            defer { collecting = outside }
            return (describe(), collecting ?? DeclaredDestinations())
        }
    }

    /// The root page's key, which no route's can equal: a route's carries its depth.
    private static let rootIdentity = "root"

    /// Who a pushed page is: its depth and its route together.
    /// Design: docs/design/views/pages.md#an-arrangement-keys-its-pages
    private static func identity(depth: Int, route: some Hashable) -> String {
        "\(depth)/\(String(describing: route))"
    }

    /// A page node wearing the key the stack gives it.
    private static func identified(_ node: Node, as identity: String) -> Node {
        var copy = node
        copy.id = identity
        return copy
    }
}

extension NavigationStack {
    /// The colour the bar draws on its background: the navigation title and
    /// the native navigation and toolbar affordances. Destructive actions keep
    /// the platform's warning colour.
    @_spi(Host) public func barForegroundColor(_ value: Color) -> NavigationStack {
        setValue(NavigationStackContract.barForegroundColor, value)
    }
}

/// A `Page` over an already-built node - what a `.navigationDestination`
/// factory makes once it has the value or item it was registered for, and
/// what a `NavigationLink`'s pushed page wears.
struct DestinationPage: Page {
    var node: Node
}

extension View {
    /// Registers the page the enclosing `NavigationStack` shows for a pushed
    /// value of `type` - SwiftUI's
    /// `.navigationDestination(for:content:)`:
    ///
    ///     NavigationStack(path: $path) {
    ///         HomeView()
    ///             .navigationDestination(for: FilePage.self) {
    ///                 FileEdittingView(filePage: $0)
    ///             }
    ///     }
    ///
    /// The registration rides on this view's node, where the stack reads it
    /// for each route on its path.
    public func navigationDestination<D: Hashable, C: View>(
        for type: D.Type = D.self,
        @ViewBuilder destination: @escaping (D) -> C
    ) -> ModifiedContent {
        revised {
            $0.destinations[ObjectIdentifier(type)] = { value in
                destination(value as! D).node
            }
            NavigationStack.DeclaredDestinations.collecting?.typed[ObjectIdentifier(type)] =
                $0.destinations[ObjectIdentifier(type)]
        }
    }

    /// Registers the page the enclosing `NavigationStack` pushes while
    /// `item` is set - SwiftUI's `.navigationDestination(item:destination:)`:
    ///
    ///     SettingsView()
    ///         .navigationDestination(item: $addRoute) { route in
    ///             ModelEditSheetView(defaultKind: route)
    ///         }
    ///
    /// Setting `item` pushes the destination; a way back off it - the
    /// platform's, or a `\.dismiss` - clears `item`.
    public func navigationDestination<D: Hashable, C: View>(
        item: Binding<D?>,
        @ViewBuilder destination: @escaping (D) -> C
    ) -> ModifiedContent {
        revised {
            $0.itemDestination = Node.ItemDestination(
                make: { item.wrappedValue.map { destination($0).node } },
                dismiss: { item.wrappedValue = nil })
            NavigationStack.DeclaredDestinations.collecting?.item = $0.itemDestination
        }
    }
}
