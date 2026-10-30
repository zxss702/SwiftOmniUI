// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// Lays its children one over another, each in the whole room or in the area it names.
///
///     ZStack(alignment: .bottomTrailing) {
///         ColorPicker(.cornflowerBlue)
///
///         Text("Bottom right")
///
///         Text("Right half")
///             .area(.proportional(0.5, 0, 0.5, 1))
///     }
///     .frame(height: 160)
///
/// A child stands in its area by the stack's `alignment` - or by its own
/// `horizontalAlignment` and `verticalAlignment` where it names them - and
/// fills it unless it says otherwise. A later child is drawn over an earlier
/// one; `zIndex` reorders them without moving anything.
public struct ZStack: LayoutView {
    /// The node this control describes.
    public var node: Node

    /// An empty one - what a `Style<ZStack>` is written against.
    public init() {
        node = Node(contract: ZStackContract.self)
    }

    /// A stack of the layers the closure describes, the first at the back.
    /// Layers stand by the host's default - filling their areas - as before.
    public init(@ViewBuilder content: @escaping () -> any View) {
        self.init()
        node.producer = { content().node.asChildren }
    }

    /// A stack whose layers stand at `alignment` in their areas - a layer
    /// that names its own alignments keeps them.
    public init(
        alignment: Alignment,
        @ViewBuilder content: @escaping () -> any View
    ) {
        self.init(content: content)
        node.producer = {
            var made = content().node.asChildren
            made.alignChildren(horizontal: alignment.horizontal.axis)
            made.alignChildren(vertical: alignment.vertical.axis)
            return made
        }
    }
}
