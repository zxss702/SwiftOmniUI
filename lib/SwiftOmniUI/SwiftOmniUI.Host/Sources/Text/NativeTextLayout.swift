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
            // Keep source order inside directional runs; slices retain the native
            // grapheme boundaries. A run per glyph would multiply wire payload
            // and preference-copy costs for long paragraphs.
            var runs: [TextLayoutReport.Run] = []
            var current: [Glyph] = []
            func flush() {
                guard let first = current.first else { return }
                let bounds = current.dropFirst().reduce(first.rect) { union($0, $1.rect) }
                let visible = current.filter { !$0.text.allSatisfy(\.isNewline) }
                runs.append(TextLayoutReport.Run(rect: bounds, direction: first.direction, span: -1,
                                                 slices: visible.map(\.rect), sliceTexts: visible.map(\.text)))
                current.removeAll(keepingCapacity: true)
            }
            for glyph in glyphs {
                if let previous = current.last, previous.direction != glyph.direction { flush() }
                current.append(glyph)
            }
            flush()
            return TextLayoutReport.Line(rect: rect, runs: runs)
        })
    }

    public static func union(_ lhs: Rect, _ rhs: Rect) -> Rect {
        let x = min(lhs.x, rhs.x), y = min(lhs.y, rhs.y)
        return Rect(x, y, max(lhs.x + lhs.width, rhs.x + rhs.width) - x,
                    max(lhs.y + lhs.height, rhs.y + rhs.height) - y)
    }
}
