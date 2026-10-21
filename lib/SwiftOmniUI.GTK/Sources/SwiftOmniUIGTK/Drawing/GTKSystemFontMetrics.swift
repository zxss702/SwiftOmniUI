// SPDX-License-Identifier: Apache-2.0
@_spi(Host) import SwiftOmniUICore
import CSwiftOmniUIGTK
import CNativeFontShaping

@MainActor enum GTKSystemFontMetrics {
    private struct Key: Hashable {
        let descriptor: FontMetrics.Descriptor
        let context: UInt32
        let map: UInt32
    }
    private static var probes: [Int32: GTKWidget] = [:]
    private static var cache: [Key: FontMetrics] = [:]
    private static var listening = false
    private static var generation: (context: UInt32, map: UInt32)?

    static func read(_ descriptor: FontMetrics.Descriptor) -> FontMetrics? {
        if !listening, let settings = gtk_settings_get_default() {
            listening = true
            for property in ["gtk-font-name", "gtk-theme-name", "gtk-xft-dpi"] {
                connectNotify(UnsafeMutableRawPointer(settings), property, number: 0) { _, _, _ in
                    MainActor.assumeIsolated { GTKSystemFontMetrics.cache.removeAll() }
                }
            }
        }
        let probe: GTKWidget
        if let previous = probes[descriptor.style] { probe = previous }
        else {
            guard let made = gtk_label_new(nil) else { return nil }
            probe = made
            _ = g_object_ref_sink(UnsafeMutableRawPointer(probe))
            if descriptor.style >= 0 && descriptor.style < 11 {
                let roles = ["title-1", "title-2", "title-3", "title-4", "heading", "caption", "body", "body", "caption", "caption", "caption"]
                gtk_widget_add_css_class(probe, roles[Int(descriptor.style)])
            }
            probes[descriptor.style] = probe
        }
        guard let context = gtk_widget_get_pango_context(probe),
              let base = pango_context_get_font_description(context),
              let map = pango_context_get_font_map(context) else { return nil }
        let contextSerial = pango_context_get_serial(context), mapSerial = pango_font_map_get_serial(map)
        let key = Key(descriptor: descriptor, context: contextSerial, map: mapSerial)
        if let result = cache[key] { return result }
        if generation?.map != mapSerial { cache.removeAll() }
        generation = (contextSerial, mapSerial)
        guard let description = pango_font_description_copy(base) else { return nil }
        defer { pango_font_description_free(description) }
        if let family = descriptor.family, !family.isEmpty { pango_font_description_set_family(description, family) }
        else if descriptor.design == 3 { pango_font_description_set_family(description, "monospace") }
        else if descriptor.design == 1 { pango_font_description_set_family(description, "serif") }
        if let size = descriptor.size { pango_font_description_set_absolute_size(description, size * Double(PANGO_SCALE)) }
        if let weight = descriptor.weight, weight > 0 {
            pango_font_description_set_weight(description, PangoWeight(rawValue: UInt32(min(max(weight, 1), 1000))))
        } else if descriptor.attributes & FontAttributes.bold.rawValue != 0 {
            pango_font_description_set_weight(description, PANGO_WEIGHT_BOLD)
        }
        if descriptor.attributes & FontAttributes.italic.rawValue != 0 { pango_font_description_set_style(description, PANGO_STYLE_ITALIC) }
        guard let font = pango_context_load_font(context, description) else { return nil }
        defer { g_object_unref(UnsafeMutableRawPointer(font)) }
        guard let metrics = pango_font_get_metrics(font, pango_context_get_language(context)) else { return nil }
        defer { pango_font_metrics_unref(metrics) }
        let scale = Double(PANGO_SCALE)
        let ascent = Double(pango_font_metrics_get_ascent(metrics)) / scale
        let descent = Double(pango_font_metrics_get_descent(metrics)) / scale
        let height = Double(pango_font_metrics_get_height(metrics)) / scale
        guard let hbFont = pango_font_get_hb_font(font) else { return nil }
        var glyph: hb_codepoint_t = 0
        guard hb_font_get_nominal_glyph(hbFont, 0x48, &glyph) != 0 else { return nil }
        var ink = PangoRectangle()
        pango_font_get_glyph_extents(font, glyph, &ink, nil)
        guard let absolute = pango_font_describe_with_absolute_size(font) else { return nil }
        defer { pango_font_description_free(absolute) }
        let points = Double(pango_font_description_get_size(absolute)) / scale
        let result = FontMetrics(pointSize: points, ascender: ascent, descender: -descent,
                                 leading: max(0, height - ascent - descent), capHeight: max(0, -Double(ink.y) / scale))
        cache[key] = result
        return result
    }
}
