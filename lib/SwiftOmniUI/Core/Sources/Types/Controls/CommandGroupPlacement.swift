// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// A closed vocabulary, numbered by SwiftOmniUI: append a case, never insert one.
// Design: docs/design/types/vocabularies.md#written-out-and-appended

/// Where in the platform's menus a `CommandGroup` stands - the region its
/// entries belong to, as SwiftUI's `CommandGroupPlacement` names it.
public struct CommandGroupPlacement: Equatable, Sendable {
    /// The region's number, as the wire holds it.
    public let rawValue: Int32

    /// A placement of `rawValue`.
    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    /// The application's own menu: its about entry, preferences and services
    /// on macOS, the app menu's whole region on other platforms.
    public static let appInfo = CommandGroupPlacement(rawValue: 0)

    /// The settings entry's region of the app's menu.
    public static let appSettings = CommandGroupPlacement(rawValue: 1)

    /// The hide-and-show entries' region of the app's menu.
    public static let appVisibility = CommandGroupPlacement(rawValue: 2)

    /// The quit entry's region of the app's menu.
    public static let appTermination = CommandGroupPlacement(rawValue: 3)

    /// The system's own services menu.
    public static let systemServices = CommandGroupPlacement(rawValue: 4)

    /// The new-document entries' region - File's New on a desktop menu bar.
    public static let newItem = CommandGroupPlacement(rawValue: 5)

    /// The save entries' region.
    public static let saveItem = CommandGroupPlacement(rawValue: 6)

    /// The import and export entries' region.
    public static let importExport = CommandGroupPlacement(rawValue: 7)

    /// The print entries' region.
    public static let printItem = CommandGroupPlacement(rawValue: 8)

    /// The undo and redo entries' region of the Edit menu.
    public static let undoRedo = CommandGroupPlacement(rawValue: 9)

    /// The cut, copy and paste entries' region.
    public static let cutCopyPaste = CommandGroupPlacement(rawValue: 10)

    /// The select-all entry's region.
    public static let selectAll = CommandGroupPlacement(rawValue: 11)

    /// The find entries' region.
    public static let find = CommandGroupPlacement(rawValue: 12)

    /// The find-and-replace entries' region.
    public static let findAndReplace = CommandGroupPlacement(rawValue: 13)

    /// The share entries' region.
    public static let share = CommandGroupPlacement(rawValue: 14)

    /// The navigation entries' region - back and forward, where the platform
    /// groups them.
    public static let navigation = CommandGroupPlacement(rawValue: 15)

    /// The sidebar entries' region.
    public static let sidebar = CommandGroupPlacement(rawValue: 16)

    /// The toolbar's own entries' region.
    public static let toolbar = CommandGroupPlacement(rawValue: 17)

    /// The one-window list of an application with a single window.
    public static let singleWindowList = CommandGroupPlacement(rawValue: 18)

    /// The size-and-position entries' region of the windows' menu.
    public static let windowSize = CommandGroupPlacement(rawValue: 19)

    /// The open windows' list at the windows' menu's end.
    public static let windowList = CommandGroupPlacement(rawValue: 20)

    /// The help menu's entries.
    public static let help = CommandGroupPlacement(rawValue: 21)

    /// The text editing entries' region.
    public static let textEditing = CommandGroupPlacement(rawValue: 22)

    /// The text formatting entries' region.
    public static let textFormatting = CommandGroupPlacement(rawValue: 23)
}

extension CommandGroupPlacement: HostRepresentable {
    /// The region's number, as the wire holds it.
    public var propValue: PropValue { .enumeration(rawValue) }

    /// The region of `propValue`'s number, or nothing where it is not one.
    public init?(propValue: PropValue) {
        guard let rawValue = propValue.enumeration else { return nil }
        self.init(rawValue: rawValue)
    }
}
