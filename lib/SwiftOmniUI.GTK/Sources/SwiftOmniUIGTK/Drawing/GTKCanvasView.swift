// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIGTK

/// A Canvas: its drawing replayed in order into the panel's snapshot - the instructions and the pen the host layer
/// reads (`CanvasInstruction`, `CanvasPen`), its arcs the host layer's curves - clipped to its own frame; a press on
/// it is followed from down to up by a drag gesture of the view's own.
/// Design: docs/design/platforms/gtk/drawing.md#a-canvas
@MainActor
final class GTKCanvasView: GTKPanelView {
    private static var bitmapCanvas: GTKCanvasView?
    static func bitmap(size: Size, scale: Double, drawing: [DrawCommand]) -> PicturePixels? {
        let pixelWidth = (size.width * scale).rounded(.up)
        let pixelHeight = (size.height * scale).rounded(.up)
        guard scale.isFinite, scale > 0, size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0,
              pixelWidth.isFinite, pixelHeight.isFinite,
              pixelWidth > 0, pixelHeight > 0, pixelWidth <= 32768, pixelHeight <= 32768 else { return nil }
        let width = Int(pixelWidth), height = Int(pixelHeight)
        if bitmapCanvas == nil { bitmapCanvas = GTKCanvasView() }
        guard let canvas = bitmapCanvas, let snapshot = gtk_snapshot_new() else { return nil }
        canvas.instructions = CanvasInstruction.instructions(drawing)
        canvas.draw(snapshot, width: size.width, height: size.height)
        let node = gtk_snapshot_free_to_node(snapshot)
        defer { if let node { gsk_render_node_unref(node) } }
        guard let surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, Int32(width), Int32(height)) else { return nil }
        defer { cairo_surface_destroy(surface) }
        guard cairo_surface_status(surface) == CAIRO_STATUS_SUCCESS, let cr = cairo_create(surface) else { return nil }
        defer { cairo_destroy(cr) }
        guard cairo_status(cr) == CAIRO_STATUS_SUCCESS else { return nil }
        cairo_scale(cr, scale, scale)
        if let node { gsk_render_node_draw(node, cr) }
        cairo_surface_flush(surface)
        guard cairo_status(cr) == CAIRO_STATUS_SUCCESS, cairo_surface_status(surface) == CAIRO_STATUS_SUCCESS,
              let bytes = cairo_image_surface_get_data(surface) else { return nil }
        let stride = Int(cairo_image_surface_get_stride(surface))
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height { for x in 0..<width {
            let from = y * stride + x * 4, to = (y * width + x) * 4
            #if _endian(little)
            rgba[to] = bytes[from + 2]; rgba[to + 1] = bytes[from + 1]; rgba[to + 2] = bytes[from]; rgba[to + 3] = bytes[from + 3]
            #else
            rgba[to] = bytes[from + 1]; rgba[to + 1] = bytes[from + 2]; rgba[to + 2] = bytes[from + 3]; rgba[to + 3] = bytes[from]
            #endif
        } }
        return PicturePixels(width: width, height: height, rgba: rgba)
    }

    var onPressed: ((Point) -> Void)?
    var onDragged: ((Point) -> Void)?
    var onReleased: ((Point) -> Void)?

    private var instructions: [CanvasInstruction] = []
    private var drawnCommands: [DrawCommand]?
    private var requestedSize: (element: ElementId, size: Size)?

    override init() {
        super.init()

        let drag = gtk_gesture_drag_new()!
        gtk_gesture_single_set_button(drag, 0)
        gtk_widget_add_controller(widget, drag)
        connectSignal(UnsafeMutableRawPointer(drag), "drag-begin", number: number) { _, x, y, data in
            let number = viewNumber(data)
            MainActor.assumeIsolated {
                (GTKView.find(number) as? GTKCanvasView)?.onPressed?(Point(x: x, y: y))
            }
        }
        connectSignal(UnsafeMutableRawPointer(drag), "drag-update", number: number) { gesture, x, y, data in
            let number = viewNumber(data)
            nonisolated(unsafe) let gesture = gesture
            MainActor.assumeIsolated {
                (GTKView.find(number) as? GTKCanvasView)?.onDragged?(GTKCanvasView.dragPoint(gesture, moved: (x, y)))
            }
        }
        connectSignal(UnsafeMutableRawPointer(drag), "drag-end", number: number) { gesture, x, y, data in
            let number = viewNumber(data)
            nonisolated(unsafe) let gesture = gesture
            MainActor.assumeIsolated {
                (GTKView.find(number) as? GTKCanvasView)?.onReleased?(GTKCanvasView.dragPoint(gesture, moved: (x, y)))
            }
        }
    }

    /// Where a drag stands: the point the press is at now, in the view; the offset it reports is the fallback.
    private static func dragPoint(_ gesture: UnsafeMutableRawPointer?, moved: (Double, Double)) -> Point {
        var x = 0.0
        var y = 0.0
        let single = OpaquePointer(gesture)
        guard gtk_gesture_get_point(single, gtk_gesture_single_get_current_sequence(single), &x, &y) != 0
        else { return Point(x: moved.0, y: moved.1) }
        return Point(x: x, y: y)
    }

    /// The drawing, as its contract declares it; none draws nothing.
    func apply(_ drawing: [DrawCommand]?) {
        let commands = drawing ?? []
        guard commands != drawnCommands else { return }
        drawnCommands = commands
        instructions = CanvasInstruction.instructions(commands)
        gtk_widget_queue_draw(widget)
    }

    override func allocate(width: Double, height: Double) {
        guard let element = sourceElement,
              width.isFinite, height.isFinite, width > 0, height > 0 else { return }
        let size = Size(width, height)
        guard requestedSize?.element != element.id || requestedSize?.size != size else { return }
        requestedSize = (element.id, size)
        if let commands = CoreLink().canvasDrawing(for: element.id, size: size) {
            apply(commands)
        }
    }

    /// A canvas has no size of its own: it takes the room its layout gives it.
    override func measure(across: Bool, forSize: Int32) -> Double {
        0
    }

    /// The room `text` takes drawn in the font `look` names, measured by a Pango layout of this widget's own -
    /// the same attributes `insert` puts on the words a label wears - wrapped at `maximumWidth` where one is
    /// given, each paragraph one line else. The `measureText` act's answer.
    func measureText(_ text: String, font look: TextLook, maximumWidth: Double?) -> Size {
        guard let layout = gtk_widget_create_pango_layout(widget, text) else { return .zero }
        defer { g_object_unref(UnsafeMutableRawPointer(layout)) }

        let attributes = pango_attr_list_new()!
        look.insert(into: attributes)
        pango_layout_set_attributes(layout, attributes)
        pango_attr_list_unref(attributes)

        if let maximumWidth, maximumWidth.isFinite {
            pango_layout_set_width(layout, Int32((max(0, maximumWidth) * Double(PANGO_SCALE)).rounded()))
            pango_layout_set_wrap(layout, PANGO_WRAP_WORD)
        }

        var measured = (width: Int32(0), height: Int32(0))
        pango_layout_get_pixel_size(layout, &measured.width, &measured.height)
        return Size(width: Double(measured.width), height: Double(measured.height))
    }

    override func draw(_ snapshot: OpaquePointer, width: Double, height: Double) {
        var bounds = Self.rect(0, 0, width, height)
        gtk_snapshot_push_clip(snapshot, &bounds)
        defer { gtk_snapshot_pop(snapshot) }

        var pen = CanvasPen()
        var saved = 0
        for instruction in instructions {
            if pen.take(instruction) {
                if instruction == .saveState {
                    gtk_snapshot_save(snapshot)
                    saved += 1
                } else if instruction == .restoreState, saved > 0 {
                    gtk_snapshot_restore(snapshot)
                    saved -= 1
                }
                continue
            }
            draw(instruction, pen: pen, in: snapshot)
        }
        while saved > 0 {
            gtk_snapshot_restore(snapshot)
            saved -= 1
        }
    }

    override func detach() {
        super.detach()
        requestedSize = nil
        drawnCommands = nil
    }

    private func draw(_ instruction: CanvasInstruction, pen: CanvasPen, in snapshot: OpaquePointer) {
        switch instruction {
        case .drawLine(let from, let to):
            stroke(Self.path([.move(from), .line(to)]), pen: pen, in: snapshot)
        case .drawRectangle(let room):
            stroke(Self.path(Self.rectangle(room)), pen: pen, in: snapshot)
        case .drawRoundedRectangle(let room, let radius):
            stroke(Self.rounded(room, radius), pen: pen, in: snapshot)
        case .drawEllipse(let room):
            stroke(Self.rounded(room, room.width / 2, room.height / 2), pen: pen, in: snapshot)
        case .drawArc(let room, let start, let end, let clockwise, let closed):
            stroke(Self.path(CanvasArithmetic.arc(
                in: room, start: start, end: end, clockwise: clockwise, closed: closed, wedge: false)),
                pen: pen, in: snapshot)
        case .drawPath(let curves):
            stroke(Self.path(curves), pen: pen, in: snapshot)
        case .fillRectangle(let room):
            fill(Self.path(Self.rectangle(room)), pen: pen, in: snapshot)
        case .fillRoundedRectangle(let room, let radius):
            fill(Self.rounded(room, radius), pen: pen, in: snapshot)
        case .fillEllipse(let room):
            fill(Self.rounded(room, room.width / 2, room.height / 2), pen: pen, in: snapshot)
        case .fillArc(let room, let start, let end, let clockwise):
            fill(Self.path(CanvasArithmetic.arc(
                in: room, start: start, end: end, clockwise: clockwise, closed: true, wedge: true)),
                pen: pen, in: snapshot)
        case .fillPath(let curves):
            fill(Self.path(curves), pen: pen, in: snapshot)
        case .drawText(let text, let room, let across, let down):
            draw(text: text, in: room, horizontal: across, vertical: down, pen: pen, in: snapshot)
        case .translate(let x, let y):
            var corner = graphene_point_t(x: Float(x), y: Float(y))
            Self.transform(snapshot, gsk_transform_translate(nil, &corner))
        case .rotate(let degrees):
            Self.transform(snapshot, gsk_transform_rotate(nil, Float(degrees)))
        case .scale(let x, let y):
            Self.transform(snapshot, gsk_transform_scale(nil, Float(x), Float(y)))
        default:
            break
        }
    }

    /// `transform` takes effect on what the snapshot draws from here; the call keeps no reference of its own.
    private static func transform(_ snapshot: OpaquePointer, _ transform: OpaquePointer?) {
        gtk_snapshot_transform(snapshot, transform)
        if let transform { gsk_transform_unref(transform) }
    }

    /// Outlines `path` with the pen's stroke colour, width, cap and join.
    private func stroke(_ path: OpaquePointer?, pen: CanvasPen, in snapshot: OpaquePointer) {
        guard let path else { return }
        defer { gsk_path_unref(path) }
        guard pen.strokeWidth > 0, var color = GTKBrush.rgba(pen.stroke) else { return }
        color.alpha *= Float(pen.alpha)

        let outline = gsk_stroke_new(Float(pen.strokeWidth))
        defer { gsk_stroke_free(outline) }
        gsk_stroke_set_line_cap(
            outline,
            pen.strokeCap == .round ? GSK_LINE_CAP_ROUND
                : pen.strokeCap == .square ? GSK_LINE_CAP_SQUARE : GSK_LINE_CAP_BUTT)
        gsk_stroke_set_line_join(
            outline,
            pen.strokeJoin == .round ? GSK_LINE_JOIN_ROUND
                : pen.strokeJoin == .bevel ? GSK_LINE_JOIN_BEVEL : GSK_LINE_JOIN_MITER)

        gsk_stroke_set_miter_limit(outline, Float(pen.strokeMiter))
        let dashes = pen.strokeDash.map(Float.init)
        if dashes.contains(where: { $0 > 0 }) {
            gsk_stroke_set_dash(outline, dashes, gsize(dashes.count))
            gsk_stroke_set_dash_offset(outline, Float(pen.strokePhase))
        }
        var bounds = graphene_rect_t()
        guard gsk_path_get_stroke_bounds(path, outline, &bounds) != 0 else { return }
        gtk_snapshot_push_stroke(snapshot, path, outline)
        gtk_snapshot_append_color(snapshot, &color, &bounds)
        gtk_snapshot_pop(snapshot)
    }

    /// Fills `path` with the pen's fill colour, by the rule the pen says.
    private func fill(_ path: OpaquePointer?, pen: CanvasPen, in snapshot: OpaquePointer) {
        guard let path else { return }
        defer { gsk_path_unref(path) }
        guard var color = GTKBrush.rgba(pen.fill) else { return }
        color.alpha *= Float(pen.alpha)

        var bounds = graphene_rect_t()
        guard gsk_path_get_bounds(path, &bounds) != 0 else { return }
        gtk_snapshot_push_fill(snapshot, path, pen.fillEvenOdd ? GSK_FILL_RULE_EVEN_ODD : GSK_FILL_RULE_WINDING)
        gtk_snapshot_append_color(snapshot, &color, &bounds)
        gtk_snapshot_pop(snapshot)
    }

    /// Text in its box, placed across and down it as the alignments say and cut at its edges.
    private func draw(
        text: String, in room: Rect, horizontal across: TextAlignment, vertical down: TextAlignment,
        pen: CanvasPen, in snapshot: OpaquePointer
    ) {
        guard var color = GTKBrush.rgba(pen.text), let layout = gtk_widget_create_pango_layout(widget, text)
        else { return }
        defer { g_object_unref(UnsafeMutableRawPointer(layout)) }
        color.alpha *= Float(pen.alpha)

        if let description = pango_font_description_new() {
            if let size = pen.fontSize, size > 0 {
                pango_font_description_set_absolute_size(description, size * Double(PANGO_SCALE))
            }
            if !pen.fontFamily.isEmpty { pango_font_description_set_family(description, pen.fontFamily) }
            pango_font_description_set_weight(description, PangoWeight(rawValue: UInt32(min(1000, max(1, pen.fontWeight)))))
            pango_font_description_set_style(description, pen.fontItalic ? PANGO_STYLE_ITALIC : PANGO_STYLE_NORMAL)
            pango_layout_set_font_description(layout, description)
            pango_font_description_free(description)
        }

        var measured = (width: Int32(0), height: Int32(0))
        pango_layout_get_pixel_size(layout, &measured.width, &measured.height)
        let across: Double = switch across {
        case .center: (room.width - Double(measured.width)) / 2
        case .end: room.width - Double(measured.width)
        default: 0
        }
        let down: Double = switch down {
        case .center: (room.height - Double(measured.height)) / 2
        case .end: room.height - Double(measured.height)
        default: 0
        }
        let x = room.x + across
        let y = room.y + down

        gtk_snapshot_save(snapshot)
        defer { gtk_snapshot_restore(snapshot) }
        var corner = graphene_point_t(x: Float(x), y: Float(y))
        Self.transform(snapshot, gsk_transform_translate(nil, &corner))
        var clip = Self.rect(Float(room.x - x), Float(room.y - y), Float(room.width), Float(room.height))
        gtk_snapshot_push_clip(snapshot, &clip)
        gtk_snapshot_append_layout(snapshot, layout, &color)
        gtk_snapshot_pop(snapshot)
    }

    /// The path the flat curves draw; an empty one draws nothing.
    private static func path(_ curves: [HostCurveCommand]) -> OpaquePointer? {
        guard !curves.isEmpty else { return nil }
        let builder = gsk_path_builder_new()!
        for curve in curves {
            switch curve {
            case .move(let point):
                gsk_path_builder_move_to(builder, Float(point.x), Float(point.y))
            case .line(let point):
                gsk_path_builder_line_to(builder, Float(point.x), Float(point.y))
            case .cubic(let first, let second, let end):
                gsk_path_builder_cubic_to(
                    builder, Float(first.x), Float(first.y), Float(second.x), Float(second.y),
                    Float(end.x), Float(end.y))
            case .quadratic(let control, let end):
                gsk_path_builder_quad_to(builder, Float(control.x), Float(control.y), Float(end.x), Float(end.y))
            case .close:
                gsk_path_builder_close(builder)
            }
        }
        return gsk_path_builder_free_to_path(builder)
    }

    /// A rectangle's outline as flat curves, from its top left around.
    private static func rectangle(_ room: Rect) -> [HostCurveCommand] {
        [
            .move(Point(x: room.x, y: room.y)),
            .line(Point(x: room.x + room.width, y: room.y)),
            .line(Point(x: room.x + room.width, y: room.y + room.height)),
            .line(Point(x: room.x, y: room.y + room.height)),
            .close,
        ]
    }

    /// A `room` rounded by `radius` across and down at each corner - the whole
    /// corner being a circle, the path an ellipse draws as.
    private static func rounded(_ room: Rect, _ across: Double, _ down: Double) -> OpaquePointer? {
        var corners = GTKOutline.rounded(
            rect(room.x, room.y, room.width, room.height),
            corners: (0..<4).map { _ in graphene_size_t(width: Float(max(0, across)), height: Float(max(0, down))) })
        let builder = gsk_path_builder_new()!
        gsk_path_builder_add_rounded_rect(builder, &corners)
        return gsk_path_builder_free_to_path(builder)
    }

    /// A `room` rounded by `radius` at each corner.
    private static func rounded(_ room: Rect, _ radius: Double) -> OpaquePointer? {
        rounded(room, radius, radius)
    }

    private static func rect<Number: BinaryFloatingPoint>(
        _ x: Number, _ y: Number, _ width: Number, _ height: Number
    ) -> graphene_rect_t {
        graphene_rect_t(
            origin: graphene_point_t(x: Float(x), y: Float(y)),
            size: graphene_size_t(width: Float(width), height: Float(height)))
    }
}
