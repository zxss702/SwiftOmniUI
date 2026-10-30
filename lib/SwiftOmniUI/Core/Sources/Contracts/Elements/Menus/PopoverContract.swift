// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// A transient view presented over a window, anchored to the element that
/// carries it - the platform's own popover, flyout, or anchored panel.
public enum PopoverContract: ElementContract {
    /// The node type the contract declares.
    public static let nodeType: NodeType = "Popover"

    /// It hangs off an element, shown where the platform anchors such a view.
    public static let layer: ElementLayer = .adaptive

    /// Whether the popover shows; the host writes each change the element's
    /// driven property brings. What `isPresented:` names on `.popover`.
    public static let isOpen = ElementProperty<Self, Bool>("isOpen", layer: .native)

    /// The edge of the anchor the popover's arrow prefers to stand on.
    public static let arrowEdge = ElementProperty<Self, Edge>("arrowEdge", layer: .adaptive)

    /// The user took the popover away - a click outside it, its platform's
    /// own gesture: the element hears it to write its binding `false`.
    public static let dismissed = ElementEvent<Self, Void>("dismissed", layer: .adaptive)

    /// The element's own members.
    public static let members: [any ContractMember] = [isOpen, arrowEdge, dismissed]
}
