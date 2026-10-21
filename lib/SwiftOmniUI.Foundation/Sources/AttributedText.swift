// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// `Text(AttributedString)`: an attributed string shown as runs, each run's
// look mapped onto a span. SwiftOmniUI's text already draws runs; the
// `AttributedString` it cannot name - Foundation's - is converted here.
//
// Attributes read: the portable `TextRunStyle` - foreground colour, font
// attributes, underline and strikethrough, letter shape. A run carrying none
// renders as plain text.

import Foundation
@_spi(Host) import SwiftOmniUICore

/// Extra run styling for `AttributedString`s - the portable spelling of what a
/// markdown string's `inlinePresentationIntent` says where Foundation ships it.
/// `Text(_:)` applies it to the run's span.
public struct TextRunStyle: Hashable, Sendable {
    /// Bold, italic, or both.
    public var fontAttributes: FontAttributes
    /// Underline, strikethrough, or both.
    public var decorations: TextDecorations
    /// The letter shape - `.monospaced` for inline code.
    public var design: FontDesign?
    /// The run's colour.
    public var foreground: Color?

    public init(
        fontAttributes: FontAttributes = [],
        decorations: TextDecorations = [],
        design: FontDesign? = nil,
        foreground: Color? = nil
    ) {
        self.fontAttributes = fontAttributes
        self.decorations = decorations
        self.design = design
        self.foreground = foreground
    }
}

/// The `AttributedString` key a `TextRunStyle` travels by.
public enum TextRunStyleAttributeKey: AttributedStringKey {
    public typealias Value = TextRunStyle
    public static let name = "SwiftOmniUI.TextRunStyle"
}

/// The same foreground-colour attribute spelling used by SwiftUI's text.
public enum ForegroundColorAttribute: AttributedStringKey {
    public typealias Value = Color
    public static let name = "SwiftOmniUI.ForegroundColor"
}
public extension AttributeScopes {
    struct SwiftOmniUIAttributes: AttributeScope {
        public let foregroundColor: ForegroundColorAttribute
    }
    var swiftOmniUI: SwiftOmniUIAttributes.Type { SwiftOmniUIAttributes.self }
}
public extension AttributeDynamicLookup {
    subscript<T: AttributedStringKey>(dynamicMember keyPath: KeyPath<AttributeScopes.SwiftOmniUIAttributes, T>) -> T {
        self[T.self]
    }
}

extension Text {
    /// Text showing an attributed string's runs, each keeping its own look.
    ///
    /// Disfavoured so a string literal keeps meaning the localized key -
    /// `AttributedString` spells itself out of literals too.
    @_disfavoredOverload
    public init(_ attributed: AttributedString) {
        self = Text().spans {
            let runs = Array(attributed.runs)

            ForEach(0..<runs.count) { index in
                let run = runs[index]
                TextSpan(String(attributed[run.range].characters))
                    .styled(with: run)
            }
        }
    }
}

extension TextSpan {
    /// One attributed run's look, as span modifiers.
    fileprivate func styled(with run: AttributedString.Runs.Run) -> TextSpan {
        var span = self

        // The portable channel - read on every platform.
        if let style = run.attributes[TextRunStyleAttributeKey.self] {
            if style.fontAttributes.contains(.bold) { span = span.bold() }
            if style.fontAttributes.contains(.italic) { span = span.italic() }
            if style.decorations.contains(.underline) { span = span.underline() }
            if style.decorations.contains(.strikethrough) { span = span.strikethrough() }
            if let design = style.design { span = span.fontDesign(design) }
            if let color = style.foreground { span = span.foregroundStyle(color) }
        }

        if let color = run.attributes[ForegroundColorAttribute.self] { span = span.foregroundStyle(color) }
        return span
    }
}

