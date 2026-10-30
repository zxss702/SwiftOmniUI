// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// Properties shared by a `TitleBar` and `Style<TitleBar>`.
public protocol TitleBarProperties: PropertyContainer {}

extension TitleBarProperties {
    /// Adds a second line that identifies the current document or section.
    @_spi(Host) public func subtitle(_ value: String) -> Modified {
        setValue(TitleBarContract.subtitle, value)
    }

    /// Places a small image beside the authored title.
    @_spi(Host) public func icon(_ value: ImageSource) -> Modified {
        setValue(TitleBarContract.icon, value)
    }

    /// The colour the bar draws its authored title and subtitle in.
    ///
    /// Use `background(_:)` for the title area's background.
    @_spi(Host) public func barForegroundColor(_ value: Color) -> Modified {
        setValue(TitleBarContract.barForegroundColor, value)
    }
}

/// An authored title area attached to a window through `WindowSession`.
///
/// Hosts with native window chrome place this content according to their own
/// title-area conventions. Hosts without an authored title area may ignore it.
///
///     struct HomePage: View {
///         @Environment private var window: WindowSession
///
///         var content: any View {
///             VStack { … }
///                 .onAppear {
///                     window.titleBar = TitleBar("SwiftOmniUI Gallery")
///                         .subtitle("Fundamentals")
///                         .trailingContent {
///                             Button("Surprise me")
///                         }
///                 }
///         }
///     }
///
/// `leadingContent`, `content`, and `trailingContent` are identified child
/// subtrees. A composed view inside a slot reads and follows its own state even
/// when the surrounding `TitleBar` value is written only once. Returning no
/// child removes the slot:
///
///     TitleBar("Notes")
///         .trailingContent {
///             if showsAccount {
///                 Button(icon: "account.png")
///             }
///         }
///
/// Each slot presents one root view. Put several controls in a layout and use
/// that layout as the root.
public struct TitleBar: VisualElement, TitleBarProperties{
    /// The node this control describes.
    public var node: Node

    /// An empty one - what a `Style<TitleBar>` is written against.
    public init() {
        node = Node(contract: TitleBarContract.self)
    }

    /// Creates a title area reading `title`.
    public init(_ title: String) {
        node = Node(contract: TitleBarContract.self)
        node.write(TitleBarContract.title, title)
    }

    // MARK: The slots

    /// Places one root view before the title, such as a sidebar toggle.
    ///
    ///     TitleBar("Notes")
    ///         .leadingContent {
    ///             Button(icon: "menu.png").onClicked { showsPane.toggle() }
    ///         }
    ///
    /// A closure producing nothing empties the slot, which is what an `if` in
    /// one is for.
    @_spi(Host) public func leadingContent(@ViewBuilder _ content: () -> any View) -> Self {
        slot(LeadingContentContract.self, content())
    }

    /// Places one root view in the central title-area position.
    ///
    ///     TitleBar("Notes")
    ///         .content {
    ///             SearchField($query).frame(width: 320)
    ///         }
    ///
    /// A closure producing nothing empties the slot.
    @_spi(Host) public func content(@ViewBuilder _ content: () -> any View) -> Self {
        slot(ContentContract.self, content())
    }

    /// Places one root view at the far end of the title area.
    ///
    /// A closure producing nothing empties the slot.
    @_spi(Host) public func trailingContent(@ViewBuilder _ content: () -> any View) -> Self {
        slot(TrailingContentContract.self, content())
    }

    /// Replaces one named slot while keeping structural children last.
    private func slot<Slot: ElementContract>(_ slot: Slot.Type, _ views: any View) -> Self {
        var copy = self
        copy.node.children.removeAll { $0.type == Slot.nodeType }
        let slots = copy.node.children.filter { $0.type == .contextMenu }
        copy.node.children.removeAll { $0.type == .contextMenu }

        let filled = views.node.asChildren.first.map { [Node(contract: Slot.self, children: [$0])] } ?? []

        copy.node.children += filled + slots
        return copy
    }
}
