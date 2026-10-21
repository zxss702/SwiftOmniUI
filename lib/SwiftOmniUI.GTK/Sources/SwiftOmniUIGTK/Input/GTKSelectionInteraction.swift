// SPDX-License-Identifier: Apache-2.0
@_spi(Host) import SwiftOmniUICore
import CSwiftOmniUIGTK

/// Window controllers stay attached only while their selection container is mapped.
@MainActor final class GTKSelectionInteraction {
    weak var view: GTKView?
    var send: (Event, [PropValue]) -> Void
    var active = false
    var point: Point?
    private var ownsCommands = false
    // Borrowed only for identity comparison; the root owns the focused widget.
    private var commandFocus: GTKWidget?
    private var root: GTKWidget?
    private var controllers: [OpaquePointer] = []
    private var tick: guint = 0
    private var lastFrame: gint64 = 0
    private var mapped: gulong = 0, unmapped: gulong = 0

    init(view: GTKView, send: @escaping (Event, [PropValue]) -> Void) {
        self.view = view; self.send = send
        mapped = connectSignal(UnsafeMutableRawPointer(view.widget), "map", number: view.number) { _, data in
            MainActor.assumeIsolated { GTKView.find(viewNumber(data))?.selectionInteraction?.attach() }
        }
        unmapped = connectSignal(UnsafeMutableRawPointer(view.widget), "unmap", number: view.number) { _, data in
            MainActor.assumeIsolated { GTKView.find(viewNumber(data))?.selectionInteraction?.disconnect() }
        }
    }
    func dispose() {
        disconnect()
        if let view {
            g_signal_handler_disconnect(view.widget, mapped)
            g_signal_handler_disconnect(view.widget, unmapped)
        }
    }
    func update(active: Bool, point: [Double]) {
        self.active = active
        self.point = point.count == 2 ? Point(point[0], point[1]) : nil
        attach()
        if self.point != nil, tick == 0, let view, gtk_widget_get_mapped(view.widget) != 0 {
            tick = gtk_widget_add_tick_callback(view.widget, { _, clock, data in
                let time = gdk_frame_clock_get_frame_time(clock)
                return MainActor.assumeIsolated { GTKView.find(viewNumber(data))?.selectionInteraction?.scroll(time: time) ?? false } ? 1 : 0
            }, UnsafeMutableRawPointer(bitPattern: Int(view.number)), nil)
        } else if self.point == nil, tick != 0, let view {
            gtk_widget_remove_tick_callback(view.widget, tick); tick = 0
        }
    }
    private func attach() {
        guard let view, gtk_widget_get_mapped(view.widget) != 0,
              let next = gtk_widget_get_root(view.widget) else { return }
        let widget = UnsafeMutablePointer<GtkWidget>(OpaquePointer(next))
        guard root != widget else { return }
        disconnect(); root = widget; g_object_ref(widget)
        let click = gtk_gesture_click_new()!
        gtk_gesture_single_set_button(click, guint(GDK_BUTTON_PRIMARY))
        gtk_event_controller_set_propagation_phase(click, GTK_PHASE_CAPTURE)
        connectSignal(UnsafeMutableRawPointer(click), "pressed", number: view.number) { _, _, x, y, data in
            MainActor.assumeIsolated { GTKView.find(viewNumber(data))?.selectionInteraction?.pressed(x: x, y: y) }
        }
        let keys = gtk_event_controller_key_new()!
        gtk_event_controller_set_propagation_phase(keys, GTK_PHASE_CAPTURE)
        let callback: @convention(c) (OpaquePointer?, guint, guint, GdkModifierType, gpointer?) -> gboolean = { _, key, _, modifiers, data in
            MainActor.assumeIsolated {
                GTKView.find(viewNumber(data))?.selectionInteraction?.keyPressed(key, modifiers: modifiers) ?? false
            } ? 1 : 0
        }
        g_signal_connect_data(UnsafeMutableRawPointer(keys), "key-pressed", unsafeBitCast(callback, to: GCallback.self),
            UnsafeMutableRawPointer(bitPattern: Int(view.number)), nil, GConnectFlags(rawValue: 0))
        controllers = [click, keys]
        for controller in controllers { gtk_widget_add_controller(widget, controller) }
    }
    private func disconnect() {
        if tick != 0, let view { gtk_widget_remove_tick_callback(view.widget, tick); tick = 0 }
        if let root {
            for controller in controllers { gtk_widget_remove_controller(root, controller) }
            g_object_unref(root)
        }
        controllers = []; root = nil; ownsCommands = false; commandFocus = nil; lastFrame = 0
    }
    private func pressed(x: Double, y: Double) {
        guard let root, let view else { return }
        var input = graphene_point_t(x: Float(x), y: Float(y)), output = graphene_point_t()
        ownsCommands = gtk_widget_compute_point(root, view.widget, &input, &output) != 0
            && output.x >= 0 && output.y >= 0
            && output.x <= Float(gtk_widget_get_width(view.widget)) && output.y <= Float(gtk_widget_get_height(view.widget))
        if ownsCommands, let hit = gtk_widget_pick(root, x, y, GTK_PICK_DEFAULT) {
            var current: GTKWidget? = hit
            while let widget = current {
                if g_type_check_instance_is_a(UnsafeMutablePointer<GTypeInstance>(OpaquePointer(widget)), gtk_editable_get_type()) != 0
                    || g_type_check_instance_is_a(UnsafeMutablePointer<GTypeInstance>(OpaquePointer(widget)), gtk_text_view_get_type()) != 0 {
                    ownsCommands = false; break
                }
                current = gtk_widget_get_parent(widget)
            }
        }
        commandFocus = gtk_root_get_focus(OpaquePointer(root))
        send(.windowPointerPressed, [])
    }
    private func keyPressed(_ key: guint, modifiers: GdkModifierType) -> Bool {
        let focus = root.flatMap { gtk_root_get_focus(OpaquePointer($0)) }
        // A click in selectable text may leave the old editor focused. A later
        // keyboard focus change returns command ownership to the new control.
        if focus != commandFocus { ownsCommands = false }
        guard active || ownsCommands,
              modifiers.rawValue & GDK_CONTROL_MASK.rawValue != 0,
              modifiers.rawValue & (GDK_ALT_MASK.rawValue | GDK_SHIFT_MASK.rawValue) == 0 else { return false }
        if !ownsCommands, let focus,
           g_type_check_instance_is_a(UnsafeMutablePointer<GTypeInstance>(OpaquePointer(focus)), gtk_editable_get_type()) != 0
            || gtk_widget_get_ancestor(focus, gtk_text_view_get_type()) != nil { return false }
        switch key {
        case guint(GDK_KEY_c), guint(GDK_KEY_C): send(.copyRequested, [])
        case guint(GDK_KEY_a), guint(GDK_KEY_A): send(.selectAllRequested, [])
        default: return false
        }
        return true
    }
    private func scroll(time: gint64) -> Bool {
        guard let point, let view else { tick = 0; lastFrame = 0; return false }
        let rate = lastFrame == 0 ? 1 : min(3, max(0, Double(time - lastFrame) / 1_000_000 * 60))
        lastFrame = time
        var ancestor = gtk_widget_get_parent(view.widget)
        while let widget = ancestor {
            ancestor = gtk_widget_get_parent(widget)
            guard g_type_check_instance_is_a(UnsafeMutablePointer<GTypeInstance>(OpaquePointer(widget)), gtk_scrolled_window_get_type()) != 0,
                  let horizontal = gtk_scrolled_window_get_hadjustment(widget.opaque),
                  let vertical = gtk_scrolled_window_get_vadjustment(widget.opaque) else { continue }
            var input = graphene_point_t(x: Float(point.x), y: Float(point.y)), output = graphene_point_t()
            guard gtk_widget_compute_point(view.widget, widget, &input, &output) != 0 else { continue }
            func shifted(_ adjustment: UnsafeMutablePointer<GtkAdjustment>, at position: Double) -> Double {
                let extent = gtk_adjustment_get_page_size(adjustment)
                let amount = position < 28 ? -min(1, (28 - position) / 28) * 16 * rate
                    : position > extent - 28 ? min(1, (position - extent + 28) / 28) * 16 * rate : 0
                let old = gtk_adjustment_get_value(adjustment)
                let next = max(gtk_adjustment_get_lower(adjustment), min(gtk_adjustment_get_upper(adjustment) - extent, old + amount))
                if next != old { gtk_adjustment_set_value(adjustment, next) }
                return next - old
            }
            let dx = shifted(horizontal, at: Double(output.x)), dy = shifted(vertical, at: Double(output.y))
            guard dx != 0 || dy != 0 else { continue }
            let local = Point(point.x + dx, point.y + dy)
            self.point = local
            send(.dragScrolled, [local.propValue])
            break
        }
        return true
    }
}
