// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// How a text lets the user select it - what `.textSelection(_:)` takes.
public protocol TextSelectability: Sendable {
    /// Whether text so marked can be selected.
    var isSelectable: Bool { get }
}

/// Text can be selected: the user drags a range out of it and copies it.
public struct EnabledTextSelectability: TextSelectability {
    /// The value: yes.
    public var isSelectable: Bool { true }

    /// The selection policy text starts with nothing under.
    public init() {}
}

/// Text cannot be selected.
public struct DisabledTextSelectability: TextSelectability {
    /// The value: no.
    public var isSelectable: Bool { false }

    /// The policy.
    public init() {}
}

extension TextSelectability where Self == EnabledTextSelectability {
    /// Text can be selected.
    public static var enabled: EnabledTextSelectability { EnabledTextSelectability() }
}

extension TextSelectability where Self == DisabledTextSelectability {
    /// Text cannot be selected.
    public static var disabled: DisabledTextSelectability { DisabledTextSelectability() }
}
