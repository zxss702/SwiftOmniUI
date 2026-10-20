// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// A picture from the application's resources.
public enum ImageContract: ElementContract {
    /// The node type the contract declares.
    public static let nodeType: NodeType = "Image"

    /// Every base host presents it with its native control.
    public static let layer: ElementLayer = .native

    /// An image keeps its own size; a symbol takes the inherited font and foreground.
    public static let tiers: [any Contract.Type] = [
        ViewContract.self, ImageElementContract.self, FontElementContract.self, TextStyleElementContract.self,
    ]

    /// Whether an animated picture is running.
    public static let isAnimating = ElementProperty<Self, Bool>("isAnimating", layer: .native)

    /// The picture shown.
    public static let source = ElementProperty<Self, ImageSource>("source", layer: .native)

    /// Whether the picture may resize to its frame; `.resizable()` writes it.
    @_spi(Host) public static let isResizable = ElementProperty<Self, Bool>("isResizable", layer: .native)

    /// Whether the picture draws in its own colours or as a stencil of the
    /// foreground one; `.renderingMode` writes it.
    public static let renderingMode = ElementProperty<Self, TemplateRenderingMode>(
        "renderingMode", layer: .native)

    /// The element's own members.
    public static let members: [any ContractMember] = [isAnimating, renderingMode, source, isResizable]
}
