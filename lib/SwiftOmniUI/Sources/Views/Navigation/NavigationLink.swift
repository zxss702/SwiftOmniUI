// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The pages a link pushed live in the stack element's session, which the
// differ hands back every render, and the stack's producer reads them.
// Design: docs/design/views/pages.md#the-stack-is-the-state

/// What pushes a page onto the `NavigationStack` the view stands in - the
/// action a `NavigationLink` runs where one is tapped.
struct PushPageAction: Sendable {
    /// The pusher the nearest stack wired for itself.
    private let act: @Sendable @MainActor (Node) -> Void

    /// An action that pushes `page` when called.
    init(_ act: @escaping @Sendable @MainActor (Node) -> Void) {
        self.act = act
    }

    /// Pushes the page.
    @MainActor func callAsFunction(_ page: Node) {
        act(page)
    }
}

/// `\.pushPage` reads a `PushPageAction`.
struct PushPageKey: EnvironmentKey {
    static let defaultValue = PushPageAction { _ in }
}

extension EnvironmentValues {
    /// The push onto the nearest `NavigationStack` - provided by the stack,
    /// read by the `NavigationLink`s in it.
    var pushPage: PushPageAction {
        get { self[PushPageKey.self] }
        set { self[PushPageKey.self] = newValue }
    }
}

/// The pages `NavigationLink`s pushed onto one `NavigationStack`, kept in
/// the stack element's session so they live as long as the element does.
@MainActor final class NavigationLinks: @unchecked Sendable {
    /// The pushed pages, bottom to top, each a page node wearing its key.
    private(set) var pushed: [Node] = []

    /// The pushed pages' numbers, never reused: a popped page and a pushed
    /// one are a leave and an arrive, not a page turned into another.
    private var next = 0

    /// Pushes `content` on the stack, wrapped as the page `\.dismiss` backs out of.
    func push(_ content: Node) {
        var page = Node.page(DestinationPage(node: content))
        page.id = "link-\(next)"
        next += 1

        let id = page.id
        page.environmentValues[keyPath: \.dismiss] = DismissAction { [weak self] in
            guard let self, let at = self.pushed.firstIndex(where: { $0.id == id }) else { return }
            self.pop(to: at)
        }
        pushed.append(page)
        Renderer.shared.stateChanged(self)
    }

    /// Keeps only the `depth` lowest pushed pages.
    func pop(to depth: Int) {
        guard pushed.count > depth else { return }
        pushed = Array(pushed.prefix(depth))
        Renderer.shared.stateChanged(self)
    }
}

/// A view the user taps to push a destination page onto the enclosing
/// `NavigationStack` - SwiftUI's
/// `NavigationLink(destination:label:)`:
///
///     NavigationStack {
///         NavigationLink {
///             DetailView()
///         } label: {
///             Text("Open")
///         }
///     }
///
/// The destination is built on the tap, not before: the closure is kept and
/// the pushed page stands for as long as it is on the stack. A way back -
/// the platform's, or a `\.dismiss` inside the pushed page - backs the stack
/// out of it.
public struct NavigationLink<Destination: View, Label: View>: View {
    /// The page a tap pushes, built then and kept.
    private let destination: () -> Destination

    /// What the tap lands on.
    private let label: () -> Label

    /// The push the nearest stack offers.
    @Environment(\.pushPage) private var pushPage

    /// A link showing `label` which pushes `destination` on a tap.
    ///
    /// - Parameters:
    ///   - destination: the page the push stands, built on the tap.
    ///   - label: what the tap lands on - a `Text`, or a row of views.
    public init(destination: @escaping () -> Destination, @ViewBuilder label: @escaping () -> Label) {
        self.destination = destination
        self.label = label
    }

    /// The label, tapped - the link is the label and a push is its press.
    public var body: some View {
        Button(action: { pushPage(destination().node) }, label: { label() })
    }
}
