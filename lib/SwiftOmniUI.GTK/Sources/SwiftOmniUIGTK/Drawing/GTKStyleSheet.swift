// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIGTK

/// The host's rules for the whole display, each a class named for what it says, which a widget wears to take it.
/// Design: docs/design/platforms/gtk/drawing.md#a-widgets-own-box
@MainActor
enum GTKStyleSheet {
    private static var provider: UnsafeMutablePointer<GtkCssProvider>?
    private static var rules: [String: String] = [:]

    /// The authored bar owns its spacing. Native toolbar styling must not
    /// add another padding or minimum height to the measured contribution.
    static var safeAreaBar: String {
        write("swiftomniui-safe-area-bar", "padding: 0; margin: 0; min-height: 0; border: none;")
        return "swiftomniui-safe-area-bar"
    }

    /// A promoted page header draws the scrolling edge below all native bars.
    /// Suppress only the owning scroller's displaced top effect, not bottom
    /// effects or effects belonging to a nested/local scroller.
    static var mergedTopBarScroll: String {
        let name = "swiftomniui-merged-top-bar-scroll"
        write(name, "", states:
            ".\(name) > undershoot.top, .\(name) > overshoot.top { background: none; box-shadow: none; }\n")
        return name
    }

    /// The class giving a widget `insets` of room between its edge and its content.
    static func padding(_ insets: EdgeInsets) -> String {
        let sides = [insets.top, insets.right, insets.bottom, insets.left].map { max(0, $0.isFinite ? $0 : 0) }
        let name = "swiftomniui-padding-" + sides.map { css($0).replacing(".", with: "_") }.joined(separator: "-")
        write(name, "padding: " + sides.map { css($0) + "px" }.joined(separator: " ") + ";")
        return name
    }

    /// The class writing a flat button's words in the theme's colour for destroying something.
    static var destructiveWords: String {
        write("swiftomniui-destructive", "color: @destructive_color;")
        return "swiftomniui-destructive"
    }

    /// The class painting a bar in `background`, what stands on it in `foreground`; nil where neither is given.
    static func bar(background: GdkRGBA?, foreground: GdkRGBA?) -> String? {
        guard background != nil || foreground != nil else { return nil }
        var name = "swiftomniui-bar"
        var body = ""
        if let background {
            name += "-b" + hex(background)
            body += "background: \(css(background)); box-shadow: none; "
        }
        if let foreground {
            name += "-f" + hex(foreground)
            body += "color: \(css(foreground)); "
        }
        write(name, body)
        return name
    }

    /// The class drawing a button's box: its fill - a little fainter under the pointer and fainter again pressed,
    /// which the color scheme's own states would otherwise lose under it - its outline and its corners' radius; nil where
    /// nothing is given.
    static func box(fill: GdkRGBA?, stroke: GdkRGBA?, strokeWidth: Double?, radius: Double?) -> String? {
        guard fill != nil || stroke != nil || radius != nil else { return nil }
        var name = "swiftomniui-box"
        var body = ""
        var states = ""
        if let fill {
            name += "-f" + hex(fill)
            body += "background: \(css(fill)); box-shadow: none; "
        }
        if let stroke, let strokeWidth {
            name += "-s" + hex(stroke) + "-w" + css(strokeWidth).replacing(".", with: "_")
            body += "border: \(css(strokeWidth))px solid \(css(stroke)); "
        }
        if let radius {
            name += "-r" + css(radius).replacing(".", with: "_")
            body += "border-radius: \(css(radius))px; "
        }
        if var fill {
            let alpha = fill.alpha
            fill.alpha = alpha * Float(PressedFill.underPointer)
            states += ".\(name):hover { background: \(css(fill)); }\n"
            fill.alpha = alpha * Float(PressedFill.pressed)
            states += ".\(name):active { background: \(css(fill)); }\n"
        }
        write(name, body, states: states)
        return name
    }

    /// The class filling a widget's box in `color`.
    static func fill(_ color: GdkRGBA) -> String {
        let name = "swiftomniui-fill-" + hex(color)
        write(name, "background: \(css(color));")
        return name
    }

    /// The class giving a control its tint: the colour `part` of it - its own words and marks where `part` is nil -
    /// is drawn in.
    static func tint(_ color: GdkRGBA, of part: String?) -> String {
        let name = "swiftomniui-tint-" + hex(color) + (part == nil ? "" : "-part")
        if let part {
            write(name, "", states: ".\(name) > \(part) { background-color: \(css(color)); }\n")
        } else {
            write(name, "color: \(css(color));")
        }
        return name
    }

    /// An editor's canvas, faintly filled unless hidden, with no border or focus decoration. Only the canvas's
    /// nodes are cleared: the text view keeps its caret and selection's own drawing.
    static func editor(backgroundHidden: Bool) -> String {
        let name = "swiftomniui-editor" + (backgroundHidden ? "-clear" : "")
        let decoration = "border: none; box-shadow: none; outline: none;"
        let fill = backgroundHidden ? "transparent" : "alpha(currentColor, 0.1)"
        write(name, "background: \(fill); border-radius: 6px; \(decoration)",
              states: ".\(name):focus-within { \(decoration) }\n"
                + ".\(name) > textview, .\(name) > textview > text { background: transparent; \(decoration) }\n")
        return name
    }

    /// The class of a list or a grid: what stands under it shows behind its rows, and an item chosen is shaded in
    /// the colour of its words, as GNOME's sidebars shade theirs - no hue of the theme's own over the page. A row and
    /// a grid's child keep no padding of the theme's: an item stands where SwiftOmniUI's spacing puts it.
    static var collection: String {
        let name = "swiftomniui-collection"
        let chosen = [".\(name) > row:selected", ".\(name) > child:selected"]
        write(name, "background: none;",
              states: ".\(name) > row, .\(name) > child { padding: 0; margin: 0; min-height: 0; min-width: 0; }\n"
                + chosen.joined(separator: ", ") + " { background-color: alpha(currentColor, 0.1); }\n"
                + chosen.map { $0 + ":hover" }.joined(separator: ", ")
                + " { background-color: alpha(currentColor, 0.13); }\n")
        return name
    }

    /// The class giving typed words their look - the font's size, weight, slant and family and the words' colour -
    /// and the placeholder its colour, in a field's own text or as an editor's label; nil where nothing is given.
    static func words(_ look: TextLook, placeholder: GdkRGBA?) -> String? {
        var name = "swiftomniui-words"
        var body = ""
        if let size = look.size, size > 0 {
            name += "-s" + css(size).replacing(".", with: "_")
            body += "font-size: \(css(size))px; "
        }
        if look.attributes.contains(.bold) {
            name += "-b"
            body += "font-weight: bold; "
        }
        if look.attributes.contains(.italic) {
            name += "-i"
            body += "font-style: italic; "
        }
        if let family = look.family, !family.isEmpty {
            name += "-f" + family.utf8.map { String($0, radix: 16) }.joined()
            body += "font-family: \"\(family.replacing("\\", with: "\\\\").replacing("\"", with: "\\\""))\"; "
        }
        if let color = look.rgbaColor {
            name += "-c" + hex(color)
            body += "color: \(css(color)); "
        }
        var states = ""
        if let placeholder {
            name += "-p" + hex(placeholder)
            states = ".\(name) placeholder, .\(name) .\(GTKTextEditorView.placeholderClass) "
                + "{ color: \(css(placeholder)); opacity: 1; }\n"
        }
        guard name != "swiftomniui-words" else { return nil }
        write(name, body, states: states)
        return name
    }

    /// Writes the rule for `name` the first time it is asked for, with the rules for its states, the whole sheet in
    /// the rules' order.
    private static func write(_ name: String, _ body: String, states: String = "") {
        guard rules[name] == nil else { return }
        rules[name] = ".\(name) { \(body) }\n" + states

        let provider = self.provider ?? {
            let made = gtk_css_provider_new()!
            gtk_style_context_add_provider_for_display(
                gdk_display_get_default(), made.opaque, guint(GTK_STYLE_PROVIDER_PRIORITY_APPLICATION))
            self.provider = made
            return made
        }()
        let sheet = rules.keys.sorted().map { rules[$0]! }.joined()
        gtk_css_provider_load_from_string(provider, sheet)
    }

    /// A colour as CSS writes it.
    private static func css(_ color: GdkRGBA) -> String {
        let channels = [color.red, color.green, color.blue].map { String(Int((min(max($0, 0), 1) * 255).rounded())) }
        return "rgba(\(channels.joined(separator: ", ")), \(css(Double(min(max(color.alpha, 0), 1)))))"
    }

    /// A colour's channels in hex, red to alpha.
    private static func hex(_ color: GdkRGBA) -> String {
        [color.red, color.green, color.blue, color.alpha].map { channel in
            let value = Int((min(max(channel, 0), 1) * 255).rounded())
            let digits = String(value, radix: 16, uppercase: true)
            return value < 16 ? "0" + digits : digits
        }.joined()
    }

    /// A number as CSS writes it: whole without a point.
    private static func css(_ number: Double) -> String {
        number == number.rounded() ? String(Int(number)) : String(number)
    }
}
