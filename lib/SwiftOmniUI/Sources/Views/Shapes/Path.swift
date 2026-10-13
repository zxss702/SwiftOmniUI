// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The platform's C maths library, for an arc's angles - not Foundation.
#if canImport(Android)
import Android
#elseif canImport(Glibc)
import Glibc
#elseif canImport(CRT)
import CRT
#endif

/// Whatever an outline can be, written in SVG path syntax.
///
///     Path("M 0,40 L 20,0 L 40,40 Z")
///         .fill(.gold)
///         .aspect(.fit)
///
/// `M` moves, `L` draws a line, `C` a curve, `A` an arc and `Z` closes the
/// figure. The numbers are device units in the path's OWN space, and `.aspect`
/// says what happens to that space in the room the layout gives it - a path
/// drawn 40 wide keeps its coordinates by default. Explicit `.fit` fills a
/// 200-wide cell; `.center` keeps its size and centers its bounds.
///
/// Every platform accepts the same grammar: the host parses the path itself
/// before drawing it.
/// Geometry construction and transforms are independent of the UI actor;
/// describing the path's view and applying view modifiers stay on MainActor.
nonisolated public struct Path: Shape, VisualElement, ShapeProperties, PathProperties {
    // Geometry is independent of the node and any frame wrappers.
    private var properties: Node
    private var commands: [HostPathCommand] = []
    private var cursor: Point?
    private var subpathStart: Point?

    /// The native description, encoded once when the view is requested.
    @MainActor public var node: Node {
        get {
            var result = properties
            result.write(PathContract.commands, geometry.numbers)
            return result
        }
        set {
            let content = newValue.controlContent
            if let data = content.props[PathContract.data.token]?.string {
                replaceGeometry(HostPath(svg: data)?.commands ?? [])
            } else if let values = content.props[PathContract.commands.token]?.numbers,
                      values != geometry.numbers {
                replaceGeometry(HostPath(numbers: values)?.commands ?? [])
            }
            properties = newValue
            properties.modifyControl {
                $0.props.removeValue(forKey: PathContract.data.token)
                $0.props.removeValue(forKey: PathContract.commands.token)
            }
        }
    }

    var geometry: HostPath { HostPath(commands: commands) }
    public func path(in rect: Rect) -> Path { self }

    /// A path with no outline yet - what a `Style<Path>` is written against.
    public init() {
        properties = Node(shape: PathContract.self)
    }

    /// The outline, in SVG path syntax.
    public init(_ data: String) {
        properties = Node(shape: PathContract.self)
        replaceGeometry(HostPath(svg: data)?.commands ?? [])
    }

    /// An outline written by the closure, the way SwiftUI builds one:
    ///
    ///     Path { path in
    ///         path.move(to: Point(x: 0, y: 0))
    ///         path.addCurve(to: Point(x: 40, y: 20),
    ///                       control1: Point(x: 0, y: 10), control2: Point(x: 40, y: 10))
    ///     }
    ///
    /// - Parameter callback: writes the outline on the empty path it is
    ///   handed, through `move`, `addLine`, `addCurve` and `closeSubpath`.
    public init(_ callback: (inout Path) -> Void) {
        self.init()
        callback(&self)
    }

    /// `rect`'s outline.
    public init(_ rect: Rect) {
        self.init()
        addRect(rect)
    }

    /// The ellipse `rect` holds, as `GraphicsContext` calls draw it.
    public init(ellipseIn rect: Rect) {
        self.init()
        addEllipse(in: rect)
    }

    /// `rect` with every corner rounded by `cornerSize` - how far across each
    /// bend reaches, then how far down.
    public init(roundedRect rect: Rect, cornerSize: Size) {
        self.init(roundedRect: rect, cornerSize: cornerSize, style: .circular)
    }

    /// The same, in `style`'s bend - `.continuous` drawing the circular bend
    /// the outline is.
    public init(roundedRect rect: Rect, cornerSize: Size, style: RoundedCornerStyle) {
        self.init()
        addRoundedRect(in: rect, cornerSize: cornerSize, style: style)
    }

    /// `rect` with every corner rounded by `cornerRadius`.
    public init(roundedRect rect: Rect, cornerRadius: Double) {
        self.init(roundedRect: rect, cornerRadius: cornerRadius, style: .circular)
    }

    /// The same, in `style`'s bend - `.continuous` drawing the circular bend
    /// the outline is.
    public init(roundedRect rect: Rect, cornerRadius: Double, style: RoundedCornerStyle) {
        self.init()
        addRoundedRect(in: rect, cornerRadius: cornerRadius)
    }

    /// `rect` with each corner rounded by its own radius.
    public init(roundedRect rect: Rect, cornerRadii: RectangleCornerRadii) {
        self.init(roundedRect: rect, cornerRadii: cornerRadii, style: .circular)
    }

    /// The same, in `style`'s bend - `.continuous` drawing the circular bend
    /// the outline is.
    public init(roundedRect rect: Rect, cornerRadii: RectangleCornerRadii, style: RoundedCornerStyle) {
        self.init()
        addRoundedRect(in: rect, cornerRadii: cornerRadii, style: style)
    }

    /// The outline as it stands, in the syntax the initializer takes - what a
    /// `GraphicsContext` call draws.
    nonisolated var svg: String {
        HostPath(commands: commands).svg
    }

    /// Whether the outline says nothing yet - an empty path draws nothing.
    public var isEmpty: Bool {
        commands.isEmpty
    }

    /// Where the outline stands: the point the next segment starts from, nil
    /// on an empty path.
    public var currentPoint: Point? { tail }

    /// Begins a new subpath at `point`, drawing nothing to it.
    public mutating func move(
        to point: Point
    ) {
        append(.move(point))
    }

    /// Adds a straight segment from where the path stands to `point`.
    public mutating func addLine(to point: Point) {
        append(.line(point))
    }

    /// Adds a straight segment to each of the points, in order.
    public mutating func addLines(_ lines: [Point]) {
        for point in lines {
            addLine(to: point)
        }
    }

    /// Adds a cubic Bézier segment to `point`, bent by the two control points.
    public mutating func addCurve(to point: Point, control1: Point, control2: Point) {
        append(.cubic(control1: control1, control2: control2, end: point))
    }

    /// Adds a quadratic Bézier segment to `point`, bent by the one control
    /// point.
    public mutating func addQuadCurve(to point: Point, control: Point) {
        append(.quadratic(control: control, end: point))
    }

    /// Adds an arc of the circle `radius` about `center`, running from
    /// `startAngle` to `endAngle` the way `clockwise` says. A straight
    /// segment to the arc's start comes first where the outline stands
    /// somewhere else.
    ///
    /// Angles count the way `.rotationEffect` turns: 0 to the right, 90
    /// straight down. Unset, `clockwise` turns the arc the way the angles
    /// grow - which reads clockwise on screen, the y axis pointing down;
    /// set it to turn the other way.
    ///
    /// - Parameters:
    ///   - center: the circle's centre.
    ///   - radius: how far the arc runs from it.
    ///   - startAngle: where on the circle the arc begins.
    ///   - endAngle: where on the circle it ends; a difference of a full
    ///     turn from `startAngle` draws the whole circle.
    ///   - clockwise: which way round it goes between the two.
    public mutating func addArc(
        center: Point, radius: Double,
        startAngle: Angle, endAngle: Angle, clockwise: Bool
    ) {
        let radius = abs(radius)
        let start = Self.rim(of: center, radius: radius, at: startAngle.degrees)
        join(to: start)
        guard radius > 0 else { return }

        let difference = clockwise
            ? startAngle.degrees - endAngle.degrees
            : endAngle.degrees - startAngle.degrees
        var delta = difference.truncatingRemainder(dividingBy: 360)
        if delta < 0 { delta += 360 }
        if delta == 0 {
            guard difference != 0 else { return }
            delta = 360
        }
        if delta == 360 {
            circle(about: center, radius: radius, from: start, sweep: !clockwise)
        } else {
            arc(
                to: Self.rim(of: center, radius: radius, at: endAngle.degrees),
                radiusX: radius, radiusY: radius,
                largeArc: delta > 180, sweep: !clockwise)
        }
    }

    /// Adds an arc of the circle `radius` about `center`, from `startAngle`
    /// turning `delta` - a positive delta the way the angles count, from
    /// right toward down, a turn of a full circle or more drawing the whole
    /// circle. A straight segment to the arc's start comes first where the
    /// outline stands somewhere else.
    ///
    /// - Parameters:
    ///   - center: the circle's centre.
    ///   - radius: how far the arc runs from it.
    ///   - startAngle: where on the circle the arc begins, 0 to the right
    ///     and 90 straight down.
    ///   - delta: how far round it turns.
    public mutating func addRelativeArc(
        center: Point, radius: Double, startAngle: Angle, delta: Angle
    ) {
        let radius = abs(radius)
        let start = Self.rim(of: center, radius: radius, at: startAngle.degrees)
        join(to: start)
        guard radius > 0, delta.degrees != 0 else { return }

        let sweep = delta.degrees > 0
        if abs(delta.degrees) >= 360 {
            circle(about: center, radius: radius, from: start, sweep: sweep)
        } else {
            arc(
                to: Self.rim(of: center, radius: radius, at: startAngle.degrees + delta.degrees),
                radiusX: radius, radiusY: radius,
                largeArc: abs(delta.degrees) > 180, sweep: sweep)
        }
    }

    /// Adds an arc of `radius` tangent to the line running from where the
    /// outline stands to `tangent1End`, and to the line from `tangent1End`
    /// to `tangent2End` - a corner rounded. A straight segment to the arc's
    /// start comes first where they do not already meet.
    ///
    /// - Parameters:
    ///   - tangent1End: the corner the two tangent lines meet in.
    ///   - tangent2End: the point the second tangent line runs to.
    ///   - radius: the bend's radius; a corner that cannot be drawn - no
    ///     outline standing, or a straight run through - draws as a line to
    ///     `tangent1End`.
    public mutating func addArc(tangent1End: Point, tangent2End: Point, radius: Double) {
        guard let current = tail else {
            move(to: tangent1End)
            return
        }
        guard radius > 0 else {
            if current != tangent1End { addLine(to: tangent1End) }
            return
        }

        // The corner the two tangent lines make, as directions out of it.
        let alongX = current.x - tangent1End.x
        let alongY = current.y - tangent1End.y
        let awayX = tangent2End.x - tangent1End.x
        let awayY = tangent2End.y - tangent1End.y
        let along = (alongX * alongX + alongY * alongY).squareRoot()
        let away = (awayX * awayX + awayY * awayY).squareRoot()
        guard along > 0, away > 0 else {
            addLine(to: tangent1End)
            return
        }

        let bend = acos(max(-1, min(1, (alongX * awayX + alongY * awayY) / (along * away))))
        guard bend > 0.0001, bend < .pi - 0.0001 else {
            addLine(to: tangent1End)
            return
        }

        // The bend's tangent points sit `reach` out of the corner on each
        // line; the arc turns the way the path turns, which a positive cross
        // reads clockwise with the y axis pointing down.
        let reach = radius / tan(bend / 2)
        let start = Point(
            tangent1End.x + alongX / along * reach,
            tangent1End.y + alongY / along * reach)
        let end = Point(
            tangent1End.x + awayX / away * reach,
            tangent1End.y + awayY / away * reach)
        if current != start { addLine(to: start) }

        let turning = (tangent1End.x - current.x) * (tangent2End.y - tangent1End.y)
            - (tangent1End.y - current.y) * (tangent2End.x - tangent1End.x)
        arc(to: end, radiusX: radius, radiusY: radius, largeArc: false, sweep: turning > 0)
    }

    /// Adds `rect`'s outline as a subpath: a move, three lines and a close.
    public mutating func addRect(_ rect: Rect) {
        move(to: Point(rect.x, rect.y))
        addLine(to: Point(rect.x + rect.width, rect.y))
        addLine(to: Point(rect.x + rect.width, rect.y + rect.height))
        addLine(to: Point(rect.x, rect.y + rect.height))
        closeSubpath()
    }

    /// Adds each rectangle's outline as a subpath, in order.
    public mutating func addRects(_ rects: [Rect]) {
        for rect in rects {
            addRect(rect)
        }
    }

    /// Adds the ellipse `rect` holds, as its own closed subpath.
    public mutating func addEllipse(in rect: Rect) {
        let radiusX = rect.width / 2
        let radiusY = rect.height / 2
        let centerX = rect.x + radiusX
        let centerY = rect.y + radiusY
        move(to: Point(centerX, centerY - radiusY))
        arc(to: Point(centerX, centerY + radiusY), radiusX: radiusX, radiusY: radiusY, largeArc: true, sweep: true)
        arc(to: Point(centerX, centerY - radiusY), radiusX: radiusX, radiusY: radiusY, largeArc: true, sweep: true)
        closeSubpath()
    }

    /// Adds `rect` with every corner rounded by `cornerSize` - how far across
    /// each bend reaches, then how far down - in `style`'s bend, as its own
    /// closed subpath. `.continuous` draws the circular bend the outline is.
    public mutating func addRoundedRect(
        in rect: Rect, cornerSize: Size, style: RoundedCornerStyle = .continuous
    ) {
        appendRoundedRect(
            rect,
            topLeading: cornerSize, topTrailing: cornerSize,
            bottomTrailing: cornerSize, bottomLeading: cornerSize)
    }

    /// Adds `rect` with each corner rounded by its own radius, as its own
    /// closed subpath - `.continuous` drawing the circular bend the outline
    /// is.
    public mutating func addRoundedRect(
        in rect: Rect, cornerRadii: RectangleCornerRadii, style: RoundedCornerStyle = .continuous
    ) {
        appendRoundedRect(
            rect,
            topLeading: Size(cornerRadii.topLeading, cornerRadii.topLeading),
            topTrailing: Size(cornerRadii.topTrailing, cornerRadii.topTrailing),
            bottomTrailing: Size(cornerRadii.bottomTrailing, cornerRadii.bottomTrailing),
            bottomLeading: Size(cornerRadii.bottomLeading, cornerRadii.bottomLeading))
    }

    /// Adds `rect` with every corner rounded by `cornerRadius`, as its own
    /// closed subpath.
    public mutating func addRoundedRect(in rect: Rect, cornerRadius: Double) {
        addRoundedRect(in: rect, cornerSize: Size(cornerRadius, cornerRadius))
    }

    /// Appends `path`'s outline to this one's - its subpaths keeping their
    /// own starts, the numbers taken as they are.
    public mutating func addPath(_ path: Path) {
        for command in path.commands { append(command) }
    }

    /// Closes the current subpath with a straight segment back to where it
    /// began.
    public mutating func closeSubpath() {
        if subpathStart != nil { append(.close) }
    }

    /// The same outline with `transform` applied to every point - a new
    /// path, this one unchanged.
    ///
    /// An arc stays an arc while the transform only moves, turns and sizes
    /// evenly - or sizes each axis its own way square to them; anything else
    /// draws the arc as the curves it flattens to.
    ///
    /// - Parameter transform: how the outline is moved, turned and sized.
    /// - Returns: the path, transformed.
    public func applying(_ transform: ViewTransform) -> Path {
        let parsed = geometry

        func mapped(_ point: Point) -> Point {
            Point(
                transform.a * point.x + transform.c * point.y + transform.tx,
                transform.b * point.x + transform.d * point.y + transform.ty)
        }

        let diagonal = transform.b == 0 && transform.c == 0
        let conformal = transform.a == transform.d && transform.c == -transform.b

        var copy = self
        copy.replaceGeometry([])
        var current = Point.zero
        var start = Point.zero

        for command in parsed.commands {
            switch command {
            case .move(let point):
                copy.move(to: mapped(point))
                current = point
                start = point
            case .line(let point):
                copy.addLine(to: mapped(point))
                current = point
            case .cubic(let control1, let control2, let end):
                copy.addCurve(to: mapped(end), control1: mapped(control1), control2: mapped(control2))
                current = end
            case .quadratic(let control, let end):
                copy.addQuadCurve(to: mapped(end), control: mapped(control))
                current = end
            case .arc(let radiusX, let radiusY, let rotation, let largeArc, let sweep, let end):
                if diagonal && (rotation.truncatingRemainder(dividingBy: 180) == 0 || abs(transform.a) == abs(transform.d)) {
                    // An axis-aligned ellipse or equal scaling of both axes; a mirror in one turns the
                    // arc the other way round.
                    let mirrored = transform.a * transform.d < 0
                    copy.arc(
                        to: mapped(end),
                        radiusX: radiusX * abs(transform.a),
                        radiusY: radiusY * abs(transform.d),
                        rotation: mirrored ? -rotation : rotation,
                        largeArc: largeArc, sweep: mirrored ? !sweep : sweep)
                } else if conformal {
                    // A turn with an even sizing: the ellipse's radii size
                    // and its axis turns with it.
                    let sizing = (transform.a * transform.a + transform.b * transform.b).squareRoot()
                    copy.arc(
                        to: mapped(end),
                        radiusX: radiusX * sizing, radiusY: radiusY * sizing,
                        rotation: rotation + atan2(transform.b, transform.a) * 180 / .pi,
                        largeArc: largeArc, sweep: sweep)
                } else {
                    for curve in HostPath.arc(
                        from: current, to: end, radiusX: radiusX, radiusY: radiusY,
                        rotation: rotation, largeArc: largeArc, sweep: sweep)
                    {
                        switch curve {
                        case .cubic(let control1, let control2, let end):
                            copy.addCurve(to: mapped(end), control1: mapped(control1), control2: mapped(control2))
                        case .line(let end):
                            copy.addLine(to: mapped(end))
                        case .quadratic(let control, let end):
                            copy.addQuadCurve(to: mapped(end), control: mapped(control))
                        case .move(let point):
                            copy.move(to: mapped(point))
                        case .close:
                            copy.closeSubpath()
                        }
                    }
                }
                current = end
            case .close:
                copy.closeSubpath()
                current = start
            }
        }
        return copy
    }

    /// The outline moved `dx` across and `dy` down - a new path, this one
    /// unchanged.
    ///
    /// - Returns: the path, moved.
    public func offsetBy(dx: Double, dy: Double) -> Path {
        applying(.translate(dx, dy))
    }

    /// One more statement of the outline, past what it already says.
    private mutating func append(_ command: HostPathCommand) {
        // A segment with no start begins at its endpoint, matching native paths.
        if cursor == nil {
            switch command {
            case .move: break
            case .line(let p), .cubic(_, _, let p), .quadratic(_, let p), .arc(_, _, _, _, _, let p):
                append(.move(p)); return
            case .close: return
            }
        }
        commands.append(command)
        switch command {
        case .move(let p): cursor = p; subpathStart = p
        case .line(let p), .cubic(_, _, let p), .quadratic(_, let p), .arc(_, _, _, _, _, let p): cursor = p
        case .close: cursor = subpathStart
        }
    }

    private mutating func replaceGeometry(_ value: [HostPathCommand]) {
        commands = []; cursor = nil; subpathStart = nil
        for command in value { append(command) }
    }

    /// An arc command from where the outline stands to `end`, the way an `A`
    /// says it: radii across then down, the ellipse's turn, the large-arc and
    /// sweep flags, the end point.
    private mutating func arc(
        to end: Point, radiusX: Double, radiusY: Double,
        rotation: Double = 0, largeArc: Bool, sweep: Bool
    ) {
        append(.arc(radiusX: radiusX, radiusY: radiusY, rotation: rotation, largeArc: largeArc, sweep: sweep, end: end))
    }

    /// A whole circle about `center`, two half turns meeting back at
    /// `start` - a single `A` cannot turn a full circle, its two ends being
    /// one point.
    private mutating func circle(about center: Point, radius: Double, from start: Point, sweep: Bool) {
        let opposite = Point(2 * center.x - start.x, 2 * center.y - start.y)
        arc(to: opposite, radiusX: radius, radiusY: radius, largeArc: true, sweep: sweep)
        arc(to: start, radiusX: radius, radiusY: radius, largeArc: true, sweep: sweep)
    }

    /// Reaches `point` ahead of a segment that starts there: a move when the
    /// outline stands nowhere yet, a line when it stands somewhere else,
    /// nothing when it is there already.
    private mutating func join(to point: Point) {
        guard let tail else {
            move(to: point)
            return
        }
        if tail != point { addLine(to: point) }
    }

    /// Where the outline stands - nil until a move or a segment lands it,
    /// nil when the data does not parse.
    private var tail: Point? { cursor }

    /// The rim point `degrees` round on the circle `radius` about `center` -
    /// 0 to the right, 90 straight down.
    private static func rim(of center: Point, radius: Double, at degrees: Double) -> Point {
        let turned = degrees * .pi / 180
        return Point(center.x + radius * cos(turned), center.y + radius * sin(turned))
    }

    /// `rect` with its corners rounded, in order top leading, top trailing,
    /// bottom trailing, bottom leading - each corner's size how far across
    /// and down its bend reaches, a corner zero on either axis staying
    /// square.
    private mutating func appendRoundedRect(
        _ rect: Rect, topLeading: Size, topTrailing: Size,
        bottomTrailing: Size, bottomLeading: Size
    ) {
        func corner(_ size: Size) -> Size {
            guard size.width > 0, size.height > 0 else { return .zero }
            return Size(min(size.width, max(0, rect.width / 2)), min(size.height, max(0, rect.height / 2)))
        }
        let topLeft = corner(topLeading)
        let topRight = corner(topTrailing)
        let bottomRight = corner(bottomTrailing)
        let bottomLeft = corner(bottomLeading)

        let left = rect.x
        let top = rect.y
        let right = rect.x + rect.width
        let bottom = rect.y + rect.height

        move(to: Point(left + topLeft.width, top))
        addLine(to: Point(right - topRight.width, top))
        if topRight.width > 0 && topRight.height > 0 {
            arc(to: Point(right, top + topRight.height), radiusX: topRight.width, radiusY: topRight.height, largeArc: false, sweep: true)
        }
        addLine(to: Point(right, bottom - bottomRight.height))
        if bottomRight.width > 0 && bottomRight.height > 0 {
            arc(to: Point(right - bottomRight.width, bottom), radiusX: bottomRight.width, radiusY: bottomRight.height, largeArc: false, sweep: true)
        }
        addLine(to: Point(left + bottomLeft.width, bottom))
        if bottomLeft.width > 0 && bottomLeft.height > 0 {
            arc(to: Point(left, bottom - bottomLeft.height), radiusX: bottomLeft.width, radiusY: bottomLeft.height, largeArc: false, sweep: true)
        }
        addLine(to: Point(left, top + topLeft.height))
        if topLeft.width > 0 && topLeft.height > 0 {
            arc(to: Point(left + topLeft.width, top), radiusX: topLeft.width, radiusY: topLeft.height, largeArc: false, sweep: true)
        }
        closeSubpath()
    }
}

extension Path: CustomStringConvertible {
    /// The outline as it stands - the same string `init(_:)` takes.
    nonisolated public var description: String { svg }
}

/// `Path`'s own properties, shared by the control and its `Style<Path>`.
@preconcurrency @MainActor public protocol PathProperties: PropertyContainer {}

extension PathProperties {
    /// The outline, in SVG path syntax - `"M 0,40 L 20,0 L 40,40 Z"`.
    ///
    /// The same value the initializer takes; write it here to give a
    /// `Style<Path>` an outline, or to swap one on a path that already has
    /// modifiers on it.
    public func data(_ value: String) -> Modified {
        modified {
            $0.modifyControl {
                $0.props.removeValue(forKey: PathContract.commands.token)
                $0.write(PathContract.data, value)
            }
        }
    }
}
