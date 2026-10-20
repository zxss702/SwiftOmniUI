// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// A text's layout as the host reports it: lines, runs and glyph slices as
// rectangles, with each run's reading direction and which of the text's own
/// runs it came from - the shape `textLayoutChanged` carries across, decoded
/// into a `Text.Layout` on this side.
// Design: docs/design/host/tree.md#runs-of-words

/// Where the host's typesetter left a text's words: its lines top to bottom,
/// each run's rectangle and direction, each glyph's slice - every rectangle
/// in the element's own coordinates.
public struct TextLayoutReport: Equatable, Sendable {
    /// One laid-out line.
    public struct Line: Equatable, Sendable {
        /// Where the line stands.
        public let rect: Rect

        /// Its runs, laid out in order.
        public let runs: [Run]

        /// A line of `rect` standing on `runs`.
        public init(rect: Rect, runs: [Run]) {
            self.rect = rect
            self.runs = runs
        }
    }

    /// One laid-out run - a stretch the typesetter kept together.
    public struct Run: Equatable, Sendable {
        /// Where the run stands.
        public let rect: Rect

        /// Which way the run's words read.
        public let direction: LayoutDirection

        /// Which of the element's own span runs this run lays out - the
        /// span's index, -1 for words that are no span's.
        public let span: Int

        /// The run's glyph slices - each cluster's rectangle.
        public let slices: [Rect]

        /// Graphemes occupying the corresponding native selection rectangles.
        public let sliceTexts: [String]

        /// A run of `rect`, reading `direction`, laying out `span`, its glyphs
        /// at `slices`.
        public init(rect: Rect, direction: LayoutDirection, span: Int, slices: [Rect], sliceTexts: [String] = []) {
            self.rect = rect
            self.direction = direction
            self.span = span
            self.slices = slices
            self.sliceTexts = sliceTexts
        }
    }

    /// The lines, top to bottom.
    public let lines: [Line]

    /// A report of `lines`.
    public init(lines: [Line]) {
        self.lines = lines
    }

    /// A line of `rect` standing on `runs`.
    public init(line rect: Rect, runs: [Run]) {
        lines = [Line(rect: rect, runs: runs)]
    }
}

extension TextLayoutReport: HostRepresentable {
    /// The report crosses as nested values: lines of rect and runs, a run of
    /// rect, direction, span and slice rects.
    public var propValue: PropValue {
        .values(lines.map { line in
            .values([
                line.rect.propValue,
                .values(line.runs.map { run in
                    .values([
                        run.rect.propValue,
                        .number(Double(run.direction.rawValue)),
                        .number(Double(run.span)),
                        .values(run.slices.map(\.propValue)),
                        .strings(run.sliceTexts),
                    ])
                }),
            ])
        })
    }

    /// The report back, or nil where the values say another shape.
    /// - Parameter propValue: what the host sent.
    public init?(propValue: PropValue) {
        guard let lineValues = propValue.values else { return nil }
        var lines: [Line] = []
        for lineValue in lineValues {
            guard let parts = lineValue.values, parts.count == 2,
                  let rect = Rect(propValue: parts[0]),
                  let runValues = parts[1].values else { return nil }

            var runs: [Run] = []
            for runValue in runValues {
                guard let runParts = runValue.values, runParts.count >= 4,
                      let runRect = Rect(propValue: runParts[0]),
                      let rawDirection = runParts[1].number,
                      let direction = LayoutDirection(rawValue: Int32(rawDirection)),
                      let span = runParts[2].number,
                      let sliceValues = runParts[3].values else { return nil }

                var slices: [Rect] = []
                for sliceValue in sliceValues {
                    guard let slice = Rect(propValue: sliceValue) else { return nil }
                    slices.append(slice)
                }
                let texts = runParts.count > 4 ? runParts[4].strings ?? [] : []
                runs.append(Run(rect: runRect, direction: direction, span: Int(span), slices: slices, sliceTexts: texts))
            }
            lines.append(Line(rect: rect, runs: runs))
        }
        self.init(lines: lines)
    }
}
