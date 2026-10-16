// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// A keyboard shortcut: a key and the modifiers held with it.

/// One key, as the press that fires a shortcut: a character, or a named key a
/// character cannot write.
public struct KeyEquivalent: Equatable, Sendable, ExpressibleByStringLiteral {
    /// The key's name: one character, or a word for a key with none -
    /// "return", "escape", "tab", "space", "delete", arrows as "up", "down",
    /// "left" and "right", the function keys as "f1" and so on.
    public let name: String

    /// The key a character names.
    public init(_ character: Character) { name = String(character).lowercased() }

    /// A key by name, for the keys a character cannot write.
    public init(stringLiteral value: String) { name = value.lowercased() }

    /// The Return key.
    public static let `return` = KeyEquivalent("return")
    /// The Escape key.
    public static let escape = KeyEquivalent("escape")
    /// The Tab key.
    public static let tab = KeyEquivalent("tab")
    /// The space bar.
    public static let space = KeyEquivalent("space")
    /// The delete-backwards key.
    public static let delete = KeyEquivalent("delete")
    /// The delete-forwards key.
    public static let deleteForward = KeyEquivalent("deleteforward")
    /// The up arrow.
    public static let upArrow = KeyEquivalent("up")
    /// The down arrow.
    public static let downArrow = KeyEquivalent("down")
    /// The left arrow.
    public static let leftArrow = KeyEquivalent("left")
    /// The right arrow.
    public static let rightArrow = KeyEquivalent("right")
    /// The Home key.
    public static let home = KeyEquivalent("home")
    /// The End key.
    public static let end = KeyEquivalent("end")
    /// The Page Up key.
    public static let pageUp = KeyEquivalent("pageup")
    /// The Page Down key.
    public static let pageDown = KeyEquivalent("pagedown")

    /// The platform's accept key - Return, as the default button's shortcut.
    public static let defaultAction = KeyEquivalent("defaultaction")
    /// The platform's cancel key - Escape, as the cancel button's.
    public static let cancelAction = KeyEquivalent("cancelaction")
}

/// The modifier keys held with a key: `.command` by default, as shortcuts
/// most often are.
public struct EventModifiers: OptionSet, Equatable, Sendable {
    /// The bits, as the wire holds them.
    public let rawValue: Int32

    /// A set from its bits.
    public init(rawValue: Int32) { self.rawValue = rawValue }

    /// The platform's command key - Command on macOS, Control elsewhere.
    public static let command = EventModifiers(rawValue: 1 << 0)
    /// The Shift key.
    public static let shift = EventModifiers(rawValue: 1 << 1)
    /// The Option key - Alt elsewhere.
    public static let option = EventModifiers(rawValue: 1 << 2)
    #if !os(Windows) && !os(Linux)
    /// The physical Control key, distinct from Command on Apple platforms.
    /// Windows and Linux use `.command` for their Control shortcuts.
    public static let control = EventModifiers(rawValue: 1 << 3)
    #endif
}

/// A key pressed with modifiers: `.keyboardShortcut(.return)` is Cmd-Return
/// on macOS, the platform's own command key elsewhere.
public struct KeyboardShortcut: Equatable, Sendable {
    /// The key.
    public let key: KeyEquivalent

    /// The modifiers held with it.
    public let modifiers: EventModifiers

    /// A shortcut for a key, `modifiers` the platform's command key where none are said.
    ///
    ///     .keyboardShortcut(.return)
    ///     .keyboardShortcut("s", modifiers: [.command, .shift])
    public init(_ key: KeyEquivalent, modifiers: EventModifiers = .command) {
        self.key = key
        self.modifiers = modifiers
    }
}

extension KeyEquivalent: HostRepresentable {
    /// The key's name, as the wire holds it.
    public var propValue: PropValue { .name(name) }

    /// The key the name stands for, where a name arrived.
    public init?(propValue: PropValue) {
        guard let name = propValue.name else { return nil }
        self.name = name
    }
}

extension EventModifiers: HostRepresentable {
    /// The modifiers' bits, as the wire holds them.
    public var propValue: PropValue { .enumeration(rawValue) }

    /// The set the bits stand for, where bits arrived.
    public init?(propValue: PropValue) {
        guard let rawValue = propValue.enumeration else { return nil }
        self.init(rawValue: rawValue)
    }
}

extension KeyboardShortcut: HostRepresentable {
    /// The key and the modifiers, as the wire holds them.
    public var propValue: PropValue { .values([key.propValue, modifiers.propValue]) }

    /// Both parts read back, or nothing where they did not arrive.
    public init?(propValue: PropValue) {
        guard let parts = propValue.values, parts.count == 2,
              let key = KeyEquivalent(propValue: parts[0]),
              let modifiers = EventModifiers(propValue: parts[1])
        else { return nil }
        self.init(key, modifiers: modifiers)
    }
}

extension KeyboardShortcut: StateValue {
    /// The modifiers' bits, then the key's name.
    public var carried: StateCarried { .text("\(modifiers.rawValue):\(key.name)") }

    /// Both halves read back, or nothing where the text is not one.
    public init?(carried: StateCarried) {
        guard case .text(let text) = carried,
              let cut = text.firstIndex(of: ":"),
              let bits = Int32(text[text.startIndex..<cut])
        else { return nil }
        self.init(KeyEquivalent(stringLiteral: String(text[text.index(after: cut)...])),
                  modifiers: EventModifiers(rawValue: bits))
    }

    /// None: a shortcut is bound or it is not.
    public static var lanes: Int { 0 }
}
