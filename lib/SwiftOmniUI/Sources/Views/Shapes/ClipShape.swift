// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The shapes a `.clipShape` cuts by, and the views that draw them.
// Design: docs/design/types/vocabularies.md#written-out-and-appended

extension Node {
    /// A shape's node - one that fills the room a layout gives it.
    ///
    /// A shape has no size of its own, so the room is all there is: a stack's
    /// `alignment` or another layer's places it without it ever standing at
    /// a natural size of nothing. Stated sizes still win - `Circle().frame(24)`
    /// is 24 across wherever it stands.
    init<Declaration: ElementContract>(shape contract: Declaration.Type) {
        self.init(contract: contract)
        write(ViewContract.horizontalAlignment, .fill)
        write(ViewContract.verticalAlignment, .fill)
    }
}

/// What a `.clipShape` cuts by - the outline a shape stands for:
///
///     Image("avatar.png")
///         .clipShape(Circle())
///
/// `Rectangle` and `Ellipse` answer for themselves; `RoundedRectangle`,
/// `Capsule` and `Circle` are views of their own too, so the same word names
/// what is drawn and what it cuts to.
@preconcurrency @MainActor public protocol ClipShape {
    /// The outline the shape stands for.
    var outline: ContainerShape { get }
}

extension Rectangle: ClipShape {
    /// A square-cornered box.
    public var outline: ContainerShape { .rectangle }
}

extension Ellipse: ClipShape {
    /// An oval the room's shape.
    public var outline: ContainerShape { .ellipse }
}

extension UnevenRoundedRectangle: ClipShape {
    /// A rectangle rounded at each corner by its own radius.
    public var outline: ContainerShape {
        .unevenRoundedRectangle(.corners(
            topLeft: cornerRadii.topLeading, topRight: cornerRadii.topTrailing,
            bottomLeft: cornerRadii.bottomLeading, bottomRight: cornerRadii.bottomTrailing))
    }
}

/// How a rounded corner runs its bend - the plain quarter-circle, or the
/// continuous curve Apple's platforms draw their own with.
public enum RoundedCornerStyle: Sendable {
    /// A quarter-circle's bend.
    case circular

    /// The continuous bend the platforms' own corners take. A host that
    /// cannot draw it takes the circular bend at the same radius.
    case continuous
}

/// A rectangle rounded by a radius, drawn or cut by:
///
///     RoundedRectangle(cornerRadius: 8).fill(.cornflowerBlue)
///     Text("…").clipShape(RoundedRectangle(cornerRadius: 8))
public struct RoundedRectangle: Shape, VisualElement, ShapeProperties, ClipShape {
    /// The node this control describes.
    public var node: Node

    /// The radius every corner rounds by.
    public let cornerRadius: Double

    /// A rectangle whose corners round by `cornerRadius` device units.
    public init(cornerRadius: Double) {
        self.cornerRadius = cornerRadius
        node = Node(shape: RectangleContract.self)
        node.props[RectangleContract.cornerRadius.token] = CornerRadius.uniform(cornerRadius).propValue
    }

    /// A rectangle whose corners round by `cornerRadius`, in `style`'s bend -
    /// `.continuous` drawing as the circular bend where the host has no
    /// squircle.
    public init(cornerRadius: Double, style: RoundedCornerStyle) {
        self.init(cornerRadius: cornerRadius)
    }

    /// A rectangle rounded by `cornerRadius`.
    public var outline: ContainerShape { .roundedRectangle(cornerRadius) }
}

/// A pill - a rectangle rounded by half its shorter side, drawn or cut by:
///
///     Capsule().fill(.tomato).frame(width: 80, height: 32)
///     Text("…").clipShape(Capsule())
public struct Capsule: Shape, VisualElement, ShapeProperties, ClipShape {
    /// The node this control describes.
    public var node: Node

    /// A capsule: the shape a `Rectangle` draws with its radius as big as a
    /// side ever is, the hosts' own fitted radius being the pill's.
    public init() {
        node = Rectangle().cornerRadius(1_000_000).node
    }

    /// A capsule in `style`'s bend - `.continuous` drawing as the circular
    /// bend where the host has no squircle.
    public init(style: RoundedCornerStyle) {
        self.init()
    }

    /// A rectangle rounded by half its shorter side.
    public var outline: ContainerShape { .capsule }
}

/// A circle, drawn or cut by - filling the room it is given, a circle where
/// the room is square:
///
///     Circle().fill(.teal).frame(width: 24, height: 24)
///     Image("avatar.png").clipShape(Circle())
public struct Circle: Shape, VisualElement, ShapeProperties, ClipShape {
    /// The node this control describes.
    public var node: Node

    /// A circle: what an `Ellipse` in a square draws.
    public init() {
        node = Ellipse().node
    }

    /// A circle as wide as the shorter side.
    public var outline: ContainerShape { .circle }
}

extension View {
    /// Cuts the view to `shape`'s outline - everything outside it away:
    ///
    ///     Image("avatar.png")
    ///         .frame(width: 48, height: 48)
    ///         .clipShape(Circle())
    ///
    /// The clip is the container the view is wrapped in's, so it cuts what the
    /// view draws of its own too.
    @_disfavoredOverload public func clipShape(_ shape: some ClipShape) -> ModifiedContent {
        var wrapper = Node(contract: ZStackContract.self)
        let content = node
        wrapper.producer = { content.asChildren }
        wrapper.props[BorderElementContract.shape.token] = shape.outline.propValue
        wrapper.props[LayoutContract.clipsContent.token] = .bool(true)
        return ModifiedContent(node: wrapper)
    }

    /// Cuts by any Shape, evaluated in this view's allocated local bounds.
    public func clipShape<S: Shape>(_ shape: S, style: FillStyle = FillStyle()) -> ModifiedContent {
        if let fixed = shape as? any ClipShape {
            var wrapper = Node(contract: ZStackContract.self)
            let content = node
            wrapper.producer = { content.asChildren }
            wrapper.write(BorderElementContract.shape, fixed.outline)
            wrapper.write(LayoutContract.clipsContent, true)
            return ModifiedContent(node: wrapper)
        }
        return ModifiedContent(node: SizedPathClip(content: self, shape: shape, style: style).node)
    }

    /// Cuts the view to its own bounds - a `.clipShape` by the bounds'
    /// rectangle, the SwiftUI spelling of it:
    ///
    ///     Text("…").frame(maxHeight: 60).clipped()
    ///
    /// `antialiased` softens the cut where the platform draws one; the clip
    /// being the bounds' own, there is no edge to soften.
    public func clipped(antialiased: Bool = false) -> ModifiedContent {
        clipShape(Rectangle())
    }

    /// Sets the outline input on the view stays within: a tap inside it
    /// reaches the view and its gestures, one outside reaches nothing - even
    /// the empty room between a stack's children counts:
    ///
    ///     HStack { … }
    ///         .contentShape(Rectangle())
    ///         .onTapGesture { picked() }
    ///
    ///     Button { } label: { Image("dot") }
    ///         .contentShape(Circle())
    ///
    /// The shape is the container the view is wrapped in's, so the whole room
    /// the view was given answers.
    public func contentShape(_ shape: some ClipShape) -> ModifiedContent {
        var wrapper = Node(contract: ZStackContract.self)
        let content = node
        wrapper.producer = { content.asChildren }
        wrapper.props[LayoutContract.hitShape.token] = shape.outline.propValue
        return ModifiedContent(node: wrapper)
    }

    /// Draws the view only where `mask`'s alpha allows: where the mask paints
    /// opaque the view shows, where it paints clear nothing does - and the
    /// mask itself never draws:
    ///
    ///     Image("cover")
    ///         .mask { RoundedRectangle(cornerRadius: 8) }
    ///
    ///     cell
    ///         .mask {
    ///             HStack(spacing: 0) {
    ///                 LinearGradient(colors: [.clear, .black],
    ///                     startPoint: .leading, endPoint: .trailing).frame(width: 32)
    ///                 Color.black
    ///                 LinearGradient(colors: [.black, .clear],
    ///                     startPoint: .leading, endPoint: .trailing).frame(width: 32)
    ///             }
    ///         }
    ///
    /// The mask is laid out in the same room the view is, so a gradient fades
    /// an edge and a shape cuts a silhouette.
    public func mask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> ModifiedContent {
        var wrapper = Node(contract: MaskedContract.self)
        let content = node
        let maskNode = mask().node
        wrapper.producer = { content.asChildren + maskNode.asChildren }
        return ModifiedContent(node: wrapper)
    }
}

/// A shape's outline filled by a brush - what `.background(_:in:)` paints
/// behind a view.
struct OutlinedFill: View {
    /// The outline drawn.
    let outline: ContainerShape

    /// The fill.
    let brush: Brush

    /// The shape view standing for the outline, filled.
    var node: Node {
        var node = switch outline {
        case .rectangle: Rectangle().node
        case .roundedRectangle(let radius): RoundedRectangle(cornerRadius: radius).node
        case .unevenRoundedRectangle(let cornerRadius):
            switch cornerRadius {
            case .uniform(let radius): RoundedRectangle(cornerRadius: radius).node
            case .corners(let topLeft, let topRight, let bottomLeft, let bottomRight):
                UnevenRoundedRectangle(
                    topLeadingRadius: topLeft, bottomLeadingRadius: bottomLeft,
                    bottomTrailingRadius: bottomRight, topTrailingRadius: topRight,
                    style: .continuous).node
            }
        case .ellipse: Ellipse().node
        case .capsule: Capsule().node
        case .circle: Circle().node
        }
        node.props[ShapeContract.fill.token] = brush.propValue
        return node
    }
}
