// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

extension View {
    /// Whether a scroll view inside answers the hand - a scroller that takes
    /// none hands its gesture to whatever lies under it:
    ///
    ///     ScrollView(.horizontal) { … }
    ///         .scrollDisabled(true)
    ///
    /// - Parameter disabled: `true` to leave it where it stands.
    public func scrollDisabled(_ disabled: Bool) -> ModifiedContent {
        revised { $0.writeInherited(ScrollViewContract.isScrollDisabled, disabled) }
    }

    /// Whether a scroll view inside springs back past its content's end:
    ///
    ///     ScrollView { … }.scrollBounceBehavior(.basedOnSize)
    ///
    /// - Parameter behavior: `.automatic`, `.always`, or `.basedOnSize`.
    public func scrollBounceBehavior(_ behavior: ScrollBounceBehavior) -> ModifiedContent {
        revised { $0.writeInherited(ScrollViewContract.scrollBounceBehavior, behavior) }
    }

    /// Whether a scroll view inside springs back past its content's end,
    /// along the named axes - the full SwiftUI spelling:
    ///
    ///     ScrollView(.horizontal) { … }.scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    ///
    /// - Parameters:
    ///   - behavior: `.automatic`, `.always`, or `.basedOnSize`.
    ///   - axes: which ways the spring answers - both when unsaid.
    public func scrollBounceBehavior(
        _ behavior: ScrollBounceBehavior,
        axes: Axis.Set = [.vertical, .horizontal]
    ) -> ModifiedContent {
        revised {
            $0.writeInherited(ScrollViewContract.scrollBounceBehavior, behavior)
            $0.writeInherited(ScrollViewContract.scrollBounceAxes, axes)
        }
    }

    /// Whether a scroll view inside cuts its content at its own edges -
    /// `true` lets a shadow or a bleed draw outside them:
    ///
    ///     ScrollView { … }.scrollClipDisabled()
    ///
    /// - Parameter disabled: `true` to draw past the edges.
    public func scrollClipDisabled(_ disabled: Bool = true) -> ModifiedContent {
        revised { $0.writeInherited(LayoutContract.clipsContent, !disabled) }
    }

    /// Whether the platform's own canvas shows behind a scrollable view's
    /// content - a list's or an editor's:
    ///
    ///     List(rows) { … }.scrollContentBackground(.hidden)
    ///
    /// - Parameter visibility: `.hidden` for the content alone, or the
    ///   platform's own.
    public func scrollContentBackground(_ visibility: Visibility) -> ModifiedContent {
        revised { $0.writeInherited(ScrollContentElementContract.scrollContentBackground, visibility) }
    }

    /// Marks a layout's children as the targets a scroller settles on:
    ///
    ///     LazyVStack { … }.scrollTargetLayout()
    ///
    /// - Parameter isEnabled: `false` to unmark it.
    public func scrollTargetLayout(_ isEnabled: Bool = true) -> ModifiedContent {
        revised { $0.writeInherited(LayoutContract.scrollTargetLayout, isEnabled) }
    }

    /// How a scroll view inside settles when the hand leaves it - on a
    /// target's edge, or one page at a time:
    ///
    ///     ScrollView { … }.scrollTargetBehavior(.viewAligned(anchor: .bottom))
    ///
    /// - Parameter behavior: `.viewAligned(anchor:)` or `.paging`.
    public func scrollTargetBehavior(_ behavior: ScrollTargetBehavior) -> ModifiedContent {
        revised { $0.writeInherited(ScrollViewContract.scrollTargetBehavior, behavior) }
    }

    /// Whether the bars of a scroll view inside are drawn - the SwiftUI
    /// spelling, reaching every scroller below:
    ///
    ///     List { … }.scrollIndicators(.hidden)
    ///
    /// - Parameters:
    ///   - visibility: `.visible`, `.hidden`, or `.automatic`.
    ///   - axes: `.vertical`, `.horizontal`, or both when unsaid.
    @_disfavoredOverload
    public func scrollIndicators(
        _ visibility: ScrollIndicatorVisibility,
        axes: Axis.Set = .all
    ) -> ModifiedContent {
        revised {
            if axes.contains(.vertical) {
                $0.writeInherited(ScrollViewContract.verticalScrollIndicators, visibility)
            }
            if axes.contains(.horizontal) {
                $0.writeInherited(ScrollViewContract.horizontalScrollIndicators, visibility)
            }
        }
    }

    /// Where a scroll view inside rests before anything is written - a chat
    /// pinned to its end:
    ///
    ///     ScrollView { … }.defaultScrollAnchor(.bottom)
    ///
    /// - Parameter anchor: the fraction across and down the content and the
    ///   room it rests at.
    public func defaultScrollAnchor(_ anchor: UnitPoint) -> ModifiedContent {
        revised { $0.writeInherited(ScrollViewContract.defaultScrollAnchor, anchor) }
    }

    /// Adds room to the safe region passed to this view's content.
    ///
    ///     TextEditor(text: $body).safeAreaPadding(.vertical, 12)
    ///
    /// - Parameters:
    ///   - edges: the edges it stands clear by, `.all` for each.
    ///   - amount: how far, the library's default for `nil`.
    public func safeAreaPadding(_ edges: Edge.Set = .all, _ amount: Double? = nil) -> ModifiedContent {
        let inset = amount ?? libraryDefaultPadding
        var insets = EdgeInsets(0, 0, 0, 0)
        if edges.contains(.leading) { insets.left = inset }
        if edges.contains(.top) { insets.top = inset }
        if edges.contains(.trailing) { insets.right = inset }
        if edges.contains(.bottom) { insets.bottom = inset }
        return revised {
            $0.wrapPaddedFrame()
            $0.props[.safeAreaPadding] = insets.propValue
        }
    }

    /// Scrolls so the child `.id` names stands at `anchor`, every time `id`
    /// moves - a write of the binding scrolls the scroll view this sits on:
    ///
    ///     ScrollView {
    ///         LazyVStack { … .id(row.id) }
    ///     }
    ///     .scrollPosition(id: $position, anchor: .top)
    ///
    /// the SwiftUI spelling; reading the position the host scrolled to is not
    /// reported yet - the binding is written from, not into.
    ///
    /// - Parameters:
    ///   - id: what `.id(_:)` on the child names; `nil` scrolls nowhere.
    ///   - anchor: where on the child it stands - `nil` moves only to make it
    ///     wholly visible.
    public func scrollPosition<Id: Hashable>(
        id: Binding<Id?>, anchor: UnitPoint? = nil
    ) -> ModifiedContent {
        let aim = Aim(ScrollView.self)
        return revised { $0.aim = aim.box }
            .onChange(of: id.wrappedValue) { _, newID in
                guard let newID else { return }
                let name = String(describing: newID)
                let (x, y) = (anchor?.x, anchor?.y)
                Task { try? await aim.call(ScrollViewContract.scrollToDescendant, name, x, y) }
            }
    }
}
