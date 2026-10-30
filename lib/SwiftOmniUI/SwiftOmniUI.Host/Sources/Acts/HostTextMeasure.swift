// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore

/// What a canvas's `measureText` act asks - the words, the font decomposed the way `FontElementContract`'s
/// members carry it, and the width the words wrap at - which every host reads the same and measures with its
/// own text engine.
/// Design: docs/design/host/runtime.md#acts
@_spi(Host) public struct HostTextMeasure: Equatable, Sendable {
    /// The words to measure.
    public let text: String

    /// The font to measure them in, as a look carrying the font's members only - its text style, size, family,
    /// weight, letter shape and attributes.
    public let font: TextLook

    /// The width the words wrap at; nil for each paragraph one line.
    public let maximumWidth: Double?

    /// What `call` asks; nil for an act that is no `measureText`.
    public init?(_ call: HostActCall) {
        guard call.act == .measureText, let text = call.arguments.value(1)?.string else { return nil }
        self.text = text
        var look = TextLook()
        look.textStyle = call.arguments.value(2).flatMap(FontTextStyle.init(propValue:))
        look.size = call.arguments.value(3)?.number
        look.family = call.arguments.value(4)?.name
        look.weight = call.arguments.value(5)?.number
        look.design = call.arguments.value(6).flatMap(FontDesign.init(propValue:))
        look.attributes = call.arguments.value(7)?.enumeration.map { FontAttributes(rawValue: $0) } ?? .none
        font = look
        maximumWidth = call.arguments.value(8)?.number
    }
}
