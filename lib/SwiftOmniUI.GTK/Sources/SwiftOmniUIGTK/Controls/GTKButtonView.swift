// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIGTK

/// A `GtkButton`: its caption and how it looks, whether it takes a press, and the click it raises.
@MainActor
final class GTKButtonView: GTKView {
    /// What the button does when the user clicks it.
    var onClicked: (() -> Void)?

    /// What a staying-pressed button reports when a press flips it - `isOn`
    /// worn on the element at all makes it one.
    var onToggled: ((Bool) -> Void)?

    /// Whether the press keeps - `isOn` worn at all. A button that keeps
    /// nothing has its active taken back on each click.
    private var toggleable = false

    /// A button, or one that stays pressed in while what it turns on is on.
    init(toggles: Bool = false) {
        super.init { _ in toggles ? gtk_toggle_button_new() : gtk_button_new() }
        connect("clicked") { _, data in
            MainActor.assumeIsolated { GTKView.find(viewNumber(data))?.clicked() }
        }
    }

    /// The shortcut's controller while the button has one.
    private var shortcutController: OpaquePointer?

    /// The keyboard shortcut, as a controller that activates the button for
    /// the key and modifiers named - Control for the platform's command key.
    func setShortcut(_ shortcut: KeyboardShortcut?) {
        if let controller = shortcutController {
            gtk_widget_remove_controller(widget, controller)
            shortcutController = nil
        }
        guard let shortcut else { return }
        let keyval = Self.keyval(shortcut.key.name)
        guard keyval != GDK_KEY_VoidSymbol else { return }
        var mask = GdkModifierType(rawValue: 0).rawValue
        if shortcut.modifiers.contains(.command) || shortcut.modifiers.contains(.control) {
            mask |= GDK_CONTROL_MASK.rawValue
        }
        if shortcut.modifiers.contains(.shift) { mask |= GDK_SHIFT_MASK.rawValue }
        if shortcut.modifiers.contains(.option) { mask |= GDK_ALT_MASK.rawValue }
        let modifiers = GdkModifierType(rawValue: mask)
        guard let controller = gtk_shortcut_controller_new(),
              let trigger = gtk_keyval_trigger_new(keyval, modifiers),
              let action = gtk_callback_action_new({ target, _, _ in
                  target.map { gtk_widget_activate($0) } ?? 0
              }, widget, nil),
              let made = gtk_shortcut_new(trigger, action)
        else { return }
        gtk_shortcut_controller_add_shortcut(controller, made)
        gtk_widget_add_controller(widget, controller)
        shortcutController = controller
    }

    /// The key's GDK keyval: the named keys by the names GDK gives them, a
    /// character by itself.
    private static func keyval(_ name: String) -> guint {
        let gdk: String = switch name {
        case "return", "defaultaction": "Return"
        case "escape", "cancelaction": "Escape"
        case "tab": "Tab"
        case "space": "space"
        case "delete": "BackSpace"
        case "deleteforward": "Delete"
        case "up": "Up"
        case "down": "Down"
        case "left": "Left"
        case "right": "Right"
        case "home": "Home"
        case "end": "End"
        case "pageup": "Page_Up"
        case "pagedown": "Page_Down"
        default: name
        }
        return gdk.withCString { gdk_keyval_from_name($0) }
    }

    /// The logical style's CSS classes on the widget now.
    private var styleClasses: [String] = []

    /// The logical style, mapped to the look GTK's own buttons take for it.
    func setStyle(_ style: ButtonStyleKind?) {
        let wanted: [String] = switch style ?? .automatic {
        case .borderedProminent: ["suggested-action"]
        case .plain, .borderless: ["flat"]
        case .link: ["flat", "link"]
        default: []
        }
        for name in styleClasses where !wanted.contains(name) { gtk_widget_remove_css_class(widget, name) }
        for name in wanted where !styleClasses.contains(name) { gtk_widget_add_css_class(widget, name) }
        styleClasses = wanted
    }

    /// How the caption's words look.
    private(set) var look = TextLook()

    /// The style sheet's class drawing the button's box.
    private var boxClass: String?

    /// The caption's words and picture's name - a symbol's or a file's - as the element last said them.
    private var caption = ""
    private var picture: String?

    /// Whether the button shows a picture now, which a caption of words alone takes away again.
    private var showsPicture = false

    /// Whether a picture stands in place of the words - a header bar's button, as a toolbar's `Label` shows its
    /// icon alone - the words its tooltip and its name to assistive technology.
    var showsPictureAlone = false {
        didSet { if showsPictureAlone != oldValue { writeCaption() } }
    }

    /// The caption.
    func setText(_ text: String) {
        caption = text
        writeCaption()
    }

    /// The picture beside the caption - a symbol or a picture's file; nil for the words alone.
    func setPicture(_ source: ImageSource?) {
        setPictureNamed(source.flatMap { $0.symbol ?? ($0.file.isEmpty ? nil : $0.file) })
    }

    /// The picture by the name the theme or a file answers to; nil for the words alone.
    func setPictureNamed(_ name: String?) {
        guard name != picture else { return }
        picture = name
        writeCaption()
    }

    /// Shows the caption as SwiftUI does, through the platform's own buttons: a theme's symbol alone where the
    /// words stand aside - GTK's icon button - or beside the words in libadwaita's button content; a picture's
    /// file alone; the words alone otherwise.
    private func writeCaption() {
        let button = widget.of(GtkButton.self)
        let name = picture
        let alone = showsPictureAlone || caption.isEmpty
        if showsPicture {
            gtk_widget_remove_css_class(widget, "image-button")
            gtk_widget_set_tooltip_text(widget, nil)
            showsPicture = false
        }
        if let name, GTKSymbols.has(name) {
            if alone {
                gtk_button_set_icon_name(button, name)
                if !caption.isEmpty { nameByCaption(caption) }
            } else {
                let content = adw_button_content_new()!
                adw_button_content_set_icon_name(content.opaque, name)
                adw_button_content_set_label(content.opaque, caption)
                gtk_button_set_child(button, content)
            }
            showsPicture = true
            return
        }
        if let name, alone, setIcon(name, size: 16, caption: caption) {
            showsPicture = true
            return
        }
        gtk_button_set_label(button, caption)
        writeLook()
    }

    /// Names the button by `caption` where a picture stands in place of it: its tooltip, and its name to
    /// assistive technology.
    private func nameByCaption(_ caption: String) {
        gtk_widget_set_tooltip_text(widget, caption)
        var property = GTK_ACCESSIBLE_PROPERTY_LABEL
        var label = GValue()
        g_value_init(&label, g_type_from_name("gchararray"))
        g_value_set_string(&label, caption)
        gtk_accessible_update_property_value(widget.opaque, 1, &property, &label)
        g_value_unset(&label)
    }

    /// Changes how the caption's words look.
    func setLook(_ change: (inout TextLook) -> Void) {
        change(&look)
        writeLook()
    }

    /// Writes the look on the label the button shows its caption in.
    private func writeLook() {
        guard let label = gtk_button_get_child(widget.of(GtkButton.self)),
              g_type_check_instance_is_a(label.of(GTypeInstance.self), gtk_label_get_type()) != 0
        else { return }
        let list = pango_attr_list_new()!
        look.insert(into: list)
        gtk_label_set_attributes(label.opaque, list)
        pango_attr_list_unref(list)
    }

    /// The button's box - its fill, its outline's colour and width, and its shape - as a class of the host's style
    /// sheet; what is nil stays the platform's.
    /// Design: docs/design/platforms/gtk/controls.md#a-buttons-box
    func setBox(fill: HostValue?, stroke: HostValue?, strokeWidth: Double?, shape: HostValue?) {
        let radius: Double? = switch shape.map(BoxArithmetic.outline) {
        case .roundedRectangle(let radius)?: radius
        case .unevenRoundedRectangle(let cornerRadius)?: BoxArithmetic.clockwise(cornerRadius).max() ?? 0
        case .ellipse?, .capsule?, .circle?: 9999
        case .rectangle?: 0
        case nil: nil
        }
        let drawn = GTKStyleSheet.box(
            fill: fill.flatMap { GTKBrush($0).firstColor }, stroke: stroke.flatMap { GTKBrush($0).firstColor },
            strokeWidth: stroke == nil ? nil : BoxArithmetic.outlineWidth(stroke: stroke, width: strokeWidth),
            radius: radius)
        guard drawn != boxClass else { return }
        if let boxClass { gtk_widget_remove_css_class(widget, boxClass) }
        if let drawn { gtk_widget_add_css_class(widget, drawn) }
        boxClass = drawn
    }

    /// A picture in place of the caption, `size` logical pixels across; the caption stays the button's name to
    /// assistive technology and its tooltip. Whether there was such a picture.
    @discardableResult
    func setIcon(_ name: String, size: Int32, caption: String) -> Bool {
        guard let image = GTKPictures.icon(named: name, size: size) else { return false }
        gtk_button_set_child(widget.of(GtkButton.self), image)
        gtk_widget_add_css_class(widget, "image-button")
        nameByCaption(caption)
        return true
    }

    /// The caption the button shows now, read back from GTK.
    var text: String {
        gtk_button_get_label(widget.of(GtkButton.self)).map { String(cString: $0) } ?? ""
    }

    /// The staying-pressed look, or none: `nil` for a momentary button - a
    /// widget made with `toggles` is required, or the cast below fails.
    func setOn(_ on: Bool?) {
        toggleable = on != nil
        gtk_toggle_button_set_active(widget.of(GtkToggleButton.self), (on ?? false) ? 1 : 0)
    }

    /// The picture and the caption stand in the button's direction too.
    override func setDirection(_ direction: GtkTextDirection) {
        super.setDirection(direction)
        if let content = gtk_button_get_child(widget.of(GtkButton.self)) { gtk_widget_set_direction(content, direction) }
    }

    override func clicked() {
        onClicked?()
        // Only a widget made with `toggles` answers the toggle calls.
        guard g_type_check_instance_is_a(widget.of(GTypeInstance.self), gtk_toggle_button_get_type()) != 0
        else { return }
        if toggleable {
            onToggled?(gtk_toggle_button_get_active(widget.of(GtkToggleButton.self)) != 0)
        } else {
            // A momentary button must not keep the toggle's pressed look.
            gtk_toggle_button_set_active(widget.of(GtkToggleButton.self), 0)
        }
    }

    override func detach() {
        super.detach()
        onClicked = nil
        onToggled = nil
    }
}
