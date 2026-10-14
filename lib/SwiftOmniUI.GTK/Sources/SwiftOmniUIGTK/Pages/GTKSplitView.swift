// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIGTK

/// Native draggable columns in wide windows; libadwaita owns the sidebar overlay in narrow windows.
/// Design: docs/design/platforms/gtk/pages.md#a-split-view
@MainActor
final class GTKSplitView: GTKLayoutView {
    private(set) var isPresented = false
    private(set) var isContentPresented = true
    var isCollapsed: Bool { adw_overlay_split_view_get_collapsed(native) != 0 }
    var onPresentationChanged: ((Bool) -> Void)?
    var onVisibilityChanged: ((NavigationSplitViewVisibility) -> Void)?
    var framedPanes: [Bool] = []
    private(set) var sidebarFrame: GTKPageFrame?
    private(set) var contentFrame: GTKPageFrame?
    private(set) var detailFrame: GTKPageFrame?

    private let split = GTKWidgetView { adw_overlay_split_view_new() }
    private let columns = GTKColumnPaned(trailing: false)
    private let middle = GTKColumnPaned(trailing: true)
    private var panes: [GTKView] = []
    private var framedViews: [GTKWidget] = []
    private var attached: [GTKWidget] = []
    private var attachedState: [Bool] = []
    private var adapted = false
    private var adaptation = SidebarAdaptation()
    private var configurationPending = false
    private var isDetached = false
    private static let collapsesAt = 400.0
    private var native: OpaquePointer { split.widget.opaque }
    var hasContentColumn: Bool { panes.count > 2 }
    var showsDetailColumn: Bool { hasContentColumn && SplitColumnWidth(detailWidthBounds, defaultIdeal: 320).maximum != 0 }

    // Widths are staged together by arrangeChildren before setItems binds any native columns.
    var sidebarWidthBounds: [Double]?
    var contentWidthBounds: [Double]?
    var detailWidthBounds: [Double]?

    override init() {
        super.init()
        split.placingLayout = self
        adw_overlay_split_view_set_sidebar_width_unit(native, ADW_LENGTH_UNIT_PX)
        setChildren([split])
        connectNotify(UnsafeMutableRawPointer(split.widget), "show-sidebar", number: number) { _, _, data in
            MainActor.assumeIsolated { (GTKView.find(viewNumber(data)) as? GTKSplitView)?.sidebarMoved() }
        }
        connectNotify(UnsafeMutableRawPointer(split.widget), "collapsed", number: number) { _, _, data in
            MainActor.assumeIsolated { (GTKView.find(viewNumber(data)) as? GTKSplitView)?.collapseChanged() }
        }
    }

    @discardableResult
    override func setItems(_ items: [GTKLayoutItem]) -> Bool {
        let views = items.map(\.view)
        let changed = views.count != panes.count || !zip(views, panes).allSatisfy({ $0 === $1 })
        let previous = [sidebarFrame, contentFrame, detailFrame].compactMap { $0 }
        // Existing frames follow their page when the auxiliary column appears or disappears.
        func frame(_ index: Int) -> GTKPageFrame? {
            guard views.indices.contains(index), framedPanes.indices.contains(index), framedPanes[index] else { return nil }
            return previous.first { $0.page === views[index] } ?? GTKPageFrame(page: views[index])
        }
        panes = views
        for view in views { view.placingLayout = nil }
        sidebarFrame = frame(0)
        contentFrame = showsDetailColumn ? frame(1) : nil
        detailFrame = frame(showsDetailColumn ? 2 : 1)
        framedViews = views.enumerated().map { index, view in
            let frame = index == 0 ? sidebarFrame : (index == 1 ? (showsDetailColumn ? contentFrame : detailFrame)
                                                                  : (showsDetailColumn ? detailFrame : nil))
            return frame?.widget ?? view.widget
        }
        configure()
        if changed { invalidateMeasurements() }
        return changed
    }

    func present(_ shows: Bool) {
        guard isPresented != shows else { return }
        isPresented = shows
        configure()
    }

    func present(visibility: NavigationSplitViewVisibility) {
        switch visibility {
        case .automatic: break
        case .all: isPresented = true; isContentPresented = true
        case .doubleColumn: isPresented = !hasContentColumn; isContentPresented = true
        case .detailOnly: isPresented = false; isContentPresented = false
        }
        configure()
    }

    private var effectiveVisibility: NavigationSplitViewVisibility {
        isPresented ? .all : (isContentPresented ? .doubleColumn : .detailOnly)
    }

    private func configure() {
        guard !isDetached else { return }
        // Parent changes and GtkPaned position writes stay outside native allocation.
        if GTKView.allocating > 0 {
            guard !configurationPending else { return }
            configurationPending = true
            GTKDoorbell.afterLayout { [weak self] in
                guard let self, !isDetached else { return }
                configurationPending = false
                configure()
            }
            return
        }
        guard framedViews.count >= 2 else { return }
        let three = showsDetailColumn
        let state = [isCollapsed, isPresented, isContentPresented, three]
        ProgramWrite.perform {
            if attached != framedViews || attachedState != state {
                // Detach through each native owner's API before giving any column a new parent.
                adw_overlay_split_view_set_sidebar(native, nil)
                adw_overlay_split_view_set_content(native, nil)
                columns.clear()
                middle.clear()
                let content = framedViews[1]
                let body: GTKWidget
                if three {
                    middle.set(start: isContentPresented ? content : nil, end: framedViews[2])
                    body = middle.widget
                } else {
                    body = content
                }
                if isCollapsed {
                    adw_overlay_split_view_set_sidebar(native, framedViews[0])
                    adw_overlay_split_view_set_content(native, body)
                } else {
                    columns.set(start: isPresented ? framedViews[0] : nil, end: body)
                    adw_overlay_split_view_set_content(native, columns.widget)
                }
                attached = framedViews
                attachedState = state
                invalidateMeasurements()
            }
            adw_overlay_split_view_set_show_sidebar(native, isCollapsed && isPresented ? 1 : 0)
            let sidebar = SplitColumnWidth(sidebarWidthBounds)
            let content = SplitColumnWidth(contentWidthBounds, defaultIdeal: 320)
            let detail = SplitColumnWidth(detailWidthBounds, defaultIdeal: 320)
            if three { middle.setWidths(detail, other: content) }
            columns.setWidths(sidebar, other: SplitColumnWidth([three ? middle.minimumRoom : content.minimum, -1, -1]))
            // The overlay also follows the authored bounds, including the ideal at its current width.
            adw_overlay_split_view_set_min_sidebar_width(native, sidebar.minimum)
            adw_overlay_split_view_set_max_sidebar_width(native, sidebar.maximum.isFinite ? sidebar.maximum : Double.greatestFiniteMagnitude)
            let width = Double(gtk_widget_get_width(split.widget))
            if width > 0 { adw_overlay_split_view_set_sidebar_width_fraction(native, min(1, sidebar.ideal / width)) }
        }
    }

    private func sidebarMoved() {
        guard !ProgramWrite.isWriting, isCollapsed else { return }
        let shows = adw_overlay_split_view_get_show_sidebar(native) != 0
        guard shows != isPresented else { return }
        isPresented = shows
        if hasContentColumn { onVisibilityChanged?(effectiveVisibility) }
        else { onPresentationChanged?(shows) }
    }

    private func collapseChanged() {
        configure()
        GTKDoorbell.afterLayout { [weak self] in
            guard let self, !isDetached else { return }
            GTKRenderer.shared?.refreshChrome()
        }
    }

    func adapt(in window: GTKWidget) {
        guard !adapted else { return }
        adapted = true
        let breakpoint = adw_breakpoint_new(adw_breakpoint_condition_parse("max-width: \(Int(Self.collapsesAt))sp"))!
        var collapsed = GValue()
        g_value_init(&collapsed, g_type_from_name("gboolean"))
        g_value_set_boolean(&collapsed, 1)
        adw_breakpoint_add_setter(breakpoint, split.widget.of(GObject.self), "collapsed", &collapsed)
        g_value_unset(&collapsed)
        adw_application_window_add_breakpoint(window.of(AdwApplicationWindow.self), breakpoint)
    }

    private static var breakpoint: Double {
        guard let settings = gtk_settings_get_default() else { return collapsesAt }
        var value = GValue()
        g_value_init(&value, g_type_from_name("gint"))
        defer { g_value_unset(&value) }
        g_object_get_property(UnsafeMutablePointer<GObject>(settings), "gtk-xft-dpi", &value)
        let dpi = Double(g_value_get_int(&value))
        return dpi > 0 ? collapsesAt * dpi / (96 * 1024) : collapsesAt
    }

    override func contentSize(width: Double?) -> LayoutSize { split.measure(width: width, height: nil) }

    override func arrange(in bounds: Rect) {
        split.layout(bounds)
        if adaptation.room(bounds.width, breakpoint: Self.breakpoint, shown: isPresented) {
            GTKDoorbell.afterLayout { [weak self] in
                guard let self, !isDetached else { return }
                present(true)
                if hasContentColumn { onVisibilityChanged?(effectiveVisibility) }
                else { onPresentationChanged?(true) }
            }
        }
    }

    override func detach() {
        isDetached = true
        ProgramWrite.perform {
            adw_overlay_split_view_set_sidebar(native, nil)
            adw_overlay_split_view_set_content(native, nil)
            columns.clear()
            middle.clear()
        }
        super.detach()
        onPresentationChanged = nil
        onVisibilityChanged = nil
    }
}

/// GtkPaned owns pointer capture and keyboard resizing. Only its width constraints are host arithmetic.
@MainActor
private final class GTKColumnPaned: GTKView {
    private let trailing: Bool
    private let startSlot = GTKWidgetView { gtk_box_new(GTK_ORIENTATION_VERTICAL, 0) }
    private let endSlot = GTKWidgetView { gtk_box_new(GTK_ORIENTATION_VERTICAL, 0) }
    private var widths = SplitColumnWidth(nil)
    private var other = SplitColumnWidth(nil)
    private var paneWidth = 256.0
    private var allocatedWidth = 0.0
    private var setting = false
    private var pending = false
    private var native: OpaquePointer { widget.opaque }

    init(trailing: Bool) {
        self.trailing = trailing
        super.init { _ in gtk_paned_new(GTK_ORIENTATION_HORIZONTAL) }
        gtk_widget_add_css_class(widget, GTKStyleSheet.splitColumns)
        gtk_paned_set_wide_handle(native, 0)
        gtk_paned_set_resize_start_child(native, trailing ? 1 : 0)
        gtk_paned_set_resize_end_child(native, trailing ? 0 : 1)
        gtk_paned_set_shrink_start_child(native, 1)
        gtk_paned_set_shrink_end_child(native, 1)
        connectNotify(UnsafeMutableRawPointer(widget), "position", number: number) { _, _, data in
            MainActor.assumeIsolated { (GTKView.find(viewNumber(data)) as? GTKColumnPaned)?.positionChanged() }
        }
        connectNotify(UnsafeMutableRawPointer(widget), "max-position", number: number) { _, _, data in
            MainActor.assumeIsolated { (GTKView.find(viewNumber(data)) as? GTKColumnPaned)?.schedule() }
        }
    }

    func clear() {
        setting = true
        defer { setting = false }
        while let child = gtk_widget_get_first_child(startSlot.widget) { gtk_box_remove(startSlot.widget.of(GtkBox.self), child) }
        while let child = gtk_widget_get_first_child(endSlot.widget) { gtk_box_remove(endSlot.widget.of(GtkBox.self), child) }
        gtk_paned_set_start_child(native, nil)
        gtk_paned_set_end_child(native, nil)
    }

    func set(start: GTKWidget?, end: GTKWidget?) {
        setting = true
        defer { setting = false }
        if let start {
            gtk_widget_set_vexpand(start, 1)
            gtk_box_append(startSlot.widget.of(GtkBox.self), start)
            gtk_paned_set_start_child(native, startSlot.widget)
        }
        if let end {
            gtk_widget_set_vexpand(end, 1)
            gtk_box_append(endSlot.widget.of(GtkBox.self), end)
            gtk_paned_set_end_child(native, endSlot.widget)
        }
        schedule()
    }

    func setWidths(_ widths: SplitColumnWidth, other: SplitColumnWidth) {
        if self.widths != widths { paneWidth = widths.ideal }
        self.widths = widths
        self.other = other
        schedule()
    }

    private var gutter: Double {
        var child = gtk_widget_get_first_child(widget)
        while let each = child {
            if each != gtk_paned_get_start_child(native) && each != gtk_paned_get_end_child(native) {
                let width = gtk_widget_get_width(each)
                if width > 0 { return Double(width) }
                var minimum: Int32 = 0
                gtk_widget_measure(each, GTK_ORIENTATION_HORIZONTAL, -1, &minimum, nil, nil, nil)
                return Double(minimum)
            }
            child = gtk_widget_get_next_sibling(each)
        }
        return 0
    }

    var minimumRoom: Double {
        guard gtk_paned_get_start_child(native) != nil else { return trailing ? widths.minimum : other.minimum }
        guard gtk_paned_get_end_child(native) != nil else { return trailing ? other.minimum : widths.minimum }
        return widths.minimum + other.minimum + gutter
    }

    private func positionChanged() {
        guard !setting else { return }
        let width = Double(gtk_widget_get_width(widget))
        if width == allocatedWidth, width > 0 {
            let position = Double(gtk_paned_get_position(native))
            paneWidth = widths.clamp(trailing ? width - gutter - position : position)
        }
        schedule()
    }

    private func schedule() {
        guard !pending else { return }
        pending = true
        GTKDoorbell.afterLayout { [weak self] in
            guard let self else { return }
            pending = false
            applyWidth()
        }
    }

    private func applyWidth() {
        guard let start = gtk_paned_get_start_child(native), let end = gtk_paned_get_end_child(native) else { return }
        let width = Double(gtk_widget_get_width(widget))
        guard width > 0 else { return }
        let available = max(0, width - gutter)
        let least = max(widths.minimum, other.maximum.isFinite ? available - other.maximum : 0)
        let most = max(least, min(widths.maximum, available - other.minimum))
        let length = min(available, min(most, max(least, paneWidth)))
        let position = Int32((trailing ? available - length : length).rounded())
        setting = true
        allocatedWidth = width
        if gtk_paned_get_position(native) != position { gtk_paned_set_position(native, position) }
        gtk_widget_set_size_request(trailing ? end : start, Int32(min(widths.minimum, available).rounded()), -1)
        gtk_widget_set_size_request(trailing ? start : end, Int32(min(other.minimum, available).rounded()), -1)
        setting = false
    }
}
