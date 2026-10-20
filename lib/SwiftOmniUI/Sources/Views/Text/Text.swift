// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// `Text`'s own properties, shared by the control and its `Style<Text>`.
public protocol TextProperties: PropertyContainer {}

extension TextProperties {
    /// What happens to text too long for the space: wrap it, or cut it and say
    /// so.
    @_spi(Host) public func lineBreak(_ value: LineBreak) -> Modified {
        setValue(TextContract.lineBreak, value)
    }

    /// Where a too-long line is cut, the SwiftUI spelling of the truncating
    /// `lineBreak`s.
    public func truncationMode(_ mode: TruncationMode) -> Modified {
        lineBreak(mode.lineBreak)
    }

    /// How many lines to show before the text is cut - what the cut LOOKS like
    /// is `lineBreak`'s business. A count of -1 means no limit, which is
    /// the default.
    public func lineLimit(_ value: Int) -> Modified {
        setValue(TextContract.lineLimit, value)
    }


    /// Whether the user can drag a range out of the text and copy it.
    ///
    ///     Text(output).textSelection(.enabled)
    public func textSelection(_ selectability: some TextSelectability) -> Modified {
        setValue(TextContract.selectable, selectability.isSelectable)
    }

    /// The fraction of its own size the text may shrink to fit the room it
    /// was given before the host cuts it: 0 shrinks it to nothing said, 1
    /// keeps it whole.
    ///
    ///     Text(longName).minimumScaleFactor(0.5)
    public func minimumScaleFactor(_ factor: Double) -> Modified {
        setValue(TextContract.minimumScaleFactor, factor)
    }
}

extension View {
    /// Whether the text inside this view lets the user drag a range out of it
    /// and copy it - a `Text` keeping its own wins over the inherited one.
    ///
    ///     Text(output).textSelection(.enabled)
    @_disfavoredOverload
    public func textSelection(_ selectability: some TextSelectability) -> ModifiedContent {
        revised { $0.writeInherited(TextContract.selectable, selectability.isSelectable) }
    }

    /// The fraction `Text`s inside this view may shrink to before they are
    /// cut - a `Text` keeping its own wins over the inherited one.
    ///
    ///     Text(longName).minimumScaleFactor(0.5)
    @_disfavoredOverload
    public func minimumScaleFactor(_ factor: Double) -> ModifiedContent {
        revised { $0.writeInherited(TextContract.minimumScaleFactor, factor) }
    }
}

/// A read-only piece of text.
///
///     Text("Total")
///         .fontSize(20)
///         .fontAttributes(.bold)
///         .multilineTextAlignment(.center)
public struct Text: VisualElement, TextElement, FontElement, TextAlignmentElement, PaddingElement, LineHeightElement, DecorableTextElement, TextProperties{
    /// The node this control describes.
    public var node: Node

    /// A text's node, wired to answer `Text.LayoutKey`: the seed offers a
    /// `Layout` reading a shared box, the handler fills it when the host says
    /// how the words were laid out.
    private static func wiredNode() -> Node {
        var node = Node(contract: TextContract.self)
        let box = TextLayoutBox()
        node.textLayoutBox = box
        // The text's position feeds `Layout.origin` without treating every
        // text as a business geometry read that suppresses layout animation.
        let anchorBox = AnchorBox()
        node.addHandler(.textFrameChanged) {
            guard let numbers = MemberValues.carried(
                EventBuffer.current, by: "textFrameChanged", as: [Double].self),
                let report = FrameReport(numbers)
            else { return }
            anchorBox.frame = report.global
        }
        // The offer is asked at fold: a text the walk carries answers for the
        // report the host last handed in, not the one its render saw.
        node.preferenceSeeds.append(PreferenceSeed(
            box: PreferenceKeyBox(LayoutKey.self), lazy: { [box, anchorBox] in
                [Layout(box: box, anchorBox: anchorBox)]
            }))
        node.addHandler(TextContract.textLayoutChanged.token) {
            guard let report = MemberValues.carried(
                EventBuffer.current, by: TextContract.textLayoutChanged.name,
                as: TextLayoutReport.self)
            else { return }
            box.fill(report)
            // A host-pushed report is no state's doing: the render it asks
            // for is an untracked one - and only where an ear stands, which
            // is how the folded answers move.
            if DispatchContext.differ?.watchesTextLayout == true {
                Renderer.shared.setNeedsRender()
            }
        }
        return node
    }

    /// An empty one - what a `Style<Text>` is written against.
    public init() {
        node = Self.wiredNode()
    }

    /// A label showing `content`, verbatim - a `String` is never looked up;
    /// the literal that is a key is `Text(_ key:)`, which a literal prefers.
    @_disfavoredOverload public init<S: StringProtocol>(_ content: S) {
        node = Self.wiredNode()
        node.write(TextElementContract.text, String(content))
    }

    /// A label showing what `key` looks up - the SwiftUI spelling, where a
    /// literal is a key and a `String` is verbatim:
    ///
    ///     Text("Save")                    // looked up in the host's tables
    ///     Text("Elapsed: \(s, specifier: "%.2f") s")
    ///
    /// The host answers the key, and `key.displayString` stands written as
    /// `text` for everywhere the tables do not reach.
    public init(_ key: LocalizedStringKey) {
        node = Self.wiredNode()
        node.write(TextElementContract.text, key.displayString)
        node.write(TextElementContract.textKey, key)
    }

    /// A picture inline in text, the only way one stands among words:
    ///
    ///     Text(Image(systemName: "star")) + Text(" marked")
    ///
    /// The run it writes is one glyph at the picture's size, lifted by
    /// `.baselineOffset` the way any run's is.
    public init(_ image: Image) {
        self.init()
        var span = Node(contract: SpanContract.self)
        if let source = image.imageSource {
            span.write(SpanContract.image, source)
        }
        node.children = [Node(contract: SpansContract.self, children: [span])]
    }

    /// A label whose text is carried from a state, written by the host as it
    /// changes, at no render.
    ///
    /// - Parameter text: the state the words are read from.
    public init(_ text: Binding<String>) {
        self = Text().text(text)
    }

    /// Text made of runs, each with a look of its own.
    ///
    ///     Text()
    ///         .spans {
    ///             TextSpan("let ").foregroundStyle(.purple)
    ///             TextSpan("counter").foregroundStyle(.steelBlue)
    ///             TextSpan(" = 0")
    ///         }
    ///
    /// The one way to colour part of a label: text in two colours is two runs.
    /// A `ForEach` builds them, keyed by where each sits, since two tokens may
    /// read the same:
    ///
    ///     Text().spans {
    ///         ForEach(Array(highlighted(code).enumerated()), id: \.offset) { token in
    ///             TextSpan(token.element.text).foregroundStyle(token.element.colour)
    ///         }
    ///     }
    ///
    /// A Text given both runs and a `text` shows the runs.
    @_spi(Host) public func spans(@ViewBuilder _ spans: () -> any View) -> Self {
        modified {
            $0.children = [Node(contract: SpansContract.self, children: spans().node.asChildren)]
        }
    }
}

extension Text {
    /// One text after another - each keeping its own look, as SwiftUI's
    /// `+` keeps it:
    ///
    ///     Text("let ") + Text("counter").foregroundStyle(.purple)
    ///
    /// Each side becomes a run of the answer's `spans`, carrying the props
    /// written on it - its words, its look, its baseline's lift. A side made
    /// of runs already offers them; a plain side is one run.
    public static func + (lhs: Text, rhs: Text) -> Text {
        var answer = Text()
        answer.node.children = [Node(
            contract: SpansContract.self,
            children: lhs.concatenatedSpans + rhs.concatenatedSpans)]
        for (type, attribute) in lhs.node.textLayoutBox?.attributes ?? [:] {
            answer.node.textLayoutBox?.attributes[type] = attribute
        }
        for (type, attribute) in rhs.node.textLayoutBox?.attributes ?? [:] {
            answer.node.textLayoutBox?.attributes[type] = attribute
        }
        return answer
    }

    /// The spans a `+` takes this text for: the ones written with `.spans`,
    /// else this text itself as one run carrying its own props.
    private var concatenatedSpans: [Node] {
        if let held = node.children.first(where: { $0.type == .spans }) {
            return held.children
        }
        var span = Node(contract: SpanContract.self)
        span.props = node.props
        return [span]
    }

    /// How far the words' baseline stands from the line's own, in points -
    /// a `Text(Image)` glyph sits on the baseline until this lifts it:
    ///
    ///     Text(Image(systemName: "star")).baselineOffset(-2)
    ///
    /// A `+` carries each side's offset down to its own runs.
    public func baselineOffset(_ offset: Double) -> Text {
        var copy = self
        copy.node.write(TextElementContract.baselineOffset, offset)
        return copy
    }

    /// An attribute `Text.Layout`'s runs answer back - the channel a payload
    /// that must survive typesetting travels by:
    ///
    ///     text.customAttribute(MappingsAttribute(mappings: map))
    ///     // in a laid-out run: run[MappingsAttribute.self]
    ///
    /// - Parameter attribute: what each run of this text answers.
    public func customAttribute<A: TextAttribute>(_ attribute: A) -> Text {
        let copy = self
        copy.node.textLayoutBox?.attributes[ObjectIdentifier(A.self)] = attribute
        return copy
    }
}

extension TextLayoutBox {
    /// The report the host sent as this box's lines, its attributes put back
    /// on every run, the generation bumped so a `Layout` folded after answers
    /// anew.
    func fill(_ report: TextLayoutReport) {
        version += 1
        lines = report.lines.map { line in
            Text.Layout.Line(
                typographicBounds: TypographicBounds(rect: line.rect),
                runs: line.runs.map { run in
                    Text.Layout.Run(
                        typographicBounds: TypographicBounds(rect: run.rect),
                        layoutDirection: run.direction,
                        slices: run.slices.enumerated().map { index, rect in
                            Text.Layout.RunSlice(typographicBounds: TypographicBounds(rect: rect),
                                                 text: index < run.sliceTexts.count ? run.sliceTexts[index] : nil)
                        },
                        attributes: attributes)
                })
        }
    }
}

/// One run of text inside a Text, with its own colour, size and weight.
///
///     TextSpan("Sold out")
///         .foregroundStyle(.firebrick)
///         .fontAttributes(.bold)
///
/// Not a view: a run has text and font properties and nothing else, and it
/// goes only in a Text's `spans`.
public struct TextSpan: View, ModifiableElement, TextElement, FontElement,
    LineHeightElement, DecorableTextElement {
    /// The node this run describes.
    public var node: Node

    /// An empty one, for a run built up by modifiers.
    public init() {
        node = Node(contract: SpanContract.self)
    }

    /// A run showing `text`.
    public init(_ text: String) {
        node = Node(contract: SpanContract.self)
        node.write(TextElementContract.text, text)
    }

    /// What is drawn behind this run - a highlight over part of a line.
    public func background(_ value: Color) -> Self {
        setValue(SpanContract.background, value)
    }
}

extension Text {
    /// `lineLimit` from a state, `$x`: the host sets each new value as it
    /// stands, and no view is rebuilt for it.
    public func lineLimit(_ state: Binding<Int>) -> Modified {
        plain(.lineLimit, by: state)
    }
}

extension Text {
    /// A custom renderer for this text, as `.textRenderer` names one:
    ///
    ///     Text(body)
    ///         .textRenderer(MyRenderer())
    ///
    /// The renderer is a code object: it rides the node and a host that draws
    /// text natively keeps its own drawing, so a renderer that only watches
    /// layout still works but its draw pass does not run.
    public func textRenderer(_ renderer: some TextRenderer) -> Self {
        var copy = self
        copy.node.write(TextContract.textRenderer, "custom")
        copy.node.textRenderer = renderer
        return copy
    }
}

extension Text {
    /// The words a `Text` node carries - what `navigationTitle` reads of one
    /// written for it.
    var words: String {
        node.props[TextElementContract.text.token]?.string ?? ""
    }

    /// The lookup key a `Text` node carries, where one was written -
    /// `navigationTitle`'s `titleKey` and its siblings read it of one.
    var wordsKey: LocalizedStringKey? {
        node.props[TextElementContract.textKey.token].flatMap(LocalizedStringKey.init(propValue:))
    }
}
