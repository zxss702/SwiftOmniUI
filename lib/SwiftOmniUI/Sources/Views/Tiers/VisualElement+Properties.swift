// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The modifiers every drawn view shares, on the tier a `Style` can also
// wear: the property half writes `Modified`, keeping an element's own type
// through a chain, and the `@_disfavoredOverload` twins on `View` answer the
// same names for a composed view, whose result is opaque.

extension Node {
    /// Padding owns its room, so later backgrounds and clips include it.
    mutating func wrapPadding() {
        wrapPaddedFrame()
        children[0].props[.horizontalAlignmentDefault] = AxisAlignment.fill.propValue
        children[0].props[.verticalAlignmentDefault] = AxisAlignment.fill.propValue
    }

    /// A frame encloses the preceding view, keeping its own size and alignment.
    mutating func wrapPaddedFrame(alignment: Alignment = .center) {
        var content = self
        let fillsAcross = content.props[.horizontalAlignment]?.enumeration == AxisAlignment.fill.rawValue
        let fillsDown = content.props[.verticalAlignment]?.enumeration == AxisAlignment.fill.rawValue
        self = Node(contract: GridContract.self)
        isFrameWrapper = true
        for property: Prop in [.gridRow, .gridColumn, .gridRowSpan, .gridColumnSpan, .area,
            .flex, .layoutPriority, .horizontalGuide, .verticalGuide,
            .horizontalAlignment, .verticalAlignment, .horizontalAlignmentDefault, .verticalAlignmentDefault] {
            props[property] = content.props.removeValue(forKey: property)
            driven[property] = content.driven.removeValue(forKey: property)
        }
        id = content.id
        key = content.key
        content.id = nil
        content.key = nil
        layoutValues = content.layoutValues
        content.layoutValues = [:]
        content.props[.horizontalAlignmentDefault] = alignment.horizontal.axis.propValue
        content.props[.verticalAlignmentDefault] = alignment.vertical.axis.propValue
        content.props[.isFrameContent] = true.propValue
        if fillsAcross { content.props[.horizontalAlignment] = AxisAlignment.fill.propValue }
        if fillsDown { content.props[.verticalAlignment] = AxisAlignment.fill.propValue }
        children = [content]
    }
}

extension VisualElementProperties where Self: View {
    /// Widths the view as the state says, the cell it owns padding it first.
    @_spi(Host) public func frame(width: Binding<Double>) -> Modified {
        modified { node in
            node.wrapPaddedFrame()
            node.driveJourney(VisualElementContract.width, by: width)
        }
    }

    /// Heights the view as the state says, the cell it owns padding it first.
    @_spi(Host) public func frame(height: Binding<Double>) -> Modified {
        modified { node in
            node.wrapPaddedFrame()
            node.driveJourney(VisualElementContract.height, by: height)
        }
    }

    /// Sizes the view to the given width and height, aligning its content
    /// inside the cell the frame owns.
    public func frame(width: Double? = nil, height: Double? = nil, alignment: Alignment = .center) -> Modified {
        modified { node in
            node.wrapPaddedFrame(alignment: alignment)
            if let width { node.write(VisualElementContract.width, width) }
            if let height { node.write(VisualElementContract.height, height) }
            node.write(ViewContract.horizontalContentAlignment, alignment.horizontal.axis)
            node.write(ViewContract.verticalContentAlignment, alignment.vertical.axis)
        }
    }
}

extension VisualElementProperties {
    /// Whether the view responds to the user. Disabling a container disables
    /// everything in it.
    ///
    ///     Button("Save").disabled(!form.isValid)
    public func disabled(_ disabled: Bool = true) -> Modified {
        modified { $0.disable(disabled) }
    }

    /// Hides the view without unbuilding it.
    ///
    /// Showing and hiding animate: a view being hidden fades out before it
    /// goes, one being shown fades in, so two views swapped in one place
    /// cross-fade. A view on its way out answers no touch. A view described for
    /// the first time is simply shown or not; `.animation(nil)` makes the
    /// change immediate.
    public func hidden(_ hidden: Bool = true) -> Modified {
        setValue(VisualElementContract.isVisible, !hidden)
    }

    /// Whether the view and everything in it ignore input: a tap or a click
    /// goes through to whatever is behind it. Not the same as disabled - a
    /// disabled view still takes the touch and does nothing with it. A layout
    /// whose children should still answer says `letsInputThrough` instead.
    public func allowsHitTesting(_ allows: Bool = true) -> Modified {
        setValue(VisualElementContract.ignoresInput, !allows)
    }

    /// Which way the view lays its content out - and, for a language written
    /// right to left, the edge everything starts from.
    ///
    ///     VStack { … }.layoutDirection(.rightToLeft)
    ///
    /// It is INHERITED: a view left at `.inherited` takes whatever the view
    /// above it has, so an application usually says it once at the top.
    @_spi(Host) public func layoutDirection(_ value: LayoutDirection) -> Modified {
        setValue(VisualElementContract.layoutDirection, value)
    }

    /// How opaque the view is, from 0 to 1.
    public func opacity(_ value: Double) -> Modified {
        setValue(VisualElementContract.opacity, value)
    }

    /// A blur applied to this view, in device units - 0 for none.
    ///
    ///     cover.blur(radius: 8)
    public func blur(radius: Double) -> Modified {
        setValue(VisualElementContract.blur, max(radius, 0))
    }

    /// How the view looks as it is inserted and as it is removed - the SwiftUI
    /// spelling.
    ///
    ///     Text("Ready").transition(.blur.combined(with: .offset(y: -48)))
    public func transition(_ transition: AnyTransition) -> Modified {
        setValue(VisualElementContract.transition, transition)
    }

    /// What is drawn behind the view. A view's own background replaces its
    /// style's, and a `Color(light:dark:)` follows the system color scheme.
    public func background(_ value: Color) -> Modified {
        setValue(VisualElementContract.background, .color(value))
    }

    /// What is drawn behind the view, when one colour will not do.
    ///
    ///     VStack { … }.background(.linearGradient([
    ///         GradientStop(.cornflowerBlue, 0),
    ///         GradientStop(.indigo, 1),
    ///     ]))
    ///
    /// The same property as a colour background: the one written last wins.
    public func background(_ value: Brush) -> Modified {
        setValue(VisualElementContract.background, .brush(value))
    }

    /// The size the view asks for, in device units. A request: the layout has
    /// the last word.
    ///
    ///     Image(source).frame(width: 64, height: 64)
    ///     Text(title).frame(alignment: .leading)
    ///
    /// `alignment` is where it sits inside the frame it was given.
    public func frame(
        width: Double? = nil,
        height: Double? = nil,
        alignment: Alignment = .center
    ) -> Modified {
        modified { node in
            if let width { node.write(VisualElementContract.width, width) }
            if let height { node.write(VisualElementContract.height, height) }
            node.write(ViewContract.horizontalContentAlignment, alignment.horizontal.axis)
            node.write(ViewContract.verticalContentAlignment, alignment.vertical.axis)
            if alignment != .center {
                node.write(ViewContract.horizontalAlignment, alignment.horizontal.axis)
                node.write(ViewContract.verticalAlignment, alignment.vertical.axis)
            }
        }
    }

    /// The bounds the view asks to keep within, in device units. A request:
    /// the layout has the last word.
    ///
    ///     Text(title).frame(maxWidth: .infinity)
    ///    Panel().frame(minWidth: 240, maxWidth: 480, minHeight: 120)
    ///
    /// `min*` and `max*` are the bounds it asks not to cross; `ideal*` the size
    /// it prefers within them, the view's own without them. `alignment` is where
    /// it sits inside the frame it was given.
    public func frame(
        minWidth: Double? = nil,
        idealWidth: Double? = nil,
        maxWidth: Double? = nil,
        minHeight: Double? = nil,
        idealHeight: Double? = nil,
        maxHeight: Double? = nil,
        alignment: Alignment = .center
    ) -> Modified {
        modified { node in
            if Self.self is any View.Type { node.wrapPaddedFrame(alignment: alignment) }
            if let minWidth { node.write(VisualElementContract.minimumWidth, minWidth) }
            if let maxWidth { node.write(VisualElementContract.maximumWidth, maxWidth) }
            if let minHeight { node.write(VisualElementContract.minimumHeight, minHeight) }
            if let maxHeight { node.write(VisualElementContract.maximumHeight, maxHeight) }
            node.write(ViewContract.horizontalContentAlignment, alignment.horizontal.axis)
            node.write(ViewContract.verticalContentAlignment, alignment.vertical.axis)
            if !(Self.self is any View.Type), alignment != .center {
                node.write(ViewContract.horizontalAlignment, alignment.horizontal.axis)
                node.write(ViewContract.verticalAlignment, alignment.vertical.axis)
            }
        }
    }

    /// Turns the view, about `anchor`.
    ///
    ///     Image(icon).rotationEffect(.degrees(45))
    ///     Image(icon).rotationEffect(.degrees(45), anchor: .topLeading)
    public func rotationEffect(_ angle: Angle, anchor: UnitPoint = .center) -> Modified {
        modified { node in
            node.write(VisualElementContract.rotation, angle)
            if anchor != .center {
                node.write(VisualElementContract.pivotX, anchor.x)
                node.write(VisualElementContract.pivotY, anchor.y)
            }
        }
    }

    /// Tips the view about its horizontal axis - the top going away as the
    /// bottom comes forward - and about its vertical axis.
    ///
    /// Each platform projects a turn out of the screen's plane through its own
    /// camera, so the same angle draws differently; for the same picture
    /// everywhere, write a `scaleY` of `cos(angle)` instead.
    @_spi(Host) public func rotation3DEffect(x: Angle = .zero, y: Angle = .zero) -> Modified {
        modified { node in
            node.write(VisualElementContract.rotationX, x)
            node.write(VisualElementContract.rotationY, y)
        }
    }

    /// How this view is moved, turned and sized: one transform about the view's
    /// own centre, the same picture on every platform.
    ///
    ///     Card(item).transformEffect(.rotate(14).scale(0.9).translate(100, 200))
    ///
    /// The parts apply in the order written, each to what the parts before it
    /// made; see `ViewTransform`. It writes `offset`, `rotation` and `scale`, so
    /// use it or those, not both.
    @_spi(Host) public func transformEffect(_ transform: ViewTransform) -> Modified {
        modified {
            $0.write(VisualElementContract.translationX, transform.x)
            $0.write(VisualElementContract.translationY, transform.y)
            $0.write(VisualElementContract.rotation, Angle(degrees: transform.rotation))
            $0.write(VisualElementContract.scaleX, transform.width)
            $0.write(VisualElementContract.scaleY, transform.height)
        }
    }

    /// Resizes the view about `anchor`, 1 being its natural size. Drawing
    /// only: the space the layout gave it does not change.
    public func scaleEffect(_ scale: Double, anchor: UnitPoint = .center) -> Modified {
        modified { node in
            node.write(VisualElementContract.scale, scale)
            if anchor != .center {
                node.write(VisualElementContract.pivotX, anchor.x)
                node.write(VisualElementContract.pivotY, anchor.y)
            }
        }
    }

    /// Scales the view on each axis apart, about `anchor`.
    ///
    ///     Image(icon).scaleEffect(x: 0.5, y: 0.5, anchor: .bottom)
    public func scaleEffect(x: Double = 1, y: Double = 1, anchor: UnitPoint = .center) -> Modified {
        modified { node in
            node.write(VisualElementContract.scaleX, x)
            node.write(VisualElementContract.scaleY, y)
            if anchor != .center {
                node.write(VisualElementContract.pivotX, anchor.x)
                node.write(VisualElementContract.pivotY, anchor.y)
            }
        }
    }

    /// Moves the view from where the layout put it, in device units.
    public func offset(x: Double = 0, y: Double = 0) -> Modified {
        modified { node in
            node.write(VisualElementContract.translationX, x)
            node.write(VisualElementContract.translationY, y)
        }
    }

    /// Where rotation and scaling pivot, sideways: 0 the left edge, 1 the right,
    /// 0.5 the middle. What `anchor:` writes; this library's own.
    @_spi(Host) public func pivotX(_ value: Double) -> Modified {
        setValue(VisualElementContract.pivotX, value)
    }

    /// The same, vertically: 0 the top edge, 1 the bottom.
    @_spi(Host) public func pivotY(_ value: Double) -> Modified {
        setValue(VisualElementContract.pivotY, value)
    }

    /// Who is drawn on top where a grid's or an absolute layout's children
    /// overlap, higher being nearer the front; equals are drawn in the order
    /// written.
    public func zIndex(_ value: Double) -> Modified {
        setValue(VisualElementContract.zIndex, value)
    }
}

extension VisualElementProperties {
    /// `opacity` from a state, `$x`: the host animates the property to each new
    /// value, and no view is rebuilt for it.
    @_spi(Host) public func opacity(_ state: Binding<Double>) -> Modified {
        journey(VisualElementContract.opacity, by: state)
    }

    /// `blur` from a state, `$x`: the host animates the property to each new
    /// value, and no view is rebuilt for it.
    @_spi(Host) public func blur(_ state: Binding<Double>) -> Modified {
        journey(VisualElementContract.blur, by: state)
    }

    /// `layoutDirection` from a state, `$x`: the host sets each new value as it
    /// stands, and no view is rebuilt for it.
    @_spi(Host) public func layoutDirection(_ state: Binding<LayoutDirection>) -> Modified {
        plain(VisualElementContract.layoutDirection, by: state)
    }

    /// `background` from a state, `$x`: the host animates the property to each
    /// new value, and no view is rebuilt for it.
    @_spi(Host) public func background(_ state: Binding<Color>) -> Modified {
        journey(VisualElementContract.background.token, by: state)
    }

    /// `width` from a state, `$x`: the host animates the property to each new
    /// value, and no view is rebuilt for it.
    @_spi(Host) public func frame(width: Binding<Double>) -> Modified {
        journey(VisualElementContract.width, by: width)
    }

    /// `height` from a state, `$x`: the host animates the property to each new
    /// value, and no view is rebuilt for it.
    @_spi(Host) public func frame(height: Binding<Double>) -> Modified {
        journey(VisualElementContract.height, by: height)
    }

    /// `minimumWidth` from a state, `$x`: the host animates the property to
    /// each new value, and no view is rebuilt for it.
    @_spi(Host) public func frame(minWidth: Binding<Double>) -> Modified {
        journey(VisualElementContract.minimumWidth, by: minWidth)
    }

    /// `maximumWidth` from a state, `$x`: the host animates the property to
    /// each new value, and no view is rebuilt for it.
    @_spi(Host) public func frame(maxWidth: Binding<Double>) -> Modified {
        journey(VisualElementContract.maximumWidth, by: maxWidth)
    }

    /// `minimumHeight` from a state, `$x`: the host animates the property to
    /// each new value, and no view is rebuilt for it.
    @_spi(Host) public func frame(minHeight: Binding<Double>) -> Modified {
        journey(VisualElementContract.minimumHeight, by: minHeight)
    }

    /// `maximumHeight` from a state, `$x`: the host animates the property to
    /// each new value, and no view is rebuilt for it.
    @_spi(Host) public func frame(maxHeight: Binding<Double>) -> Modified {
        journey(VisualElementContract.maximumHeight, by: maxHeight)
    }

    /// `rotation` from a state, `$x`: the host animates the property to each
    /// new value, and no view is rebuilt for it.
    @_spi(Host) public func rotationEffect(_ state: Binding<Angle>) -> Modified {
        journey(VisualElementContract.rotation, by: state)
    }

    /// `rotation` from a state of degrees, `$x`: the host animates it, and no
    /// view is rebuilt for it.
    @_spi(Host) public func rotationEffect(_ state: Binding<Double>) -> Modified {
        journey(VisualElementContract.rotation.token, by: state)
    }

    /// `rotationX` and `rotationY` from states, `$x`: the host animates them,
    /// and no view is rebuilt for it.
    @_spi(Host) public func rotation3DEffect(x: Binding<Angle>? = nil, y: Binding<Angle>? = nil) -> Modified {
        modified { node in
            if let x { node.driveJourney(VisualElementContract.rotationX, by: x) }
            if let y { node.driveJourney(VisualElementContract.rotationY, by: y) }
        }
    }

    /// `rotationX` and `rotationY` from states of degrees, `$x`: the host
    /// animates them, and no view is rebuilt for it.
    @_spi(Host) public func rotation3DEffect(x: Binding<Double>? = nil, y: Binding<Double>? = nil) -> Modified {
        modified { node in
            if let x { node.driveJourney(VisualElementContract.rotationX.token, by: x) }
            if let y { node.driveJourney(VisualElementContract.rotationY.token, by: y) }
        }
    }

    /// `scale` from a state, `$x`: the host animates the property to each new
    /// value, and no view is rebuilt for it.
    @_spi(Host) public func scaleEffect(_ state: Binding<Double>) -> Modified {
        journey(VisualElementContract.scale, by: state)
    }

    /// `scaleX` and `scaleY` from states, `$x`: the host animates them, and no
    /// view is rebuilt for it.
    @_spi(Host) public func scaleEffect(x: Binding<Double>? = nil, y: Binding<Double>? = nil) -> Modified {
        modified { node in
            if let x { node.driveJourney(VisualElementContract.scaleX, by: x) }
            if let y { node.driveJourney(VisualElementContract.scaleY, by: y) }
        }
    }

    /// `offset` from states, `$x`: the host animates them, and no view is
    /// rebuilt for it.
    @_spi(Host) public func offset(x: Binding<Double>? = nil, y: Binding<Double>? = nil) -> Modified {
        modified { node in
            if let x { node.driveJourney(VisualElementContract.translationX, by: x) }
            if let y { node.driveJourney(VisualElementContract.translationY, by: y) }
        }
    }

    /// `pivotX` from a state, `$x`: the host animates the property to each new
    /// value, and no view is rebuilt for it.
    @_spi(Host) public func pivotX(_ state: Binding<Double>) -> Modified {
        journey(VisualElementContract.pivotX, by: state)
    }

    /// `pivotY` from a state, `$x`: the host animates the property to each new
    /// value, and no view is rebuilt for it.
    @_spi(Host) public func pivotY(_ state: Binding<Double>) -> Modified {
        journey(VisualElementContract.pivotY, by: state)
    }

    /// `zIndex` from a state, `$x`: the host sets each new value as it stands,
    /// and no view is rebuilt for it.
    @_spi(Host) public func zIndex(_ state: Binding<Double>) -> Modified {
        plain(VisualElementContract.zIndex, by: state)
    }
}

extension VisualElementProperties {
    /// `isVisible` from a state, `$x`, inverted as `.hidden` reads it: the host
    /// shows the view where the state stands false, and no view is rebuilt for
    /// it. The state drives the property through a conversion - the derived
    /// state the host carries - so the modifier's direction is the author's.
    @_spi(Host) public func hidden(_ state: Binding<Bool>) -> Modified {
        plain(VisualElementContract.isVisible, by: state.convert { !$0 })
    }

    /// A branch's interaction environment follows the state, including labels
    /// and controls that are materialized later.
    @_spi(Host) public func disabled(_ state: Binding<Bool>) -> Modified {
        disabled(state.wrappedValue)
    }

    /// `ignoresInput` from a state, `$x`, inverted.
    @_spi(Host) public func allowsHitTesting(_ state: Binding<Bool>) -> Modified {
        plain(VisualElementContract.ignoresInput, by: state.convert { !$0 })
    }
}

extension View {
    /// Whether the view responds to the user. Disabling a container disables
    /// everything in it.
    ///
    ///     Button("Save").disabled(!form.isValid)
    @_disfavoredOverload
    public func disabled(_ disabled: Bool = true) -> ModifiedContent {
        revised { $0.disable(disabled) }
    }

    /// Hides the view without unbuilding it.
    @_disfavoredOverload
    public func hidden(_ hidden: Bool = true) -> ModifiedContent {
        setting(VisualElementContract.isVisible, !hidden)
    }

    /// Whether the view and everything in it ignore input: a tap or a click
    /// goes through to whatever is behind it.
    @_disfavoredOverload
    public func allowsHitTesting(_ allows: Bool = true) -> ModifiedContent {
        setting(VisualElementContract.ignoresInput, !allows)
    }

    /// `isEnabled` from a state, `$x`, inverted as `.disabled` reads it.
    @_disfavoredOverload
    @_spi(Host) public func disabled(_ state: Binding<Bool>) -> ModifiedContent {
        disabled(state.wrappedValue)
    }

    /// `isVisible` from a state, `$x`, inverted as `.hidden` reads it.
    @_disfavoredOverload
    @_spi(Host) public func hidden(_ state: Binding<Bool>) -> ModifiedContent {
        revised { $0.drivePlain(VisualElementContract.isVisible, by: state.convert { !$0 }) }
    }

    /// `ignoresInput` from a state, `$x`, inverted.
    @_disfavoredOverload
    @_spi(Host) public func allowsHitTesting(_ state: Binding<Bool>) -> ModifiedContent {
        revised { $0.drivePlain(VisualElementContract.ignoresInput, by: state.convert { !$0 }) }
    }

    /// Which way the view lays its content out - and, for a language written
    /// right to left, the edge everything starts from.
    @_disfavoredOverload
    public func layoutDirection(_ value: LayoutDirection) -> ModifiedContent {
        setting(VisualElementContract.layoutDirection, value)
    }

    /// How opaque the view is, from 0 to 1.
    @_disfavoredOverload
    public func opacity(_ value: Double) -> ModifiedContent {
        setting(VisualElementContract.opacity, value)
    }

    /// A blur applied to this view, in device units - 0 for none.
    @_disfavoredOverload
    public func blur(radius: Double) -> ModifiedContent {
        setting(VisualElementContract.blur, max(radius, 0))
    }

    /// How the view looks as it is inserted and as it is removed.
    @_disfavoredOverload
    public func transition(_ transition: AnyTransition) -> ModifiedContent {
        setting(VisualElementContract.transition, transition)
    }

    /// What is drawn behind the view.
    @_disfavoredOverload
    public func background(_ value: Color) -> ModifiedContent {
        setting(VisualElementContract.background, .color(value))
    }

    /// What is drawn behind the view, when one colour will not do.
    @_disfavoredOverload
    public func background(_ value: Brush) -> ModifiedContent {
        setting(VisualElementContract.background, .brush(value))
    }

    /// What is drawn behind the view, said as a style: a colour, a gradient
    /// or a material.
    ///
    ///     Text("…").background(LinearGradient(colors: [.white, .clear],
    ///         startPoint: .top, endPoint: .bottom))
    ///     Text("…").background(.regularMaterial)
    @_disfavoredOverload
    public func background(_ style: some ShapeStyle) -> ModifiedContent {
        background(style.brush)
    }

    /// `style` painted behind the view within `shape`'s outline - the outline
    /// filled behind the view, which itself keeps its own shape:
    ///
    ///     Text("…").background(.ultraThinMaterial, in: Capsule())
    ///     row.background(isHovered ? .gray.opacity(0.1) : .clear,
    ///         in: RoundedRectangle(cornerRadius: 8))
    public func background(_ style: some ShapeStyle, in shape: some Shape,
                           fillStyle: FillStyle = FillStyle()) -> some View {
        background {
            if let fixed = shape as? any PrimitiveShape {
                OutlinedFill(outline: fixed.outline, brush: style.brush)
                    .setting(ShapeContract.fillRule, fillStyle.isEOFilled ? .evenOdd : .nonzero)
            } else {
                shape.fill(style, style: fillStyle)
            }
        }
    }

    /// The size the view asks for, in device units. A request: the layout has
    /// the last word.
    @_disfavoredOverload
    public func frame(
        width: Double? = nil,
        height: Double? = nil,
        alignment: Alignment = .center
    ) -> ModifiedContent {
        revised { node in
            node.wrapPaddedFrame(alignment: alignment)
            if let width { node.write(VisualElementContract.width, width) }
            if let height { node.write(VisualElementContract.height, height) }
            node.write(ViewContract.horizontalContentAlignment, alignment.horizontal.axis)
            node.write(ViewContract.verticalContentAlignment, alignment.vertical.axis)
        }
    }

    /// The bounds the view asks to keep within, in device units. A request:
    /// the layout has the last word.
    @_disfavoredOverload
    public func frame(
        minWidth: Double? = nil,
        idealWidth: Double? = nil,
        maxWidth: Double? = nil,
        minHeight: Double? = nil,
        idealHeight: Double? = nil,
        maxHeight: Double? = nil,
        alignment: Alignment = .center
    ) -> ModifiedContent {
        revised { node in
            node.wrapPaddedFrame(alignment: alignment)
            if let minWidth { node.write(VisualElementContract.minimumWidth, minWidth) }
            if let maxWidth { node.write(VisualElementContract.maximumWidth, maxWidth) }
            if let minHeight { node.write(VisualElementContract.minimumHeight, minHeight) }
            if let maxHeight { node.write(VisualElementContract.maximumHeight, maxHeight) }
            node.write(ViewContract.horizontalContentAlignment, alignment.horizontal.axis)
            node.write(ViewContract.verticalContentAlignment, alignment.vertical.axis)
        }
    }

    /// Turns the view, about `anchor`.
    @_disfavoredOverload
    public func rotationEffect(_ angle: Angle, anchor: UnitPoint = .center) -> ModifiedContent {
        revised { node in
            node.write(VisualElementContract.rotation, angle)
            if anchor != .center {
                node.write(VisualElementContract.pivotX, anchor.x)
                node.write(VisualElementContract.pivotY, anchor.y)
            }
        }
    }

    /// Tips the view about its horizontal and vertical axes.
    @_disfavoredOverload
    @_spi(Host) public func rotation3DEffect(x: Angle = .zero, y: Angle = .zero) -> ModifiedContent {
        revised { node in
            node.write(VisualElementContract.rotationX, x)
            node.write(VisualElementContract.rotationY, y)
        }
    }

    /// Turns the view about the axis given, in the screen's plane when the
    /// axis is `z` and out of it when `x` or `y` - the SwiftUI spelling.
    public func rotation3DEffect(
        _ angle: Angle, axis: (x: Double, y: Double, z: Double)
    ) -> ModifiedContent {
        revised { node in
            if axis.x != 0 { node.write(VisualElementContract.rotationX, Angle(degrees: angle.degrees * axis.x)) }
            if axis.y != 0 { node.write(VisualElementContract.rotationY, Angle(degrees: angle.degrees * axis.y)) }
            if axis.z != 0 { node.write(VisualElementContract.rotation, Angle(degrees: angle.degrees * axis.z)) }
        }
    }

    /// How this view is moved, turned and sized: one transform about the view's
    /// own centre.
    @_disfavoredOverload
    @_spi(Host) public func transformEffect(_ transform: ViewTransform) -> ModifiedContent {
        revised {
            $0.write(VisualElementContract.translationX, transform.x)
            $0.write(VisualElementContract.translationY, transform.y)
            $0.write(VisualElementContract.rotation, Angle(degrees: transform.rotation))
            $0.write(VisualElementContract.scaleX, transform.width)
            $0.write(VisualElementContract.scaleY, transform.height)
        }
    }

    /// Resizes the view about `anchor`, 1 being its natural size.
    @_disfavoredOverload
    public func scaleEffect(_ scale: Double, anchor: UnitPoint = .center) -> ModifiedContent {
        revised { node in
            node.write(VisualElementContract.scale, scale)
            if anchor != .center {
                node.write(VisualElementContract.pivotX, anchor.x)
                node.write(VisualElementContract.pivotY, anchor.y)
            }
        }
    }

    /// Scales the view on each axis apart, about `anchor`.
    @_disfavoredOverload
    public func scaleEffect(x: Double = 1, y: Double = 1, anchor: UnitPoint = .center) -> ModifiedContent {
        revised { node in
            node.write(VisualElementContract.scaleX, x)
            node.write(VisualElementContract.scaleY, y)
            if anchor != .center {
                node.write(VisualElementContract.pivotX, anchor.x)
                node.write(VisualElementContract.pivotY, anchor.y)
            }
        }
    }

    /// Moves the view from where the layout put it, in device units.
    @_disfavoredOverload
    public func offset(x: Double = 0, y: Double = 0) -> ModifiedContent {
        revised { node in
            node.write(VisualElementContract.translationX, x)
            node.write(VisualElementContract.translationY, y)
        }
    }

    /// Where rotation and scaling pivot, sideways. This library's own.
    @_disfavoredOverload
    @_spi(Host) public func pivotX(_ value: Double) -> ModifiedContent {
        setting(VisualElementContract.pivotX, value)
    }

    /// The same, vertically.
    @_disfavoredOverload
    @_spi(Host) public func pivotY(_ value: Double) -> ModifiedContent {
        setting(VisualElementContract.pivotY, value)
    }

    /// Who is drawn on top where a grid's or an absolute layout's children
    /// overlap.
    @_disfavoredOverload
    public func zIndex(_ value: Double) -> ModifiedContent {
        setting(VisualElementContract.zIndex, value)
    }
}

extension View {
    /// `opacity` from a state, `$x`: the host animates the property to each new
    /// value, and no view is rebuilt for it.
    @_disfavoredOverload
    @_spi(Host) public func opacity(_ state: Binding<Double>) -> ModifiedContent {
        revised { $0.driveJourney(VisualElementContract.opacity, by: state) }
    }

    /// `blur` from a state, `$x`.
    @_disfavoredOverload
    @_spi(Host) public func blur(_ state: Binding<Double>) -> ModifiedContent {
        revised { $0.driveJourney(VisualElementContract.blur, by: state) }
    }

    /// `layoutDirection` from a state, `$x`.
    @_disfavoredOverload
    @_spi(Host) public func layoutDirection(_ state: Binding<LayoutDirection>) -> ModifiedContent {
        revised { $0.drivePlain(VisualElementContract.layoutDirection, by: state) }
    }

    /// `background` from a state, `$x`.
    @_disfavoredOverload
    @_spi(Host) public func background(_ state: Binding<Color>) -> ModifiedContent {
        revised { $0.driveJourney(VisualElementContract.background.token, by: state) }
    }

    /// `width` from a state, `$x`.
    @_disfavoredOverload
    @_spi(Host) public func frame(width: Binding<Double>) -> ModifiedContent {
        revised { node in
            node.wrapPaddedFrame()
            node.driveJourney(VisualElementContract.width, by: width)
        }
    }

    /// `height` from a state, `$x`.
    @_disfavoredOverload
    @_spi(Host) public func frame(height: Binding<Double>) -> ModifiedContent {
        revised { node in
            node.wrapPaddedFrame()
            node.driveJourney(VisualElementContract.height, by: height)
        }
    }

    /// `minimumWidth` from a state, `$x`.
    @_disfavoredOverload
    @_spi(Host) public func frame(minWidth: Binding<Double>) -> ModifiedContent {
        revised { $0.driveJourney(VisualElementContract.minimumWidth, by: minWidth) }
    }

    /// `maximumWidth` from a state, `$x`.
    @_disfavoredOverload
    @_spi(Host) public func frame(maxWidth: Binding<Double>) -> ModifiedContent {
        revised { $0.driveJourney(VisualElementContract.maximumWidth, by: maxWidth) }
    }

    /// `minimumHeight` from a state, `$x`.
    @_disfavoredOverload
    @_spi(Host) public func frame(minHeight: Binding<Double>) -> ModifiedContent {
        revised { $0.driveJourney(VisualElementContract.minimumHeight, by: minHeight) }
    }

    /// `maximumHeight` from a state, `$x`.
    @_disfavoredOverload
    @_spi(Host) public func frame(maxHeight: Binding<Double>) -> ModifiedContent {
        revised { $0.driveJourney(VisualElementContract.maximumHeight, by: maxHeight) }
    }

    /// `rotation` from a state, `$x`.
    @_disfavoredOverload
    @_spi(Host) public func rotationEffect(_ state: Binding<Angle>) -> ModifiedContent {
        revised { $0.driveJourney(VisualElementContract.rotation, by: state) }
    }

    /// `rotation` from a state of degrees, `$x`.
    @_disfavoredOverload
    @_spi(Host) public func rotationEffect(_ state: Binding<Double>) -> ModifiedContent {
        revised { $0.driveJourney(VisualElementContract.rotation.token, by: state) }
    }

    /// `rotationX` and `rotationY` from states, `$x`.
    @_disfavoredOverload
    @_spi(Host) public func rotation3DEffect(x: Binding<Angle>? = nil, y: Binding<Angle>? = nil) -> ModifiedContent {
        revised { node in
            if let x { node.driveJourney(VisualElementContract.rotationX, by: x) }
            if let y { node.driveJourney(VisualElementContract.rotationY, by: y) }
        }
    }

    /// `rotationX` and `rotationY` from states of degrees, `$x`.
    @_disfavoredOverload
    @_spi(Host) public func rotation3DEffect(x: Binding<Double>? = nil, y: Binding<Double>? = nil) -> ModifiedContent {
        revised { node in
            if let x { node.driveJourney(VisualElementContract.rotationX.token, by: x) }
            if let y { node.driveJourney(VisualElementContract.rotationY.token, by: y) }
        }
    }

    /// `scale` from a state, `$x`.
    @_disfavoredOverload
    @_spi(Host) public func scaleEffect(_ state: Binding<Double>) -> ModifiedContent {
        revised { $0.driveJourney(VisualElementContract.scale, by: state) }
    }

    /// `scaleX` and `scaleY` from states, `$x`.
    @_disfavoredOverload
    @_spi(Host) public func scaleEffect(x: Binding<Double>? = nil, y: Binding<Double>? = nil) -> ModifiedContent {
        revised { node in
            if let x { node.driveJourney(VisualElementContract.scaleX, by: x) }
            if let y { node.driveJourney(VisualElementContract.scaleY, by: y) }
        }
    }

    /// `offset` from states, `$x`.
    @_disfavoredOverload
    @_spi(Host) public func offset(x: Binding<Double>? = nil, y: Binding<Double>? = nil) -> ModifiedContent {
        revised { node in
            if let x { node.driveJourney(VisualElementContract.translationX, by: x) }
            if let y { node.driveJourney(VisualElementContract.translationY, by: y) }
        }
    }

    /// `pivotX` from a state, `$x`.
    @_disfavoredOverload
    @_spi(Host) public func pivotX(_ state: Binding<Double>) -> ModifiedContent {
        revised { $0.driveJourney(VisualElementContract.pivotX, by: state) }
    }

    /// `pivotY` from a state, `$x`.
    @_disfavoredOverload
    @_spi(Host) public func pivotY(_ state: Binding<Double>) -> ModifiedContent {
        revised { $0.driveJourney(VisualElementContract.pivotY, by: state) }
    }

    /// `zIndex` from a state, `$x`.
    @_disfavoredOverload
    @_spi(Host) public func zIndex(_ state: Binding<Double>) -> ModifiedContent {
        revised { $0.drivePlain(VisualElementContract.zIndex, by: state) }
    }
}
