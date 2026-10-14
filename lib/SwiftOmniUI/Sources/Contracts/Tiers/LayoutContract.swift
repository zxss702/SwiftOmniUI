// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// What every layout has: the screen's unsafe strips it keeps clear of, and
/// whether its children are clipped or let input through.
public enum LayoutContract: Contract {
    /// The tier's name.
    public static let name = "Layout"

    /// A layout is a view, and keeps space inside itself.
    public static let tiers: [any Contract.Type] = [
        ViewContract.self, PaddingElementContract.self, BorderElementContract.self,
    ]

    /// What each edge of the layout stays clear of on the screen's unsafe
    /// strip.
    public static let ignoresSafeArea = ElementProperty<Self, SafeAreaEdges>(
        "ignoresSafeArea", layer: .adaptive)

    /// Whether children are cut off at the layout's edges.
    public static let clipsContent = ElementProperty<Self, Bool>("clipsContent", layer: .native)

    /// An independent local-coordinate path clip. An empty value clips all.
    public static let clipPath = ElementProperty<Self, [Double]>("clipPath", layer: .native, travels: false)
    public static let clipFillRule = ElementProperty<Self, FillRule>("clipFillRule", layer: .native)

    /// Whether input on the layout's own empty space passes to what is under
    /// it.
    public static let letsInputThrough = ElementProperty<Self, Bool>("letsInputThrough", layer: .native)

    /// The outline input stays within - a `.contentShape`'s, where a tap
    /// outside it reaches nothing the layout holds.
    public static let hitShape = ElementProperty<Self, ContainerShape>("hitShape", layer: .native)

    /// An independent local-coordinate input region. An empty path accepts no
    /// point; unlike clipPath it does not change what the layout draws.
    public static let hitPath = ElementProperty<Self, [Double]>("hitPath", layer: .native, travels: false)
    public static let hitFillRule = ElementProperty<Self, FillRule>("hitFillRule", layer: .native)

    /// Whether the layout's children are the targets a scroller settles on.
    public static let scrollTargetLayout = ElementProperty<Self, Bool>("scrollTargetLayout", layer: .adaptive)

    /// The tier's own members.
    public static let members: [any ContractMember] = [
        ignoresSafeArea, clipsContent, letsInputThrough, hitShape, hitPath, hitFillRule,
        scrollTargetLayout, clipPath, clipFillRule,
    ]
}
