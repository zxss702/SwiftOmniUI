// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// Hands a `ScrollViewProxy` to the views it makes, for scrolling a
/// `ScrollView` inside to a child `.id()` names - the SwiftUI spelling:
///
///     ScrollViewReader { proxy in
///         ScrollView {
///             LazyVStack { … .id("bottom") }
///         }
///         .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
///     }
///
/// The proxy's aim lands on the `ScrollView` inside - on the first, where
/// there is more than one, the way `.aim(_:)` throws when two views answer.
public struct ScrollViewReader: View {
    /// What the closure makes of the proxy it is handed.
    private let held: (ScrollViewProxy) -> any View

    /// The aim the proxy scrolls through.
    private let scroller = Aim<ScrollView>(ScrollView.self)

    /// A reader handing `content` a proxy for the scroll view inside.
    ///
    /// - Parameter content: the views, given the proxy they scroll with.
    public init(@ViewBuilder content: @escaping (ScrollViewProxy) -> any View) {
        held = content
    }

    /// The views, with the proxy's aim on the scroll view inside.
    public var body: some View {
        let aim = scroller
        return held(ScrollViewProxy(aiming: aim)).revised {
            $0.aimDescendants(wearing: ScrollViewContract.self, at: aim.box)
        }
    }
}

/// The handle a `ScrollViewReader` hands its content.
public struct ScrollViewProxy: Sendable {
    /// The aim on the scroll view inside the reader's content.
    private let aim: Aim<ScrollView>

    /// A proxy scrolling through `aim`.
    init(aiming aim: Aim<ScrollView>) {
        self.aim = aim
    }

    /// Scrolls until the child `id` names stands where `anchor` says, or only
    /// until it is wholly in view where no anchor is given - what SwiftUI's
    /// `proxy.scrollTo(_:anchor:)` does:
    ///
    ///     proxy.scrollTo("bottom", anchor: .bottom)
    ///     proxy.scrollTo(last.id)
    ///
    /// - Parameters:
    ///   - id: what `.id(_:)` on the child declares.
    ///   - anchor: where on the child it stands - `.bottom`, `.top`, or a
    ///     `UnitPoint` of the author's own; `nil` moves only to make it
    ///     wholly visible.
    public func scrollTo(_ id: some Hashable, anchor: UnitPoint? = nil) {
        let name = String(describing: id)
        let (x, y) = (anchor?.x, anchor?.y)
        Task {
            try? await aim.call(ScrollViewContract.scrollToDescendant, name, x, y)
        }
    }
}

extension Node {
    /// Puts `box` on every descendant wearing `owner` - how the reader aims
    /// at the scroll view inside what it was given.
    mutating func aimDescendants<Owner: Contract>(wearing owner: Owner.Type, at box: AimBox) {
        materialize()
        if LibraryContracts.byType[type]?.worn.contains(where: { $0 == owner }) == true, aim == nil {
            aim = box
        }
        for index in children.indices {
            children[index].aimDescendants(wearing: owner, at: box)
        }
    }
}
