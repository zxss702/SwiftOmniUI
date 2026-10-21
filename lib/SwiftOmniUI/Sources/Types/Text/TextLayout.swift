// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// Where the host laid a text's lines, runs and glyphs out, said back through
// `Text.LayoutKey` the way `.preference` reports anything else. The host's own
// typesetter - TextKit, Pango - fills the report after it lays the label out;
// a `Text.Layout` reads it lazily, so the value can be written with the
// element and answered once the words are placed.
// Design: docs/design/host/tree.md#runs-of-words

/// The rectangle a line, a run or a slice of one stands in, in the text's own
/// coordinates - its top left corner the origin.
public struct TypographicBounds: Equatable, Sendable {
    /// The rectangle.
    public let rect: Rect

    /// Bounds standing at `rect`.
    public init(rect: Rect) {
        self.rect = rect
    }
}

/// A property `.customAttribute` puts on a text, read back off a laid-out
/// run through `Text.Layout`'s subscript - the channel a payload that must
/// survive typesetting travels by:
///
///     struct MappingsAttribute: TextAttribute {
///         let mappings: [Int: Range<Int>]
///     }
///
///     Text(body).customAttribute(MappingsAttribute(mappings: map))
///     // later, inside .backgroundPreferenceValue(Text.LayoutKey.self):
///     for run in line {
///         if let kept = run[MappingsAttribute.self] { … }
///     }
///
/// A value of the attribute's own type answers, as SwiftUI's does; attributes
/// ride the text itself, not the wire - the host lays words out and the core
/// puts them back on the runs they were written on.
public protocol TextAttribute {
    /// What a run's subscript answers - the attribute itself by default.
    associatedtype Value = Self

    /// What a run's subscript answers.
    var attributeValue: Value { get }
}

extension TextAttribute where Value == Self {
    /// The attribute as its own value.
    public var attributeValue: Self { self }
}

extension Text {
    /// One text as the host laid it out: the lines its words stand on, each
    /// line's runs, each run's glyph slices, all in the text's own
    /// coordinates. Written for the subtree to collect through
    /// `Text.LayoutKey`:
    ///
    ///     content.backgroundPreferenceValue(Text.LayoutKey.self) { layouts in
    ///         GeometryReader { proxy in …read layouts[0]… }
    ///     }
    ///
    /// A `Layout` answers empty until the host's first layout lands, then
    /// reads live - the same instance keeps answering what the words do, so a
    /// preference written once stays current.
    public struct Layout: Equatable, RandomAccessCollection, @unchecked Sendable {
        public typealias TypographicBounds = SwiftOmniUICore.TypographicBounds
        /// The report the host last handed over, shared by the seed that
        /// offered this layout and the handler that hears the host.
        let box: TextLayoutBox

        /// The report's generation as this layout was folded - what the
        /// preference's answers compare by, so a new report folds to an
        /// answer the old one is not.
        let version: Int

        /// Where the text's top left corner stands, resolved against a
        /// `GeometryProxy` like any anchor - what `LayoutProxy.origin`
        /// answers in SwiftUI:
        ///
        ///     for layout in layouts {
        ///         let origin = geometry[layout.origin]
        ///     }
        public let origin: Anchor<Point>

        /// SwiftUI-compatible proxy access without re-typesetting the text.
        public var layout: Layout { self }

        /// A layout reading `box`, at its generation now.
        init(box: TextLayoutBox, anchorBox: AnchorBox) {
            self.box = box
            version = box.version
            origin = Anchor<Point>(box: anchorBox) { frame, reader in
                Point(frame.x - reader.x, frame.y - reader.y)
            }
        }

        /// One line of the laid-out text.
        public struct Line: RandomAccessCollection, Sendable {
            /// Where the line stands.
            public let typographicBounds: TypographicBounds

            /// Its runs.
            let runs: [Run]

            /// Where the first run stands.
            public var startIndex: Int { runs.startIndex }

            /// Just past the last run.
            public var endIndex: Int { runs.endIndex }

            /// The run at `position`.
            public subscript(position: Int) -> Run { runs[position] }
        }

        /// One run of the laid-out text - a stretch of one look and one
        /// direction, as the typesetter cut it.
        public struct Run: RandomAccessCollection, @unchecked Sendable {
            /// Where the run stands.
            public let typographicBounds: TypographicBounds

            /// Which way the run's words read.
            public let layoutDirection: LayoutDirection

            /// Its glyph slices - one per laid-out cluster.
            let slices: [RunSlice]

            /// The attributes the text carried, put back on the run.
            var attributes: [ObjectIdentifier: Any] = [:]

            /// Where the first slice stands.
            public var startIndex: Int { slices.startIndex }

            /// Just past the last slice.
            public var endIndex: Int { slices.endIndex }

            /// The slice at `position`.
            public subscript(position: Int) -> RunSlice { slices[position] }

            /// The attribute of `type` this text was given, or none.
            ///
            ///     if let kept = run[MappingsAttribute.self] { … }
            ///
            /// - Parameter type: which `.customAttribute` to answer.
            public subscript<A: TextAttribute>(type: A.Type) -> A.Value? {
                (attributes[ObjectIdentifier(type)] as? A)?.attributeValue
            }
        }

        /// One laid-out glyph cluster of a run.
        public struct RunSlice: Equatable, Sendable {
            /// Where the slice stands.
            public let typographicBounds: TypographicBounds
            /// The source grapheme, when the native typesetter reports it.
            public let text: String?

            public init(typographicBounds: TypographicBounds, text: String? = nil) {
                self.typographicBounds = typographicBounds
                self.text = text
            }
        }

        /// Where the first line stands.
        public var startIndex: Int { box.lines.startIndex }

        /// Just past the last line.
        public var endIndex: Int { box.lines.endIndex }

        /// The line at `position`.
        public subscript(position: Int) -> Line { box.lines[position] }

        /// Two layouts agree when they were folded of the same report's
        /// generation - the box standing behind them reads live either way.
        public static func == (lhs: Layout, rhs: Layout) -> Bool {
            lhs.box.identity === rhs.box.identity && lhs.version == rhs.version
        }
    }

    /// What a `Text` writes for its ancestors: the host's answer to how it
    /// laid the words out, collected as every `Text.Layout` the subtree
    /// offers, in written order.
    public typealias LayoutProxy = Layout

    public struct LayoutKey: PreferenceKey {
        /// A subtree that wrote nothing answers no layouts.
        public static var defaultValue: [LayoutProxy] { [] }

        /// Every text's layouts join the answer, in written order.
        public static func reduce(value: inout [LayoutProxy], nextValue: () -> [LayoutProxy]) {
            value.append(contentsOf: nextValue())
        }
    }
}

/// The report a `Text.Layout` reads, filled by the handler that hears the
/// host's `textLayoutChanged`. Shared by reference: the seed's layout and the
/// handler's writes are the same box.
fileprivate final class TextLayoutIdentity {}

final class TextLayoutBox: @unchecked Sendable {
    /// Stable across a Text value rebuilding, distinct between sibling labels.
    fileprivate var identity = TextLayoutIdentity()
    /// The lines the host last said the text stands on.
    var lines: [Text.Layout.Line] = []

    /// Which report `lines` are of, bumped at every `fill` - a `Layout`
    /// folded of it answers the generation it saw.
    var version = 0

    /// The attributes `.customAttribute` wrote on the text, put back on every
    /// reported run when a report lands.
    var attributes: [ObjectIdentifier: Any] = [:]

    /// Takes over the report `other` answered for - a text rebuilt under one
    /// element keeps saying where its words stand until the host says again.
    /// The attributes are the new node's own and stay.
    func inherit(from other: TextLayoutBox) {
        identity = other.identity
        lines = other.lines.map { line in
            Text.Layout.Line(typographicBounds: line.typographicBounds, runs: line.runs.map { run in
                var run = run
                run.attributes = attributes
                return run
            })
        }
        version = other.version
    }
}
