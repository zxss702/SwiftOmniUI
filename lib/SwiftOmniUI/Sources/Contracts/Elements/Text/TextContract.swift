// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// A read-only piece of text.
public enum TextContract: ElementContract {
    /// The node type the contract declares.
    public static let nodeType: NodeType = "Text"

    /// Every base host presents it with its native control.
    public static let layer: ElementLayer = .native

    /// A label is a view of text in a font - aligned, spaced, decorated and
    /// padded.
    public static let tiers: [any Contract.Type] = [
        ViewContract.self, TextElementContract.self, FontElementContract.self,
        TextAlignmentElementContract.self, LineHeightElementContract.self, DecorableTextElementContract.self,
        PaddingElementContract.self,
    ]

    /// What happens to text too long for the space: it wraps, or it is cut and
    /// says so.
    public static let lineBreak = ElementProperty<Self, LineBreak>("lineBreak", layer: .native)

    /// How many lines show before the text is cut; -1 for no limit.
    public static let lineLimit = ElementProperty<Self, Int>(
        "lineLimit", layer: .native, travels: false)

    /// Whether the user can drag a range out of the text and copy it.
    public static let selectable = ElementProperty<Self, Bool>(
        "selectable", layer: .native, cleared: false)

    /// A subtree reading Text.LayoutKey asks its native labels for geometry.
    public static let reportsLayout = ElementProperty<Self, Bool>(
        "reportsTextLayout", layer: .native, cleared: false)

    /// The fraction of its size the text may shrink to before it is cut;
    /// `.minimumScaleFactor` writes it.
    public static let minimumScaleFactor = ElementProperty<Self, Double>(
        "minimumScaleFactor", layer: .native)

    /// Whether a custom text renderer owns drawing - `"custom"` when
    /// `.textRenderer` attaches one, absent for the default. The renderer
    /// itself is a code object and rides the node, not the wire; this token
    /// records the intent so hosts can declare what they do with it.
    public static let textRenderer = ElementProperty<Self, String>(
        "textRenderer", layer: .native)

    /// The host laid the words out: its lines, runs and glyph slices, as a
    /// `TextLayoutReport` - what the `Text.LayoutKey` preference answers.
    public static let textLayoutChanged = ElementEvent<Self, TextLayoutReport>(
        "textLayoutChanged", layer: .native)

    /// The frame the words settled in, reported as `[x, y, w, h]` - a text's
    /// position fed to its `Layout` answers without a geometry read.
    public static let textFrameChanged = ElementEvent<Self, [Double]>(
        "textFrameChanged", layer: .native)

    /// The element's own members.
    public static let members: [any ContractMember] = [
        lineBreak, lineLimit, minimumScaleFactor, selectable, reportsLayout, textRenderer,
        textLayoutChanged, textFrameChanged]
}
