// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIGTK

/// A NavigationSplitView: libadwaita's `AdwOverlaySplitView` - the sidebar beside the detail where the window is wide, over
/// it where it is narrow - each pane a page in a frame with its own header bar, or an arrangement carrying its own.
/// Whether the sidebar shows is SwiftOmniUI's binding, which the detail's toggle changes and which follows what GTK
/// shows. A window wide enough for both panes opens with the sidebar shown.
/// Design: docs/design/platforms/gtk/pages.md#a-split-view
@MainActor
final class GTKSplitView: GTKLayoutView {
    /// Whether the sidebar shows.
    private(set) var isPresented = false

    /// Whether the split stands collapsed, the sidebar over the detail.
    var isCollapsed: Bool { adw_overlay_split_view_get_collapsed(native) != 0 }

    /// What the split does when the sidebar shows or hides of its own accord - its first room, a click beside it,
    /// a swipe.
    var onPresentationChanged: ((Bool) -> Void)?

    /// What the split does when the user moves which of three columns show.
    var onVisibilityChanged: ((NavigationSplitViewVisibility) -> Void)?

    /// Which of the panes' views are framed: a page, a tabbed view.
    var framedPanes: [Bool] = []

    /// The frames of the panes that are framed: the sidebar's, the content
    /// column's, the detail's.
    private(set) var sidebarFrame: GTKPageFrame?
    private(set) var contentFrame: GTKPageFrame?
    private(set) var detailFrame: GTKPageFrame?

    private let split = GTKWidgetView { adw_overlay_split_view_new() }

    /// The middle column's own split inside the outer one's content: its
    /// sidebar is the content column, its content the detail - a three-column
    /// split as two two-column ones.
    private let middle = GTKWidgetView { adw_overlay_split_view_new() }

    private var panes: [GTKView] = []
    var detailWidthBounds: [Double]?
    private var arrangedDetailWidth: [Double]?
    private var adapted = false
    private var adaptation = SidebarAdaptation()

    /// Where GNOME's applications collapse a split, in scale-independent pixels: logical pixels at the desktop's
    /// own text scale.
    private static let collapsesAt = 400.0

    override init() {
        super.init()
        split.placingLayout = self
        setChildren([split])
        connectNotify(UnsafeMutableRawPointer(split.widget), "show-sidebar", number: number) { _, _, data in
            MainActor.assumeIsolated { (GTKView.find(viewNumber(data)) as? GTKSplitView)?.sidebarMoved() }
        }
        connectNotify(UnsafeMutableRawPointer(middle.widget), "show-sidebar", number: number) { _, _, data in
            MainActor.assumeIsolated { (GTKView.find(viewNumber(data)) as? GTKSplitView)?.contentMoved() }
        }
        adw_overlay_split_view_set_show_sidebar(middle.widget.opaque, 1)
        adw_overlay_split_view_set_enable_show_gesture(middle.widget.opaque, 0)
        adw_overlay_split_view_set_enable_hide_gesture(middle.widget.opaque, 0)
    }

    private var native: OpaquePointer { split.widget.opaque }

    /// Whether a content column stands between the sidebar and the detail.
    var hasContentColumn: Bool { panes.count > 2 }
    var showsDetailColumn: Bool { hasContentColumn && detailWidthBounds?.last != 0 }

    /// The sidebar and the pages beside it, each framed where it is a page -
    /// a third pane stands in the middle split as its sidebar.
    @discardableResult
    override func setItems(_ items: [GTKLayoutItem]) -> Bool {
        let views = items.map(\.view)
        guard views.count != panes.count || !zip(views, panes).allSatisfy({ $0 === $1 })
            || detailWidthBounds != arrangedDetailWidth else { return false }

        arrangedDetailWidth = detailWidthBounds
        panes = views
        for view in views { view.placingLayout = nil }
        sidebarFrame = frame(views.first, framed: framedPanes.first == true, keeping: sidebarFrame)
        adw_overlay_split_view_set_sidebar(native, sidebarFrame?.widget ?? views.first?.widget)

        if views.count > 2, detailWidthBounds?.last != 0 {
            middle.placingLayout = nil
            contentFrame = frame(views[1], framed: framedPanes.count > 1 && framedPanes[1], keeping: contentFrame)
            detailFrame = frame(views[2], framed: framedPanes.count > 2 && framedPanes[2], keeping: detailFrame)
            adw_overlay_split_view_set_sidebar(middle.widget.opaque, contentFrame?.widget ?? views[1].widget)
            adw_overlay_split_view_set_content(middle.widget.opaque, detailFrame?.widget ?? views[2].widget)
            adw_overlay_split_view_set_content(native, middle.widget)
        } else {
            adw_overlay_split_view_set_content(native, nil)
            adw_overlay_split_view_set_sidebar(middle.widget.opaque, nil)
            adw_overlay_split_view_set_content(middle.widget.opaque, nil)
            contentFrame = nil
            detailFrame = frame(views.dropFirst().first, framed: framedPanes.dropFirst().first == true, keeping: detailFrame)
            adw_overlay_split_view_set_content(native, detailFrame?.widget ?? views.dropFirst().first?.widget)
        }
        invalidateMeasurements()
        return true
    }

    /// A frame around `view`, the one it stands in already where it does.
    private func frame(_ view: GTKView?, framed: Bool, keeping kept: GTKPageFrame?) -> GTKPageFrame? {
        guard let view, framed else { return nil }
        return kept?.page === view ? kept : GTKPageFrame(page: view)
    }

    /// Shows or hides the sidebar, as the program's move.
    func present(_ shows: Bool) {
        isPresented = shows
        ProgramWrite.perform { adw_overlay_split_view_set_show_sidebar(native, shows ? 1 : 0) }
    }

    /// The columns the tree says show, as the program's move - the middle
    /// split's sidebar is the content column: `.all` shows all three,
    /// `.doubleColumn` drops the sidebar, `.detailOnly` drops both, and
    /// `.automatic` asks nothing.
    func present(visibility: NavigationSplitViewVisibility) {
        let threeColumns = hasContentColumn
        switch visibility {
        case .automatic:
            break
        case .all:
            present(true)
            presentContent(true)
        case .doubleColumn:
            present(!threeColumns)
            presentContent(true)
        case .detailOnly:
            present(false)
            presentContent(false)
        }
    }

    /// Shows or hides the content column, as the program's move.
    private func presentContent(_ shows: Bool) {
        guard hasContentColumn else { return }
        isContentPresented = shows
        ProgramWrite.perform { adw_overlay_split_view_set_show_sidebar(middle.widget.opaque, shows ? 1 : 0) }
    }

    /// Whether the content column shows, where three columns can.
    private(set) var isContentPresented = true

    /// The sidebar's least and most width the tree asks, `nil` leaving the
    /// split's own. A fixed width binds both; an ideal has no home in
    /// `AdwOverlaySplitView` and is left with it.
    var sidebarWidthBounds: [Double]? {
        didSet {
            guard let bounds = sidebarWidthBounds, !bounds.isEmpty else { return }
            adw_overlay_split_view_set_min_sidebar_width(native, bounds[0])
            if bounds.count > 2 {
                adw_overlay_split_view_set_max_sidebar_width(native, bounds[2])
            } else if bounds.count == 1 {
                adw_overlay_split_view_set_max_sidebar_width(native, bounds[0])
            }
        }
    }

    /// The content column's least and most width, as `sidebarWidthBounds` is
    /// the sidebar's.
    var contentWidthBounds: [Double]? {
        didSet {
            guard let bounds = contentWidthBounds, !bounds.isEmpty else { return }
            adw_overlay_split_view_set_min_sidebar_width(middle.widget.opaque, bounds[0])
            if bounds.count > 2 {
                adw_overlay_split_view_set_max_sidebar_width(middle.widget.opaque, bounds[2])
            } else if bounds.count == 1 {
                adw_overlay_split_view_set_max_sidebar_width(middle.widget.opaque, bounds[0])
            }
        }
    }

    /// Which columns stand shown on screen, where three can.
    private var effectiveVisibility: NavigationSplitViewVisibility? {
        guard hasContentColumn else { return nil }
        switch (isPresented, isContentPresented) {
        case (true, true): return .all
        case (false, true): return .doubleColumn
        case (false, false): return .detailOnly
        case (true, false): return .all
        }
    }

    /// The sidebar showed or hid of its own accord: said, where it was not the program's.
    private func sidebarMoved() {
        let shows = adw_overlay_split_view_get_show_sidebar(native) != 0
        guard !ProgramWrite.isWriting, shows != isPresented else { return }
        isPresented = shows
        if let visibility = effectiveVisibility {
            onVisibilityChanged?(visibility)
        } else {
            onPresentationChanged?(shows)
        }
    }

    /// The content column showed or hid of its own accord: said, where it was
    /// not the program's.
    private func contentMoved() {
        let shows = adw_overlay_split_view_get_show_sidebar(middle.widget.opaque) != 0
        guard !ProgramWrite.isWriting, shows != isContentPresented else { return }
        isContentPresented = shows
        if let visibility = effectiveVisibility {
            onVisibilityChanged?(visibility)
        }
    }

    /// Collapses the split in a window narrower than 400sp, as GNOME's applications do - a breakpoint of the
    /// window's, added once the split stands in one.
    /// Design: docs/design/platforms/gtk/pages.md#a-split-view
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

    /// The host's one adaptation (`SidebarAdaptation`): a split first given room wide enough for both panes opens
    /// with its sidebar shown, and says so - once GTK has laid the frame out, not inside its allocation.
    private func adaptToFirstRoom(width: Double) {
        guard adaptation.room(width, breakpoint: Self.breakpoint, shown: isPresented) else { return }
        GTKDoorbell.afterLayout { [weak self] in
            guard let self, !isPresented else { return }
            present(true)
            onPresentationChanged?(true)
        }
    }

    /// The breakpoint in logical pixels: a scale-independent pixel follows the desktop's text scale.
    private static var breakpoint: Double {
        guard let settings = gtk_settings_get_default() else { return collapsesAt }
        var value = GValue()
        g_value_init(&value, g_type_from_name("gint"))
        defer { g_value_unset(&value) }
        g_object_get_property(UnsafeMutablePointer<GObject>(settings), "gtk-xft-dpi", &value)
        let dpi = Double(g_value_get_int(&value))
        return dpi > 0 ? collapsesAt * dpi / (96 * 1024) : collapsesAt
    }

    override func contentSize(width: Double?) -> LayoutSize {
        split.measure(width: width, height: nil)
    }

    override func arrange(in bounds: Rect) {
        split.layout(bounds)
        adaptToFirstRoom(width: bounds.width)
    }

    override func detach() {
        super.detach()
        onPresentationChanged = nil
    }
}
