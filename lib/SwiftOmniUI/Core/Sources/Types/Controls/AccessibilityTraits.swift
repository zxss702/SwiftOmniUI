// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// A bit set, numbered by SwiftOmniUI: append a member, never insert one.
// Design: docs/design/types/vocabularies.md#written-out-and-appended

/// What an accessibility element is and does - what `.accessibilityAddTraits`
/// adds and `.accessibilityRemoveTraits` takes away.
///
/// A user who cannot see the page meets elements by their traits: a thing
/// that reads as a button invites a press, one marked selected speaks its
/// state, and a header lets them move by sections.
public struct AccessibilityTraits: OptionSet, Equatable, Sendable {
    /// The set as its members' bits, which is what an OptionSet is made of.
    public var rawValue: Int32

    /// A set from its members' bits.
    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    /// The element does something when acted on.
    public static let isButton = AccessibilityTraits(rawValue: 1 << 0)

    /// The element is a heading - see `.accessibilityHeadingLevel` for its depth.
    public static let isHeader = AccessibilityTraits(rawValue: 1 << 1)

    /// The element is in a chosen state, as a sidebar's current row is.
    public static let isSelected = AccessibilityTraits(rawValue: 1 << 2)

    /// The element opens a link somewhere else.
    public static let isLink = AccessibilityTraits(rawValue: 1 << 3)

    /// The element is a text field or search field.
    public static let isSearchField = AccessibilityTraits(rawValue: 1 << 4)

    /// The element shows a picture.
    public static let isImage = AccessibilityTraits(rawValue: 1 << 5)

    /// The element plays sound or video.
    public static let playsSound = AccessibilityTraits(rawValue: 1 << 6)

    /// The element acts as the keyboard's focus lands in it.
    public static let isKeyboardKey = AccessibilityTraits(rawValue: 1 << 7)

    /// The element is unchanging text.
    public static let isStaticText = AccessibilityTraits(rawValue: 1 << 8)

    /// The element speaks often-changing content - a live region.
    public static let updatesFrequently = AccessibilityTraits(rawValue: 1 << 9)

    /// Acting on the element opens a modal that must be dealt with first.
    public static let startsMediaSession = AccessibilityTraits(rawValue: 1 << 10)

    /// The element can be adjusted - a slider or stepper.
    public static let adjustable = AccessibilityTraits(rawValue: 1 << 11)

    /// Acting on the element leaves the current content.
    public static let causesPageTurn = AccessibilityTraits(rawValue: 1 << 12)

    /// The element is on, as a checked toggle is.
    public static let isToggle = AccessibilityTraits(rawValue: 1 << 13)
}

extension AccessibilityTraits: HostRepresentable {}

// A closed vocabulary, numbered by SwiftOmniUI: append a case, never insert one.

/// How an element's children take part in accessibility - what
/// `.accessibilityElement(children:)` sets.
public enum AccessibilityChildBehavior: Int32, Sendable {
    /// The element and its children each stand on their own - the default.
    case contain = 0

    /// The element's children are ignored: the element is all there is.
    case ignore = 1

    /// The element's children are merged into it, speaking as one.
    case combine = 2
}

extension AccessibilityChildBehavior: HostRepresentable {}
extension AccessibilityChildBehavior: StateChoice {}
