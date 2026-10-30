// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// The room a parent offers a child during layout, each axis nil where the
/// parent leaves it open - what a custom `Layout` reads in `sizeThatFits` and
/// hands each `LayoutSubview`.
///
///     func sizeThatFits(
///         proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache
///     ) -> Size { ... }
public struct ProposedViewSize: Equatable, Sendable {
    /// The offered width, nil for "take your natural width".
    public var width: Double?

    /// The offered height, nil for "take your natural height".
    public var height: Double?

    /// A proposal of `width` by `height`, either axis open where nil.
    public init(width: Double? = nil, height: Double? = nil) {
        self.width = width
        self.height = height
    }

    /// A proposal of `size`, both axes fixed.
    public init(_ size: Size) {
        width = size.width
        height = size.height
    }

    /// Nothing at all.
    public static let zero = ProposedViewSize(width: 0, height: 0)

    /// Both axes open - the child answers its natural size.
    public static let unspecified = ProposedViewSize()

    /// All the room there is, on both axes.
    public static let infinity = ProposedViewSize(
        width: .infinity, height: .infinity)

    /// The proposal as a definite size, `defaultValue` standing in for each
    /// axis left open or infinite.
    public func replacingUnspecifiedDimensions(
        by defaultValue: Size = Size(width: 10, height: 10)
    ) -> Size {
        Size(
            width: width.map { $0.isFinite ? $0 : defaultValue.width } ?? defaultValue.width,
            height: height.map { $0.isFinite ? $0 : defaultValue.height } ?? defaultValue.height)
    }
}
