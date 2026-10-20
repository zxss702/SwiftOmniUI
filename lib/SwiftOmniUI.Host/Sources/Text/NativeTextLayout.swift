// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore

/// Native character geometry shared by Pango and XAML. Rectangles come from
/// the actual allocated label, never from a second approximate typesetter.
@_spi(Host) public enum NativeTextLayout {
    public struct Glyph {
        public let text: String
        public let rect: Rect
        public let line: Int
        public let direction: LayoutDirection
        public init(text: String, rect: Rect, line: Int, direction: LayoutDirection = .leftToRight) {
            self.text = text; self.rect = rect; self.line = line; self.direction = direction
        }
    }

    public static func report(_ glyphs: [Glyph]) -> TextLayoutReport {
        let groups = Dictionary(grouping: glyphs, by: \.line)
        return TextLayoutReport(lines: groups.keys.sorted().compactMap { key in
            guard let glyphs = groups[key], let first = glyphs.first else { return nil }
            let rect = glyphs.dropFirst().reduce(first.rect) { union($0, $1.rect) }
            // Preserve logical order, including mixed-direction text. One native
            // grapheme per run avoids assuming that visual and source order agree.
            return TextLayoutReport.Line(rect: rect, runs: glyphs.map {
                TextLayoutReport.Run(rect: $0.rect, direction: $0.direction, span: -1,
                                     slices: [$0.rect], sliceTexts: [$0.text])
            })
        })
    }

    public static func union(_ lhs: Rect, _ rhs: Rect) -> Rect {
        let x = min(lhs.x, rhs.x), y = min(lhs.y, rhs.y)
        return Rect(x, y, max(lhs.x + lhs.width, rhs.x + rhs.width) - x,
                    max(lhs.y + lhs.height, rhs.y + rhs.height) - y)
    }
}
