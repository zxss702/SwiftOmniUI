// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// `ScrollView`'s own properties, shared by the control and its
/// `Style<ScrollView>`.
public protocol ScrollViewProperties: PropertyContainer {}

extension ScrollViewProperties {
    /// Which way it scrolls, if not down. The default is `.vertical`.
    ///
    /// `.neither` is for a scroller with nothing to scroll, such as an emptied
    /// list: it goes back to the beginning. To stop the user's hand and leave
    /// the scroller where it stands, write `.allowsHitTesting(!true)` instead.
    @_spi(Host) public func orientation(_ value: Axis) -> Modified {
        setValue(ScrollViewContract.orientation, value)
    }

    /// Where the scroller rests before anything is written - the anchor's
    /// fractions across and down the content and the room.
    @_spi(Host) public func defaultScrollAnchor(_ value: UnitPoint) -> Modified {
        setValue(ScrollViewContract.defaultScrollAnchor, value)
    }

    /// Whether the hand's scroll is answered. The default is answered.
    ///
    /// `ScrollView`'s own spelling of `.scrollDisabled` - the scroller written
    /// to, not every view.
    @_spi(Host) public func isScrollDisabled(_ value: Bool) -> Modified {
        setValue(ScrollViewContract.isScrollDisabled, value)
    }

    /// Whether it springs back past its content's end.
    @_spi(Host) public func scrollBounceBehavior(_ value: ScrollBounceBehavior) -> Modified {
        setValue(ScrollViewContract.scrollBounceBehavior, value)
    }

    /// How it settles when the hand leaves it.
    @_spi(Host) public func scrollTargetBehavior(_ value: ScrollTargetBehavior) -> Modified {
        setValue(ScrollViewContract.scrollTargetBehavior, value)
    }

    /// Whether the bar down the side is drawn.
    ///
    /// `.never` is what a scroller inside a page of cards usually wants - the
    /// bar says the same thing the content already does.
    @_spi(Host) public func verticalScrollIndicators(_ value: ScrollIndicatorVisibility) -> Modified {
        setValue(ScrollViewContract.verticalScrollIndicators, value)
    }

    /// The same, along the bottom.
    @_spi(Host) public func horizontalScrollIndicators(_ value: ScrollIndicatorVisibility) -> Modified {
        setValue(ScrollViewContract.horizontalScrollIndicators, value)
    }

    /// Whether the bars are drawn - the SwiftUI spelling, both axes at once:
    ///
    ///     ScrollView { … }.scrollIndicators(.hidden)
    ///
    /// `axes` is `.vertical`, `.horizontal`, or both.
    public func scrollIndicators(
        _ visibility: ScrollIndicatorVisibility,
        axes: Axis.Set = .all
    ) -> Modified {
        modified { node in
            if axes.contains(.vertical) { node.write(ScrollViewContract.verticalScrollIndicators, visibility) }
            if axes.contains(.horizontal) { node.write(ScrollViewContract.horizontalScrollIndicators, visibility) }
        }
    }
}

/// A scrollable container.
///
///     ScrollView {
///         VStack { … }
///     }
///     .verticalScrollIndicators(.hidden)
///
/// `.padding` is inside the scroller and moves with the content; `.margin` is
/// outside it and stays put. A ScrollView describes every child it holds,
/// whether or not any of them can be seen.
///
/// When a one-axis scroller is nested in another, it owns gestures along its
/// axis and passes a dominant gesture on the disabled axis to the enclosing
/// scroller. A horizontal code listing can therefore live inside a vertical
/// page without interrupting the page's movement.
public struct ScrollView: VisualElement, PaddingElement, BorderElement, ScrollViewProperties{
    /// The node this control describes.
    public var node: Node

    /// An empty one - what a `Style<ScrollView>` is written against.
    public init() {
        node = Node(contract: ScrollViewContract.self)
    }

    /// A scrollable view around what the closure describes. The closure runs
    /// when the differ reaches the scroller.
    public init(@ViewBuilder content: @escaping () -> any View) {
        node = Node(contract: ScrollViewContract.self)
        node.producer = { content().node.asChildren }
    }

    /// A scroller along `axes` - `.horizontal`, `.vertical` or both - around
    /// what the closure describes: the SwiftUI spelling.
    ///
    ///     ScrollView(.horizontal) { HStack { … } }
    public init(_ axes: Axis.Set, @ViewBuilder content: @escaping () -> any View) {
        self.init(content: content)
        if axes == .horizontal { node.write(ScrollViewContract.orientation, Axis.horizontal) }
        else if axes == [.horizontal, .vertical] { node.write(ScrollViewContract.orientation, Axis.both) }
    }

    /// Where the scroller stands, both ways - the host writes the user's
    /// scrolling into the state and a value written there moves the scroller.
    /// Design: docs/design/views/bindings.md#feeds
    @_spi(Host) public func scrollOffset(_ state: Binding<Point>) -> Self {
        journey(.scrollOffset, by: state)
    }

    /// Runs once the scroller has come to rest: nothing is moving and no finger
    /// is on it.
    ///
    ///     ScrollView { … }.onScrollStopped { load() }
    ///
    /// The moment for work that would show as a hitch during a swipe, and for
    /// carrying the scroller on to the nearest item by writing the offset. It
    /// runs once per movement the user makes - a drag let go, a throw that ran
    /// out, a wheel, a key - and not for one that leaves the offset where it
    /// was, nor for one the application wrote.
    @_spi(Host) public func onScrollStopped(_ handler: @escaping EventHandler) -> Self {
        onEvent(ScrollViewContract.scrollStopped, handler)
    }
}

extension ScrollView {
    /// `horizontalScrollIndicators` from a state, `$x`.
    @_spi(Host) public func horizontalScrollIndicators(_ state: Binding<ScrollIndicatorVisibility>) -> Modified {
        plain(.horizontalScrollIndicators, by: state)
    }

    /// `defaultScrollAnchor` from a state, `$x`.
    @_spi(Host) public func defaultScrollAnchor(_ state: Binding<UnitPoint>) -> Modified {
        plain(.defaultScrollAnchor, by: state)
    }

    /// `isScrollDisabled` from a state, `$x`.
    @_spi(Host) public func isScrollDisabled(_ state: Binding<Bool>) -> Modified {
        plain(.isScrollDisabled, by: state)
    }

    /// `orientation` from a state, `$x`.
    @_spi(Host) public func orientation(_ state: Binding<Axis>) -> Modified {
        plain(.orientation, by: state)
    }

    /// `scrollBounceBehavior` from a state, `$x`.
    @_spi(Host) public func scrollBounceBehavior(_ state: Binding<ScrollBounceBehavior>) -> Modified {
        plain(.scrollBounceBehavior, by: state)
    }

    /// `scrollTargetBehavior` from a state, `$x`.
    @_spi(Host) public func scrollTargetBehavior(_ state: Binding<ScrollTargetBehavior>) -> Modified {
        plain(.scrollTargetBehavior, by: state)
    }

    /// `verticalScrollIndicators` from a state, `$x`.
    @_spi(Host) public func verticalScrollIndicators(_ state: Binding<ScrollIndicatorVisibility>) -> Modified {
        plain(.verticalScrollIndicators, by: state)
    }
}
