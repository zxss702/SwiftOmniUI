// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIGTK

/// An Image: a panel drawing a picture from the application's folder, its own size, filling the room it is given
/// as the aspect says.
/// Design: docs/design/platforms/gtk/controls.md#pictures
@MainActor
final class GTKImageView: GTKPanelView {
    /// The picture shown, by file name, and whether it was found.
    private(set) var file = ""
    private(set) var found = false

    /// How the picture fills its room.
    private var aspect = ContentMode.center

    /// The file read, its own size in logical pixels, and whether it is an SVG, drawn at the size it shows at.
    private var path: String?
    private var size = LayoutSize(width: 0, height: 0)
    private var isVector = false
    private var symbol: OpaquePointer?
    private var symbolInvalidation: gulong = 0
    private var foreground: HostValue?
    private var loadedSource: ImageSource?
    private var loadedSymbolSize = 0.0
    private var loadedScale: Int32 = 0

    /// The picture's pixels, and the size in device pixels they were drawn at; nil while none are.
    private var texture: OpaquePointer?
    private var drawn: LayoutSize?

    isolated deinit {
        if let texture { g_object_unref(UnsafeMutableRawPointer(texture)) }
        if let symbol {
            if symbolInvalidation != 0 { g_signal_handler_disconnect(UnsafeMutableRawPointer(symbol), symbolInvalidation) }
            g_object_unref(UnsafeMutableRawPointer(symbol))
        }
    }

    /// Shows the picture `source` names, filling its room as `aspect` says. A source naming a symbol shows the
    /// icon theme's icon for it - the platform's own symbols - or the missing-image icon where the name is
    /// unknown.
    func apply(source: ImageSource?, aspect: ContentMode, resizable: Bool = false, font: TextLook = TextLook()) {
        foreground = font.color
        let aspect = resizable ? aspect : .center
        let symbolSize = source?.symbol == nil ? 16 : font.symbolPointSize
        let scale = max(gtk_widget_get_scale_factor(widget), 1)
        if found, source == loadedSource, symbolSize == loadedSymbolSize, scale == loadedScale {
            self.aspect = aspect
            gtk_widget_queue_draw(widget)
            return
        }
        loadedSource = source
        loadedSymbolSize = symbolSize
        loadedScale = scale
        if let symbol {
            if symbolInvalidation != 0 { g_signal_handler_disconnect(UnsafeMutableRawPointer(symbol), symbolInvalidation) }
            g_object_unref(UnsafeMutableRawPointer(symbol))
        }
        symbol = nil
        symbolInvalidation = 0
        file = source?.file ?? ""
        self.aspect = aspect
        path = source?.bitmap == nil && source?.symbol == nil && !file.isEmpty ? GTKPictures.path(of: file) : nil
        let bitmapTexture = source?.bitmap.flatMap(GTKMemoryImages.texture)
        if let name = source?.symbol {
            symbol = GTKSymbols.paintable(of: name, size: Int32(symbolSize.rounded(.up)), scale: scale)
        }
        if let symbol {
            symbolInvalidation = connectSignal(UnsafeMutableRawPointer(symbol), "invalidate-contents", number: number) { _, data in
                MainActor.assumeIsolated {
                    if let view = GTKView.find(viewNumber(data)) { gtk_widget_queue_draw(view.widget) }
                }
            }
        }
        found = bitmapTexture != nil || symbol != nil || path != nil
        if !found, let name = source?.symbol ?? (file.isEmpty ? nil : file) {
            GTKRenderer.log.error("no picture or symbol for \(name)")
        }

        var width: Int32 = 0
        var height: Int32 = 0
        if let path { _ = gdk_pixbuf_get_file_info(path, &width, &height) }
        size = source?.bitmap.map { LayoutSize(width: $0.size.width, height: $0.size.height) }
            ?? LayoutSize(width: Double(max(width, 0)), height: Double(max(height, 0)))
        if let symbol {
            let intrinsic = LayoutSize(width: Double(gdk_paintable_get_intrinsic_width(symbol)),
                                       height: Double(gdk_paintable_get_intrinsic_height(symbol)))
            size = intrinsic.height > 0 ? PictureArithmetic.glyph(intrinsic, height: symbolSize)
                : LayoutSize(width: symbolSize, height: symbolSize)
        }
        isVector = path?.lowercased().hasSuffix(".svg") == true
        replaceTexture(with: bitmapTexture)
        drawn = nil
        placingLayout?.invalidateMeasurements()
        gtk_widget_queue_resize(widget)
    }

    /// The picture's own size, whatever room is offered.
    /// Design: docs/design/platforms/gtk/controls.md#pictures
    override func measure(across: Bool, forSize: Int32) -> Double {
        across ? size.width : size.height
    }

    override func allocate(width: Double, height: Double) {
        read(for: LayoutSize(width: width, height: height))
    }

    /// Reads the picture's pixels for a room: a bitmap once, an SVG at the size it shows at in the room, at the
    /// display's scale - again only for more pixels, so a size in animation does not read it every frame. An SVG
    /// keeps its own proportions as it is read, so a stretched one is read covering the room and drawn squeezed
    /// into it.
    /// Design: docs/design/platforms/gtk/controls.md#pictures
    private func read(for room: LayoutSize) {
        guard let path, size.width > 0, size.height > 0, room.width > 0, room.height > 0 else { return }
        guard isVector else {
            if texture == nil { replaceTexture(with: gdk_texture_new_from_filename(path, nil)) }
            return
        }

        let covering = max(room.width / size.width, room.height / size.height)
        let placed = place(in: room)
        let shown = aspect == .stretch
            ? LayoutSize(width: size.width * covering, height: size.height * covering)
            : LayoutSize(width: placed.width, height: placed.height)
        let scale = Double(max(gtk_widget_get_scale_factor(widget), 1))
        let wanted = LayoutSize(width: (shown.width * scale).rounded(.up), height: (shown.height * scale).rounded(.up))
        if let drawn, drawn.width >= wanted.width, drawn.height >= wanted.height { return }

        guard let pixbuf = gdk_pixbuf_new_from_file_at_scale(path, Int32(wanted.width), Int32(wanted.height), 1, nil)
        else { return }
        replaceTexture(with: gdk_texture_new_for_pixbuf(pixbuf))
        g_object_unref(UnsafeMutableRawPointer(pixbuf))
        drawn = wanted
        gtk_widget_queue_draw(widget)
    }

    /// Where the picture stands in a room at the origin, as the aspect says (`PictureArithmetic.place`).
    private func place(in room: LayoutSize) -> Rect {
        PictureArithmetic.place(size, in: room, aspect: aspect)
    }

    override func draw(_ snapshot: OpaquePointer, width: Double, height: Double) {
        if let symbol {
            let place = place(in: LayoutSize(width: width, height: height))
            guard place.width > 0, place.height > 0 else { return }
            var tint = GdkRGBA()
            gtk_widget_get_color(widget, &tint)
            if let own = foreground.flatMap(GTKBrush.rgba) { tint = own }
            var origin = graphene_point_t(x: Float(place.x), y: Float(place.y))
            gtk_snapshot_save(snapshot)
            gtk_snapshot_translate(snapshot, &origin)
            // All symbolic roles use the foreground in monochrome mode.
            // Keep the native paintable, including theme fallback and HiDPI.
            let colors = [tint, tint, tint, tint]
            colors.withUnsafeBufferPointer {
                gtk_symbolic_paintable_snapshot_symbolic(symbol, snapshot, place.width, place.height,
                                                         $0.baseAddress, gsize($0.count))
            }
            gtk_snapshot_restore(snapshot)
            return
        }
        read(for: LayoutSize(width: width, height: height))
        guard let texture else { return }

        let place = place(in: LayoutSize(width: width, height: height))
        var bounds = graphene_rect_t(
            origin: graphene_point_t(x: Float(place.x), y: Float(place.y)),
            size: graphene_size_t(width: Float(place.width), height: Float(place.height)))
        gtk_snapshot_append_texture(snapshot, texture, &bounds)
    }

    private func replaceTexture(with texture: OpaquePointer?) {
        if let old = self.texture { g_object_unref(UnsafeMutableRawPointer(old)) }
        self.texture = texture
    }
}
