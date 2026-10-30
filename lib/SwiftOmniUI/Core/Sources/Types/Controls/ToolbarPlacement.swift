// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// A bit set, numbered by SwiftOmniUI: append a member, never insert one.
// Design: docs/design/types/vocabularies.md#written-out-and-appended

/// Which toolbars a toolbar modifier speaks to - what `.toolbarVisibility`
/// and `.toolbarBackground` take in `for:`.
public struct ToolbarPlacement: OptionSet, Equatable, Sendable {
    /// The set as its members' bits, which is what an OptionSet is made of.
    public var rawValue: Int32

    /// A set from its members' bits.
    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    /// Whichever bars the platform shows - the default.
    public static let automatic = ToolbarPlacement(rawValue: ~0)

    /// The bar a navigation stack's pages carry.
    public static let navigationBar = ToolbarPlacement(rawValue: 1 << 0)

    /// The bar a tabbed view carries.
    public static let tabBar = ToolbarPlacement(rawValue: 1 << 1)

    /// The bar a window carries, where the platform has one - macOS's title-bar
    /// toolbar, a toolbar row on Windows and Linux.
    public static let windowToolbar = ToolbarPlacement(rawValue: 1 << 2)

    /// The bar at the bottom of a page, where the platform has one.
    public static let bottomBar = ToolbarPlacement(rawValue: 1 << 3)

    /// The platform's status area, where it has one.
    public static let statusBar = ToolbarPlacement(rawValue: 1 << 4)
}

/// Which container a container-background modifier speaks to - what
/// `.containerBackground(for:)` takes.
public struct ContainerBackgroundPlacement: Sendable {
    /// The window a view's scene stands in.
    public static let window = ContainerBackgroundPlacement()

    /// The placement, made where a platform asks for one by name.
    private init() {}
}

// A closed vocabulary, numbered by SwiftOmniUI: append a case, never insert one.

/// How a window settles its size against its content - what
/// `.windowResizability` takes.
public enum WindowResizability: Int32, Sendable {
    /// The platform's ordinary sizing - the default.
    case automatic = 0

    /// The window can shrink no smaller than its content asks to be, but may
    /// grow past it.
    case contentMinSize = 1

    /// The window takes the size its content asks for, and no other - the
    /// content dictates width and height, and the user may not resize it.
    case contentSize = 2
}

extension WindowResizability: HostRepresentable {}
extension WindowResizability: StateChoice {}
