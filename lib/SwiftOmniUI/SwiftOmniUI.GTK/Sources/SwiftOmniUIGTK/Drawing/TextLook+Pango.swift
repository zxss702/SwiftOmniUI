// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIGTK

/// A look as the Pango attributes GTK draws words with.
/// Design: docs/design/platforms/gtk/controls.md#words
extension TextLook {
    /// Symbols use the requested font height, or the theme's named text size.
    @MainActor
    var symbolPointSize: Double {
        if let size, size > 0 { return size }
        guard let textStyle else { return 16 }
        let roles = ["title-1", "title-2", "title-3", "title-4", "heading", "caption", "body", "body", "caption", "caption", "caption"]
        let probe = GTKLabelView()
        // The font description below is borrowed from this widget's context.
        defer { withExtendedLifetime(probe) {} }
        gtk_widget_add_css_class(probe.widget, roles[Int(textStyle.rawValue)])
        guard let description = pango_context_get_font_description(gtk_widget_get_pango_context(probe.widget))
        else { return 16 }
        let points = Double(pango_font_description_get_size(description)) / Double(PANGO_SCALE)
        let pixels = pango_font_description_get_size_is_absolute(description) != 0 ? points : points * 96 / 72
        return pixels > 0 ? pixels : 16
    }

    /// The words' colour as GTK draws it; nil for GTK's own.
    var rgbaColor: GdkRGBA? { color.flatMap(GTKBrush.rgba) }

    /// What stands behind the words as GTK draws it: a brush's first colour; nil for nothing.
    var rgbaBackground: GdkRGBA? { GTKBrush(background).firstColor }

    /// Puts the look on the words from byte `start` to byte `end` of `list`.
    @MainActor
    func insert(into list: OpaquePointer, from start: UInt32 = 0, to end: UInt32 = UInt32.max) {
        var made: [UnsafeMutablePointer<PangoAttribute>] = []
        let size = size ?? textStyle.map { _ in symbolPointSize }
        if let size, size > 0 { made.append(pango_attr_size_new_absolute(Int32((size * Double(PANGO_SCALE)).rounded()))) }
        // A weight the look names, on Pango's own 1-1000 scale, else the attributes' bold.
        if let weight, weight > 0 {
            made.append(pango_attr_weight_new(PangoWeight(rawValue: UInt32(min(max(weight, 1), 1000)))))
        } else if attributes.contains(.bold) || textStyle == .headline {
            made.append(pango_attr_weight_new(PANGO_WEIGHT_BOLD))
        }
        if attributes.contains(.italic) { made.append(pango_attr_style_new(PANGO_STYLE_ITALIC)) }
        let family = family ?? (design == .monospaced ? "monospace" : design == .serif ? "serif" : nil)
        if let family, !family.isEmpty { made.append(pango_attr_family_new(family)) }
        if let color = rgbaColor {
            let (red, green, blue, alpha) = Self.channels(color)
            made += [pango_attr_foreground_new(red, green, blue), pango_attr_foreground_alpha_new(alpha)]
        }
        if let background = rgbaBackground {
            let (red, green, blue, alpha) = Self.channels(background)
            made += [pango_attr_background_new(red, green, blue), pango_attr_background_alpha_new(alpha)]
        }
        if letterSpacing != 0 {
            made.append(pango_attr_letter_spacing_new(Int32((letterSpacing * Double(PANGO_SCALE)).rounded())))
        }
        if let baselineOffset, baselineOffset != 0 {
            made.append(pango_attr_rise_new(Int32((baselineOffset * Double(PANGO_SCALE)).rounded())))
        }
        if let lineHeight, lineHeight > 0 { made.append(pango_attr_line_height_new(lineHeight)) }
        if decorations.contains(.underline) { made.append(pango_attr_underline_new(PANGO_UNDERLINE_SINGLE)) }
        if decorations.contains(.strikethrough) { made.append(pango_attr_strikethrough_new(1)) }

        for attribute in made {
            attribute.pointee.start_index = start
            attribute.pointee.end_index = end
            pango_attr_list_insert(list, attribute)
        }
    }

    /// A colour's channels as Pango takes them, each 0 to 65535.
    private static func channels(_ color: GdkRGBA) -> (UInt16, UInt16, UInt16, UInt16) {
        func channel(_ value: Float) -> UInt16 { UInt16((min(max(value, 0), 1) * 65535).rounded()) }
        return (channel(color.red), channel(color.green), channel(color.blue), channel(color.alpha))
    }
}
