// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// A scrollable container.
public enum ScrollViewContract: ElementContract {
    /// The node type the contract declares.
    public static let nodeType: NodeType = "ScrollView"

    /// Every base host presents it with its native control.
    public static let layer: ElementLayer = .native

    /// A scroller is a view, padded around what it holds, and clips or lets
    /// its children through as every layout does.
    public static let tiers: [any Contract.Type] = [
        ViewContract.self, PaddingElementContract.self, BorderElementContract.self,
        ScrollContentElementContract.self, LayoutContract.self,
    ]

    /// Where the scroller rests before anything is written - the anchor's
    /// fractions across and down the content and the room.
    public static let defaultScrollAnchor = ElementProperty<Self, UnitPoint>(
        "defaultScrollAnchor", layer: .native)

    /// Whether the bar along the bottom is drawn.
    public static let horizontalScrollIndicators = ElementProperty<Self, ScrollIndicatorVisibility>(
        "horizontalScrollIndicators", layer: .adaptive)

    /// Whether the hand's scroll is answered - a scroller that takes none
    /// hands it to whatever lies under it.
    public static let isScrollDisabled = ElementProperty<Self, Bool>("isScrollDisabled", layer: .native)

    /// Which way it scrolls.
    public static let orientation = ElementProperty<Self, Axis>("orientation", layer: .native)

    /// Whether it springs back past its content's end.
    public static let scrollBounceBehavior = ElementProperty<Self, ScrollBounceBehavior>(
        "scrollBounceBehavior", layer: .native)

    /// Which axes `scrollBounceBehavior` applies to - `.all` when unsaid.
    public static let scrollBounceAxes = ElementProperty<Self, Axis.Set>(
        "scrollBounceAxes", layer: .native)

    /// How it settles when the hand leaves it - on a target's edge, or a page
    /// at a time.
    public static let scrollTargetBehavior = ElementProperty<Self, ScrollTargetBehavior>(
        "scrollTargetBehavior", layer: .native)

    /// Where the scroller stands, in device units from the content's top-left
    /// corner: one point, so a diagonal scroll arrives on both axes together.
    public static let scrollOffset = ElementProperty<Self, Point>(
        "scrollOffset", layer: .structure, travels: false)

    /// The scroller came to rest.
    public static let scrollStopped = ElementEvent<Self, Void>("scrollStopped", layer: .native)

    /// Scrolls until the child `.id()` names stands where the anchor says -
    /// fractions across and down the target and the room, absent for "only
    /// where it is not wholly in view".
    public static let scrollToDescendant = ElementAct<Self, (String, Double?, Double?), Void>("scrollToDescendant")

    /// The scroller moved across, to the offset it carries.
    public static let scrollXChanged = ElementEvent<Self, Double>("scrollXChanged", layer: .native)

    /// The scroller moved down, to the offset it carries.
    public static let scrollYChanged = ElementEvent<Self, Double>("scrollYChanged", layer: .native)

    /// Whether the bar down the side is drawn.
    public static let verticalScrollIndicators = ElementProperty<Self, ScrollIndicatorVisibility>(
        "verticalScrollIndicators", layer: .adaptive)

    /// The element's own members.
    public static let members: [any ContractMember] = [
        defaultScrollAnchor, horizontalScrollIndicators, isScrollDisabled, orientation, scrollBounceAxes,
        scrollBounceBehavior, scrollOffset, scrollStopped, scrollTargetBehavior, scrollToDescendant,
        scrollXChanged, scrollYChanged, verticalScrollIndicators,
    ]
}
