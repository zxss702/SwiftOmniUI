// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The logical control styles `.buttonStyle`, `.textFieldStyle`, `.pickerStyle`
// and `.listStyle` name - what the control IS, each host draws with its own
// means.
// Design: docs/design/types/vocabularies.md#written-out-and-appended

/// How a button presents: the platform's ordinary chrome, none at all, or one
/// of the weights a platform gives a button. The `buttonStyle` member's value.
public enum ButtonStyleKind: Int32, Sendable {
    /// What the platform calls ordinary - the default.
    case automatic = 0

    /// The platform's bordered button.
    case bordered = 1

    /// The platform's accented, filled button - the one a main action wears.
    case borderedProminent = 2

    /// Caption only, no edge - kept clickable.
    case borderless = 3

    /// No chrome at all: the caption and its action, nothing more.
    case plain = 4

    /// Drawn as a link: underlined or tinted as the platform links.
    case link = 5
}

/// How a text field's box presents. The `textFieldStyle` member's value.
public enum TextFieldStyleKind: Int32, Sendable {
    /// What the platform calls ordinary - the default.
    case automatic = 0

    /// No box: the field's text on the view beneath it.
    case plain = 1

    /// The platform's rounded box.
    case roundedBorder = 2

    /// The platform's square-edged box.
    case squareBorder = 3
}

/// How a picker presents its choices. The `pickerStyle` member's value.
public enum PickerStyleKind: Int32, Sendable {
    /// What the platform calls ordinary - the default.
    case automatic = 0

    /// A menu popping up its choices.
    case menu = 1

    /// A column of radio buttons.
    case radioGroup = 2

    /// A row of segments, one per choice.
    case segmented = 3

    /// A wheel of choices.
    case wheel = 4

    /// The choices shown inline, every one visible.
    case inline = 5
}

/// How a list presents its rows. The `listStyle` member's value.
public enum ListStyleKind: Int32, Sendable {
    /// What the platform calls ordinary - the default.
    case automatic = 0

    /// Plain rows, no grouping chrome.
    case plain = 1

    /// The look a source list wears: the platform's sidebar rows.
    case sidebar = 2
}

/// The `.buttonStyle` for a branch: which of the logical kinds the buttons
/// under it take, unless a nearer write or the button's own says otherwise.
public final class ButtonStyle: @unchecked Sendable {
    /// The kind named.
    let kind: ButtonStyleKind

    private init(_ kind: ButtonStyleKind) { self.kind = kind }

    /// What the platform calls ordinary.
    public static let automatic = ButtonStyle(.automatic)

    /// The platform's bordered button.
    public static let bordered = ButtonStyle(.bordered)

    /// The platform's accented, filled button.
    public static let borderedProminent = ButtonStyle(.borderedProminent)

    /// Caption only, no edge.
    public static let borderless = ButtonStyle(.borderless)

    /// No chrome at all.
    public static let plain = ButtonStyle(.plain)

    /// Drawn as a link.
    public static let link = ButtonStyle(.link)
}

/// The `.textFieldStyle` for a branch.
public final class TextFieldStyle: @unchecked Sendable {
    /// The kind named.
    let kind: TextFieldStyleKind

    private init(_ kind: TextFieldStyleKind) { self.kind = kind }

    /// What the platform calls ordinary.
    public static let automatic = TextFieldStyle(.automatic)

    /// No box.
    public static let plain = TextFieldStyle(.plain)

    /// The platform's rounded box.
    public static let roundedBorder = TextFieldStyle(.roundedBorder)

    /// The platform's square-edged box.
    public static let squareBorder = TextFieldStyle(.squareBorder)
}

/// The `.pickerStyle` for a branch.
public final class PickerStyle: @unchecked Sendable {
    /// The kind named.
    let kind: PickerStyleKind

    private init(_ kind: PickerStyleKind) { self.kind = kind }

    /// What the platform calls ordinary.
    public static let automatic = PickerStyle(.automatic)

    /// A menu popping up its choices.
    public static let menu = PickerStyle(.menu)

    /// A column of radio buttons.
    public static let radioGroup = PickerStyle(.radioGroup)

    /// A row of segments.
    public static let segmented = PickerStyle(.segmented)

    /// A wheel of choices.
    public static let wheel = PickerStyle(.wheel)

    /// Every choice visible inline.
    public static let inline = PickerStyle(.inline)
}

extension ButtonStyleKind: HostRepresentable {}
extension ButtonStyleKind: StateChoice {}
extension TextFieldStyleKind: HostRepresentable {}
extension TextFieldStyleKind: StateChoice {}
extension PickerStyleKind: HostRepresentable {}
extension PickerStyleKind: StateChoice {}
extension ListStyleKind: HostRepresentable {}
extension ListStyleKind: StateChoice {}

/// The `.listStyle` for a branch.
public final class ListStyle: @unchecked Sendable {
    /// The kind named.
    let kind: ListStyleKind

    private init(_ kind: ListStyleKind) { self.kind = kind }

    /// What the platform calls ordinary.
    public static let automatic = ListStyle(.automatic)

    /// Plain rows.
    public static let plain = ListStyle(.plain)

    /// The platform's sidebar rows.
    public static let sidebar = ListStyle(.sidebar)
}
