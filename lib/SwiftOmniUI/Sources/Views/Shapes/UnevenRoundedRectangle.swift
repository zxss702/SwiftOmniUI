// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// A rectangle whose corners each round by their own radius, drawn by:
///
///     UnevenRoundedRectangle(bottomLeadingRadius: 20, bottomTrailingRadius: 20)
///         .fill(.cornflowerBlue)
///     Rectangle().background(UnevenRoundedRectangle(topLeadingRadius: 12).fill(.gray))
public struct UnevenRoundedRectangle: Shape, VisualElement, ShapeProperties {
    /// The node this control describes.
    public var node: Node

    /// The four corners' radii, clockwise from the top leading corner.
    public let cornerRadii: RectangleCornerRadii

    /// A rectangle whose corners round each by their own radius, in device
    /// units; a corner not named stays square - name it `0`.
    public init(
        topLeadingRadius: Double,
        bottomLeadingRadius: Double,
        bottomTrailingRadius: Double,
        topTrailingRadius: Double,
        style: RoundedCornerStyle
    ) {
        cornerRadii = RectangleCornerRadii(
            topLeading: topLeadingRadius, topTrailing: topTrailingRadius,
            bottomLeading: bottomLeadingRadius, bottomTrailing: bottomTrailingRadius)
        node = Node(shape: RectangleContract.self)
        node.props[RectangleContract.cornerRadius.token] = CornerRadius.corners(
            topLeft: topLeadingRadius, topRight: topTrailingRadius,
            bottomLeft: bottomLeadingRadius, bottomRight: bottomTrailingRadius
        ).propValue
    }

    /// A rectangle whose corners round each by their own radius, in
    /// `style`'s bend - `.continuous` drawing as the circular bend where the
    /// host has no squircle.
    public init(cornerRadii: RectangleCornerRadii, style: RoundedCornerStyle) {
        self.init(
            topLeadingRadius: cornerRadii.topLeading,
            bottomLeadingRadius: cornerRadii.bottomLeading,
            bottomTrailingRadius: cornerRadii.bottomTrailing,
            topTrailingRadius: cornerRadii.topTrailing,
            style: style)
    }
}

/// The four corners' radii of a rounded rectangle, in device units.
public struct RectangleCornerRadii: Equatable, Sendable {
    /// The top leading corner's radius.
    public let topLeading: Double

    /// The top trailing corner's radius.
    public let topTrailing: Double

    /// The bottom leading corner's radius.
    public let bottomLeading: Double

    /// The bottom trailing corner's radius.
    public let bottomTrailing: Double

    /// Radii of the four corners; one not named stays square.
    public init(
        topLeading: Double = 0, topTrailing: Double = 0,
        bottomLeading: Double = 0, bottomTrailing: Double = 0
    ) {
        self.topLeading = topLeading
        self.topTrailing = topTrailing
        self.bottomLeading = bottomLeading
        self.bottomTrailing = bottomTrailing
    }
}
