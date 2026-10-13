// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// A view with a modifier written on it. Its `node` is the content's node
/// with the change already in it, and it keeps offering every modifier - the
/// tiers' included - so a chain reads the same after one as before it.
public struct ModifiedContent: VisualElement {
    /// The content's node, with the change written into it.
    public var node: Node

    /// Wraps a node that a modifier has already been applied to. Made by the
    /// modifiers that land on a view; there is rarely a reason to call this
    /// directly.
    public init(node: Node) {
        self.node = node
    }
}

/// A modified view still takes the tiers' modifiers: what the view behind it
/// is decides which of them draw anything.
extension ModifiedContent: LayoutView, TextElement, FontElement, TextAlignmentElement,
    ImageElement, TintElement, LineHeightElement, DecorableTextElement, BarElement,
    PageElement {}
