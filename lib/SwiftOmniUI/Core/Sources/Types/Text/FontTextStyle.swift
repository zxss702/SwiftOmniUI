// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// A closed vocabulary, numbered by SwiftOmniUI: append a case, never insert one.
// Design: docs/design/types/vocabularies.md#written-out-and-appended

/// One of the platform's named text styles - what `Font.title`, `.body` and
/// the rest stand for. The host turns it into the platform's own style, so
/// the same word means the platform's size on every platform.
///
///     Text("Chapter").font(.title)
public enum FontTextStyle: Int32, Sendable {
    /// The platform's largest style.
    case largeTitle = 0

    /// A page's title.
    case title = 1

    /// A section's title.
    case title2 = 2

    /// A subsection's title.
    case title3 = 3

    /// A heading above ordinary text.
    case headline = 4

    /// A heading lighter than `headline`.
    case subheadline = 5

    /// Ordinary reading text.
    case body = 6

    /// Text a step under a heading.
    case callout = 7

    /// Footnotes and captions' companion.
    case footnote = 8

    /// Captions and small labels.
    case caption = 9

    /// The smaller caption.
    case caption2 = 10
}

extension FontTextStyle: HostRepresentable {}
extension FontTextStyle: StateChoice {}

// A closed vocabulary, numbered by SwiftOmniUI: append a case, never insert one.

/// How the system's font is drawn - the shape of its letters.
///
///     Text("Code").font(.system(size: 13, design: .monospaced))
public enum FontDesign: Int32, Sendable {
    /// As the platform draws text by default.
    case `default` = 0

    /// Serifs on the letters.
    case serif = 1

    /// Rounded terminals.
    case rounded = 2

    /// Every glyph the same width.
    case monospaced = 3
}

extension FontDesign: HostRepresentable {}
extension FontDesign: StateChoice {}
