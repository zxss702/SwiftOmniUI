// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// Which groups of a view's values a animation applies to.
///
/// A animation written on a view applies to all of them unless it names some:
///
///     VStack { … }
///         .animation(.spring(response: 0.24))
///         .animation(.none, .size)
///
/// The stack's children move to their new places on a spring and take their
/// new size at once. A property in none of the groups follows the plain
/// `.animation(_:)` and `.all`. Visual states, showing and hiding, and a
/// child's placement follow the plain `.animation(_:)` too, and a rule naming
/// `.place`, `.width` or `.height` can snap those parts of a placement alone.
///
/// Design: docs/design/types/animation.md#groups-of-values
public struct AnimationValues: OptionSet, Sendable {
    /// The members this set holds.
    public let rawValue: Int

    /// A set from its members' bits, which is what an OptionSet is made of.
    ///
    /// - Parameter rawValue: the bits.
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// How see-through the view is: `.opacity`.
    public static let opacity = AnimationValues(rawValue: 1 << 0)

    /// Every colour it wears - a background, a text colour, a track, a thumb -
    /// known from the value itself.
    public static let colour = AnimationValues(rawValue: 1 << 1)

    /// How wide it is: `.width`, `.minimumWidth`, `.maximumWidth`, and on a
    /// layout the widths it gives its children.
    public static let width = AnimationValues(rawValue: 1 << 2)

    /// How tall it is: `.height`, `.minimumHeight`, `.maximumHeight`, and on a
    /// layout the heights it gives its children.
    public static let height = AnimationValues(rawValue: 1 << 3)

    /// Both dimensions, plus the lengths its own shape is drawn with:
    /// `.cornerRadius`, `.strokeWidth` and `.borderWidth`.
    public static let size: AnimationValues = [.width, .height]

    /// Where it sits: the place its layout gives it, and `.translationX` or
    /// `.translationY`.
    public static let place = AnimationValues(rawValue: 1 << 4)

    /// How it is turned and how big it is DRAWN, which is not how big it is:
    /// `.scale`, `.scaleX`, `.scaleY`, `.rotation`, `.rotationX`, `.rotationY`,
    /// `.pivotX` and `.pivotY`.
    public static let transform = AnimationValues(rawValue: 1 << 5)

    /// The room it keeps around and inside itself: `.padding`, `.margin`,
    /// `.spacing`, `.rowSpacing` and `.columnSpacing`.
    public static let spacing = AnimationValues(rawValue: 1 << 6)

    /// How its words are set: `.fontSize`, `.lineHeight` and
    /// `.characterSpacing`.
    public static let text = AnimationValues(rawValue: 1 << 7)

    /// Everything a view has, which is what a animation applies to unless it says
    /// otherwise.
    public static let all = AnimationValues(rawValue: ~0)
}
