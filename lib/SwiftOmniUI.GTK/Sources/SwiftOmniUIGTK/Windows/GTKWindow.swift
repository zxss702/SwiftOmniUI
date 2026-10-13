// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIGTK

/// An application window of libadwaita, showing a page in a frame of its own - its header bar the window's title
/// bar - or an arrangement whose pages carry theirs; presented the first time it shows something.
/// Design: docs/design/platforms/gtk/runtime.md#the-window
@MainActor
final class GTKWindow {
    /// The `AdwApplicationWindow`, held until this is released.
    let widget: GTKWidget

    /// The title last given; nil before the first.
    private var title: String??

    /// The view the window shows: a page's, or an arrangement's.
    private(set) var content: GTKView?

    /// The frame a page shown by itself stands in; nil while the window shows an arrangement.
    private(set) var pageFrame: GTKPageFrame?

    /// Native close controls over full-size content while the window's toolbar is hidden.
    private(set) var floatingControls: GTKWidget?

    /// GTK's own window-move gestures around the content only while the toolbar is hidden.
    private(set) var dragHandle: GTKWidget?
    private var backgroundDraggable = false

    /// The layers the window's content and its overlay stand in.
    private let layers: GTKWidget

    /// What the window lays over everything it shows; nil for nothing.
    private(set) var overlay: GTKView?

    private var presented = false
    private var contentReady = false
    private var contentSizing: WindowContentSizing?
    private var constrainingSize = false
    private var layoutClock: OpaquePointer?
    private var layoutSignal: gulong = 0

    /// Whether the window's scene keeps it off screen; a hidden window does not present.
    private var hidden = false

    /// What the window does when the user asks it closed - its close button, the desktop's. The window stays
    /// while there is one: the tree decides whether it goes. nil lets GTK take the window down itself.
    var onClosedByUser: (() -> Void)?

    /// What the window does when the desktop activates it or takes that away.
    var onActiveChanged: ((Bool) -> Void)?

    /// The number the window's signals carry, one across the process.
    private let number: Int64
    private static var nextNumber: Int64 = 1
    private static var open: [Int64: GTKWindow] = [:]

    /// The size and the smallest size last given.
    private var size: (width: Double?, height: Double?) = (nil, nil)
    private var minimumSize: (width: Double?, height: Double?) = (nil, nil)

    /// The window's fill class last given; nil for the platform's own.
    private var fillClass: String?

    init(application: UnsafeMutablePointer<GtkApplication>) {
        widget = adw_application_window_new(application)!
        g_object_ref(widget)
        gtk_window_set_default_size(widget.of(GtkWindow.self), 560, 440)
        // GNOME's smallest window, which a window that adapts to its width must say.
        gtk_widget_set_size_request(widget, 360, 294)
        layers = gtk_overlay_new()!
        g_object_ref_sink(layers)
        adw_application_window_set_content(widget.of(AdwApplicationWindow.self), layers)
        number = Self.nextNumber
        Self.nextNumber += 1
        Self.open[number] = self
        connectSignal(UnsafeMutableRawPointer(widget), "realize", number: number) { _, data in
            MainActor.assumeIsolated { GTKWindow.open[viewNumber(data)]?.followLayout(true) }
        }
        connectSignal(UnsafeMutableRawPointer(widget), "unrealize", number: number) { _, data in
            MainActor.assumeIsolated { GTKWindow.open[viewNumber(data)]?.followLayout(false) }
        }
        for property in ["default-width", "default-height"] {
            connectNotify(UnsafeMutableRawPointer(widget), property, number: number) { _, _, data in
                MainActor.assumeIsolated { GTKWindow.open[viewNumber(data)]?.constrainSize() }
            }
        }
        connectAnswering(UnsafeMutableRawPointer(widget), "close-request", number: number) { _, data in
            MainActor.assumeIsolated {
                guard let onClosedByUser = GTKWindow.open[viewNumber(data)]?.onClosedByUser else { return 0 }
                onClosedByUser()
                return 1
            }
        }
        connectNotify(UnsafeMutableRawPointer(widget), "is-active", number: number) { widget, _, data in
            MainActor.assumeIsolated {
                guard let widget, let window = GTKWindow.open[viewNumber(data)] else { return }
                window.onActiveChanged?(
                    gtk_window_is_active(widget.assumingMemoryBound(to: GtkWindow.self)) != 0)
            }
        }
    }

    isolated deinit {
        followLayout(false)
        Self.open.removeValue(forKey: number)
        g_signal_handlers_disconnect_matched(
            UnsafeMutableRawPointer(widget), SWIFTOMNIUI_SIGNAL_MATCH_DATA, 0, 0, nil, nil,
            UnsafeMutableRawPointer(bitPattern: Int(number)))
        gtk_window_destroy(widget.of(GtkWindow.self))
        if let dragHandle { g_object_unref(dragHandle) }
        g_object_unref(layers)
        g_object_unref(widget)
    }

    /// Reads settled allocations after GTK's layout handlers, while another layout can precede paint.
    private func followLayout(_ follows: Bool) {
        if let layoutClock {
            g_signal_handler_disconnect(UnsafeMutableRawPointer(layoutClock), layoutSignal)
            g_object_unref(UnsafeMutableRawPointer(layoutClock))
        }
        layoutClock = follows ? gtk_widget_get_frame_clock(widget) : nil
        guard let layoutClock else { return }
        g_object_ref(UnsafeMutableRawPointer(layoutClock))
        let callback: GTKSignalHandler = { _, _ in
            MainActor.assumeIsolated { GTKRenderer.shared?.runtime.frames.commitLayout() }
        }
        layoutSignal = g_signal_connect_data(UnsafeMutableRawPointer(layoutClock), "layout",
            unsafeBitCast(callback, to: GCallback.self), nil, nil, G_CONNECT_AFTER)
    }

    /// The window's name, to the desktop - its switcher, its dock; nil for none.
    func setTitle(_ title: String?) {
        guard self.title != .some(title) else { return }
        self.title = .some(title)
        gtk_window_set_title(widget.of(GtkWindow.self), title)
    }

    /// Whether the user resizes the window, as `WindowResizability` says: `.contentSize` fixes the window to its
    /// content, the rest leave it to the user.
    func setResizable(_ resizability: Int32?) {
        gtk_window_set_resizable(widget.of(GtkWindow.self), resizability == 2 ? 0 : 1)
    }

    /// The colour the window paints behind everything; nil for the platform's own.
    func setBackground(_ value: HostValue?) {
        let wanted = GTKBrush(value).firstColor.map(GTKStyleSheet.fill)
        guard wanted != fillClass else { return }
        if let fillClass { gtk_widget_remove_css_class(widget, fillClass) }
        if let wanted { gtk_widget_add_css_class(widget, wanted) }
        fillClass = wanted
    }

    /// Keep GTK's drag gestures and close action reachable without reserving a header row or safe area.
    func showToolbarlessChrome(_ shows: Bool) {
        if backgroundDraggable != shows {
            let child = backgroundDraggable
                ? dragHandle.flatMap { gtk_window_handle_get_child($0.opaque) }
                : gtk_overlay_get_child(layers.opaque)
            backgroundDraggable = shows
            setContent(child)
        }
        if shows, floatingControls == nil {
            let controls = gtk_window_controls_new(GTK_PACK_END)!
            gtk_window_controls_set_decoration_layout(controls.opaque, ":close")
            gtk_widget_set_halign(controls, GTK_ALIGN_END)
            gtk_widget_set_valign(controls, GTK_ALIGN_START)
            gtk_widget_set_margin_top(controls, 6)
            gtk_widget_set_margin_end(controls, 6)
            gtk_overlay_add_overlay(layers.opaque, controls)
            gtk_overlay_set_measure_overlay(layers.opaque, controls, 0)
            floatingControls = controls
        }
        if let floatingControls { gtk_widget_set_visible(floatingControls, shows ? 1 : 0) }
    }

    /// The window's size as it opens, where the window element says one; a window already open takes it too.
    func setSize(width: Double?, height: Double?) {
        guard width != size.width || height != size.height else { return }
        size = (width, height)
        var current: (width: Int32, height: Int32) = (0, 0)
        gtk_window_get_default_size(widget.of(GtkWindow.self), &current.width, &current.height)
        gtk_window_set_default_size(
            widget.of(GtkWindow.self), width.map { Int32($0) } ?? current.width,
            height.map { Int32(($0 + chromeHeight()).rounded(.up)) } ?? current.height)
    }

    /// How small the user may make the window; GNOME's smallest where the element says none.
    func setMinimumSize(width: Double?, height: Double?) {
        guard width != minimumSize.width || height != minimumSize.height else { return }
        minimumSize = (width, height)
        gtk_widget_set_size_request(widget, Int32(width ?? 360), Int32(height ?? 294))
    }

    /// Refreshes content constraints without rewriting the declared default size.
    func apply(_ sizing: WindowContentSizing) {
        var sizing = sizing
        let chrome = chromeHeight()
        sizing.bounds.minimumHeight = sizing.bounds.minimumHeight.map { $0 + chrome }
        sizing.bounds.maximumHeight = sizing.bounds.maximumHeight.map { $0 + chrome }
        contentSizing = sizing
        gtk_widget_set_size_request(widget,
            Int32((sizing.bounds.minimumWidth ?? 360).rounded(.up)),
            Int32((sizing.bounds.minimumHeight ?? 294).rounded(.up)))
        gtk_window_set_resizable(widget.of(GtkWindow.self), sizing.isResizable ? 1 : 0)
        constrainSize()
    }

    private func chromeHeight() -> Double {
        guard let pageFrame, let content else { return 0 }
        var least: Int32 = 0
        var width: Int32 = 0
        var height: Int32 = 0
        gtk_widget_measure(pageFrame.widget, GTK_ORIENTATION_HORIZONTAL, -1, &least, &width, nil, nil)
        gtk_widget_measure(pageFrame.widget, GTK_ORIENTATION_VERTICAL, width, &least, &height, nil, nil)
        return max(0, Double(height) - content.measure(width: Double(width), height: nil).height)
    }

    private func constrainSize() {
        guard !constrainingSize, let contentSizing else { return }
        var width: Int32 = 0
        var height: Int32 = 0
        gtk_window_get_default_size(widget.of(GtkWindow.self), &width, &height)
        let frame = contentSizing.constrain(LayoutSize(width: Double(width), height: Double(height)))
        let nextWidth = frame.width.map { Int32($0.rounded(.up)) } ?? width
        let nextHeight = frame.height.map { Int32($0.rounded(.up)) } ?? height
        guard nextWidth != width || nextHeight != height else { return }
        constrainingSize = true
        defer { constrainingSize = false }
        gtk_window_set_default_size(widget.of(GtkWindow.self), nextWidth, nextHeight)
    }

    /// Shows `view` as the window's content, as it stands: an arrangement whose pages carry their header bars.
    func show(_ view: GTKView?) {
        guard view !== content || pageFrame != nil else { return }
        setContent(nil)
        if let pageFrame { adw_toolbar_view_set_content(pageFrame.widget.opaque, nil) }
        content = view
        pageFrame = nil
        setContent(view?.widget)
    }

    /// Shows `page` in a frame of its own, whose header bar is the window's title bar.
    func show(page: GTKView?) {
        guard page !== content || pageFrame == nil else { return }
        setContent(nil)
        if let pageFrame { adw_toolbar_view_set_content(pageFrame.widget.opaque, nil) }
        content = page
        pageFrame = page.map { GTKPageFrame(page: $0) }
        setContent(pageFrame?.widget)
    }

    /// Lays `view` over everything the window shows, where the page stands; nil takes it away.
    /// Design: docs/design/platforms/gtk/pages.md#the-windows-overlay
    func showOverlay(_ view: GTKView?) {
        guard view !== overlay else { return }
        if let overlay { gtk_overlay_remove_overlay(layers.opaque, overlay.widget) }
        overlay = view
        if let view { gtk_overlay_add_overlay(layers.opaque, view.widget) }
    }

    /// The window this one belongs to - it stays over its owner and goes with it; nil for a window of its own.
    func setOwner(_ owner: GTKWindow?) {
        gtk_window_set_transient_for(widget.of(GtkWindow.self), owner?.widget.of(GtkWindow.self))
    }

    /// Whether the window stands on screen; a hidden window's first content does not present it, showing it again
    /// presents it where it has something to show.
    func setHidden(_ hidden: Bool) {
        self.hidden = hidden
        if presented {
            gtk_widget_set_visible(widget, hidden ? 0 : 1)
        } else if contentReady, !hidden, gtk_overlay_get_child(layers.opaque) != nil {
            presented = true
            present()
        }
    }

    private func setContent(_ widget: GTKWidget?) {
        // Keep the child alive across unparenting even when the window owns its only native reference.
        if let widget { g_object_ref(widget) }
        defer { if let widget { g_object_unref(widget) } }
        gtk_overlay_set_child(layers.opaque, nil)
        if let dragHandle { gtk_window_handle_set_child(dragHandle.opaque, nil) }
        if backgroundDraggable, let widget {
            let handle: GTKWidget
            if let dragHandle {
                handle = dragHandle
            } else {
                handle = gtk_window_handle_new()!
                g_object_ref_sink(handle)
                dragHandle = handle
            }
            // GtkWindowHandle's bubbling gestures let native buttons/text controls handle their input first.
            // The window manager performs the move, including under Wayland; no manual position tracking.
            gtk_window_handle_set_child(handle.opaque, widget)
            gtk_overlay_set_child(layers.opaque, handle)
        } else {
            gtk_overlay_set_child(layers.opaque, widget)
        }
        guard widget != nil, contentReady, !presented, !hidden else { return }

        presented = true
        present()
    }

    /// Presents only after the content's constraints and size have been applied.
    func presentContent() {
        contentReady = true
        guard !presented, !hidden, gtk_overlay_get_child(layers.opaque) != nil else { return }
        presented = true
        present()
    }

    /// Brings the window forward.
    func present() {
        guard !hidden else { return }
        gtk_window_present(widget.of(GtkWindow.self))
    }

    /// Asks the window to close, as the user does: where `onClosedByUser` stands the window stays until the tree
    /// says it goes, else GTK takes it down.
    func close() {
        gtk_window_close(widget.of(GtkWindow.self))
    }

    /// Takes the window down now - the tree has already let it go.
    func destroy() {
        gtk_window_destroy(widget.of(GtkWindow.self))
    }
}
