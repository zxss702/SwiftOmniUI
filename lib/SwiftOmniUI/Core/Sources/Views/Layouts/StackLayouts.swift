// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// Stacks its children top to bottom, each as tall as it asks to be.
///
///     VStack {
///         Text("One")
///         Text("Two")
///     }
///     .spacing(12)
///     .contentPadding(24)
///
/// Children go in the trailing closure; everything else is a modifier, so the
/// layout of the code follows the layout on screen.
///
/// Three sizes are easy to confuse: `.spacing` is the gap BETWEEN children,
/// `.padding` is the room inside the stack's own edges, and `.margin` is the
/// room outside them.
///
/// A stack grows as tall as its children need and does not scroll, so a column
/// longer than the screen wants a `ScrollView` around it. A column that must
/// DIVIDE a fixed height among its children is a `Grid` instead.
public struct VStack: StackBase {
    /// The node this control describes.
    public var node: Node

    /// An empty stack, suitable as a `Style<VStack>` target.
    public init() {
        node = Node(contract: VStackContract.self)
    }

    /// A column of whatever the closure describes, in the order written.
    /// The closure is kept and run when the differ describes the stack.
    ///
    /// Children stand by the host's default - filling the column's width -
    /// the way `ScrollView` and `List` keep their greed. Where children
    /// should stand narrower, name it: `VStack(alignment: .leading)`.
    public init(@ViewBuilder content: @escaping () -> any View) {
        self.init()
        node.producer = { content().node.asChildren }
    }

    /// A column whose children stand at `alignment` across its width - a
    /// child that names its own `horizontalAlignment` keeps it.
    ///
    ///     VStack(alignment: .leading, spacing: 8) {
    ///         Text("Title")
    ///         Text("Body")
    ///     }
    public init(
        alignment: HorizontalAlignment,
        spacing: Double?,
        @ViewBuilder content: @escaping () -> any View
    ) {
        self.init(content: content)
        if let spacing { node.write(StackBaseContract.spacing, spacing) }
        let axis = alignment.axis
        node.producer = {
            var made = content().node.asChildren
            made.alignChildren(horizontal: axis)
            return made
        }
    }

    /// The same, with the stack's own spacing.
    public init(
        alignment: HorizontalAlignment,
        @ViewBuilder content: @escaping () -> any View
    ) {
        self.init(alignment: alignment, spacing: nil, content: content)
    }

    /// The same, centered with the stack's own spacing - the SwiftUI spelling
    /// for `VStack(alignment: .center, spacing:)`.
    public init(
        spacing: Double?,
        @ViewBuilder content: @escaping () -> any View
    ) {
        self.init(alignment: .center, spacing: spacing, content: content)
    }
}

/// Stacks its children left to right, each as wide as it asks to be.
///
///     HStack {
///         Image("nav_home.png")
///         Text("Home")
///     }
///     .spacing(8)
///
/// A stack takes as much room as its children need and does not wrap. Use a
/// `Grid` when children must divide a known width into rows and columns.
public struct HStack: StackBase {
    /// The node this control describes.
    public var node: Node

    /// An empty stack, suitable as a `Style<HStack>` target.
    public init() {
        node = Node(contract: HStackContract.self)
    }

    /// A row of whatever the closure describes, in the order written.
    /// The closure is kept and run when the differ describes the stack.
    ///
    /// Children stand by the host's default - filling the row's height - the
    /// way `ScrollView` and `List` keep their greed. Where children should
    /// stand narrower, name it: `HStack(alignment: .top)`.
    public init(@ViewBuilder content: @escaping () -> any View) {
        self.init()
        node.producer = { content().node.asChildren }
    }

    /// A row whose children stand at `alignment` across its height - a child
    /// that names its own `verticalAlignment` keeps it.
    ///
    ///     HStack(alignment: .top, spacing: 12) {
    ///         Image("logo.png")
    ///         Text("Title")
    ///     }
    public init(
        alignment: VerticalAlignment,
        spacing: Double?,
        @ViewBuilder content: @escaping () -> any View
    ) {
        self.init(content: content)
        if let spacing { node.write(StackBaseContract.spacing, spacing) }
        let axis = alignment.axis
        node.producer = {
            var made = content().node.asChildren
            made.alignChildren(vertical: axis)
            return made
        }
    }

    /// The same, with the stack's own spacing.
    public init(
        alignment: VerticalAlignment,
        @ViewBuilder content: @escaping () -> any View
    ) {
        self.init(alignment: alignment, spacing: nil, content: content)
    }

    /// The same, centered with the stack's own spacing - the SwiftUI spelling
    /// for `HStack(alignment: .center, spacing:)`.
    public init(
        spacing: Double?,
        @ViewBuilder content: @escaping () -> any View
    ) {
        self.init(alignment: .center, spacing: spacing, content: content)
    }
}

extension [Node] {
    /// A stack's `alignment:` handed to each child that did not name its own.
    /// Baselines are a per-child choice; a stack-level `.center` and friends
    /// are what this writes. The value lands under the `...Default` tokens so
    /// an expanded child's own alignment - a shape's `.fill` among them -
    /// always outranks it.
    mutating func alignChildren(horizontal axis: AxisAlignment) {
        for index in indices where self[index].props[.horizontalAlignment] == nil
            && self[index].props[.horizontalAlignmentDefault] == nil {
            self[index].props[.horizontalAlignmentDefault] = axis.propValue
        }
    }

    /// The same, down the other axis.
    mutating func alignChildren(vertical axis: AxisAlignment) {
        for index in indices where self[index].props[.verticalAlignment] == nil
            && self[index].props[.verticalAlignmentDefault] == nil {
            self[index].props[.verticalAlignmentDefault] = axis.propValue
        }
    }
}
