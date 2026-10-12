// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIGTK

/// GTK's `GtkScrolledWindow`, which a ScrollView stands over its whole room around the document it moves, the
/// document in a viewport that gives it its natural size the ways it scrolls.
/// Design: docs/design/platforms/gtk/layout.md#scrolling
@MainActor
final class GTKScrollerView: GTKView {
    /// Says where the view stands after it changed.
    var onScrolled: ((Point) -> Void)?

    /// Says the user took hold of the scroller - a touchpad's fingers down - or let go of it.
    var onHeld: ((Bool) -> Void)?

    /// Besides `onScrolled`, what each move of the view also tells - a lazy
    /// run whose window it is. Weakly held: a dead ear hears nothing and is
    /// dropped.
    var ears: [GTKScrollEar] = []

    private(set) var content: GTKView?

    init() {
        super.init { _ in gtk_scrolled_window_new() }
        for adjustment in [horizontal, vertical] {
            connectSignal(UnsafeMutableRawPointer(adjustment), "changed", number: number) { _, data in
                MainActor.assumeIsolated {
                    guard let view = GTKView.find(viewNumber(data)) as? GTKScrollerView else { return }
                    view.ears = view.ears.filter { $0.owner != nil }
                    for ear in view.ears { ear.moved() }
                }
            }
            connectSignal(UnsafeMutableRawPointer(adjustment), "value-changed", number: number) { _, data in
                MainActor.assumeIsolated {
                    guard let view = GTKView.find(viewNumber(data)) as? GTKScrollerView else { return }
                    view.onScrolled?(view.standing.offset)
                    view.ears = view.ears.filter { $0.owner != nil }
                    for ear in view.ears { ear.moved() }
                    // The viewport moves the document in the layout after this; allocated, it says it moved.
                    // Design: docs/design/platforms/gtk/layout.md#where-a-view-stands
                    if let content = view.content { gtk_widget_queue_allocate(content.widget) }
                }
            }
        }

        let fingers = gtk_event_controller_scroll_new(GTK_EVENT_CONTROLLER_SCROLL_BOTH_AXES)!
        gtk_event_controller_set_propagation_phase(fingers, GTK_PHASE_CAPTURE)
        connectSignal(UnsafeMutableRawPointer(fingers), "scroll-begin", number: number) { _, data in
            MainActor.assumeIsolated { (GTKView.find(viewNumber(data)) as? GTKScrollerView)?.onHeld?(true) }
        }
        connectSignal(UnsafeMutableRawPointer(fingers), "scroll-end", number: number) { _, data in
            MainActor.assumeIsolated { (GTKView.find(viewNumber(data)) as? GTKScrollerView)?.onHeld?(false) }
        }
        gtk_widget_add_controller(widget, fingers)
    }

    /// The scrolled window takes its document out of its viewport before it goes.
    isolated deinit {
        gtk_scrolled_window_set_child(scrolled, nil)
    }

    private var scrolled: OpaquePointer { widget.opaque }
    private var horizontal: UnsafeMutablePointer<GtkAdjustment> { gtk_scrolled_window_get_hadjustment(scrolled) }
    private var vertical: UnsafeMutablePointer<GtkAdjustment> { gtk_scrolled_window_get_vadjustment(scrolled) }

    /// The document it moves, the ways it scrolls, and its bars: the viewport gives the document its natural size
    /// along the ways it scrolls and the viewport's size across.
    func set(
        content: GTKView, orientation: Axis, verticalBar: ScrollIndicatorVisibility,
        horizontalBar: ScrollIndicatorVisibility
    ) {
        if content !== self.content {
            self.content = content
            gtk_scrolled_window_set_child(scrolled, content.widget)
        }
        let across = orientation == .horizontal || orientation == .both
        let down = orientation == .vertical || orientation == .both
        gtk_scrolled_window_set_policy(
            scrolled, Self.policy(scrolls: across, horizontalBar), Self.policy(scrolls: down, verticalBar))
        if let viewport = gtk_scrolled_window_get_child(scrolled), viewport != content.widget {
            gtk_scrollable_set_hscroll_policy(viewport.opaque, across ? GTK_SCROLL_NATURAL : GTK_SCROLL_MINIMUM)
            gtk_scrollable_set_vscroll_policy(viewport.opaque, down ? GTK_SCROLL_NATURAL : GTK_SCROLL_MINIMUM)
        }
    }

    /// A way the view scrolls, with its bar as asked; a way it does not scroll holds the document to the viewport.
    private static func policy(scrolls: Bool, _ bar: ScrollIndicatorVisibility) -> GtkPolicyType {
        guard scrolls else { return GTK_POLICY_NEVER }
        return switch bar {
        case .visible: GTK_POLICY_ALWAYS
        case .hidden: GTK_POLICY_EXTERNAL
        default: GTK_POLICY_AUTOMATIC
        }
    }

    /// The room the bars floating over the scroller keep from its indicators: each bar's extent on its own
    /// edge goes on the indicator's margin there, the document's room untouched.
    private var indicatorMargins: [GTKWidget: EdgeInsets] = [:]
    private var indicatorInsets: EdgeInsets?

    func insetScrollbars(_ insets: EdgeInsets) {
        guard insets != indicatorInsets else { return }
        indicatorInsets = insets
        let bars = [gtk_scrolled_window_get_vscrollbar(scrolled), gtk_scrolled_window_get_hscrollbar(scrolled)]
        for (index, candidate) in bars.enumerated() {
            guard let bar = candidate else { continue }
            let original = indicatorMargins[bar] ?? EdgeInsets(
                top: Double(gtk_widget_get_margin_top(bar)), leading: Double(gtk_widget_get_margin_start(bar)),
                bottom: Double(gtk_widget_get_margin_bottom(bar)), trailing: Double(gtk_widget_get_margin_end(bar)))
            indicatorMargins[bar] = original
            if index == 0 {
                gtk_widget_set_margin_top(bar, Int32(max(0, original.top + insets.top).rounded()))
                gtk_widget_set_margin_bottom(bar, Int32(max(0, original.bottom + insets.bottom).rounded()))
            } else {
                gtk_widget_set_margin_start(bar, Int32(max(0, original.left + insets.left).rounded()))
                gtk_widget_set_margin_end(bar, Int32(max(0, original.right + insets.right).rounded()))
            }
        }
    }

    /// Moves the view to `target` at once.
    func move(to target: Point) {
        gtk_adjustment_set_value(horizontal, target.x)
        gtk_adjustment_set_value(vertical, target.y)
    }

    /// Where the view stands, and the farthest it reaches.
    var standing: (offset: Point, reach: Point) {
        func reach(_ adjustment: UnsafeMutablePointer<GtkAdjustment>) -> Double {
            max(0, gtk_adjustment_get_upper(adjustment) - gtk_adjustment_get_page_size(adjustment))
        }
        return (
            Point(x: gtk_adjustment_get_value(horizontal), y: gtk_adjustment_get_value(vertical)),
            Point(x: reach(horizontal), y: reach(vertical)))
    }

    override func detach() {
        super.detach()
        onScrolled = nil
        onHeld = nil
        ears = []
    }
}

/// One that hears a scroller's moves - a lazy run listening for its window.
@MainActor
final class GTKScrollEar {
    /// Whose ear it is; nil once that view has left.
    weak var owner: AnyObject?

    /// What the move says.
    let moved: () -> Void

    init(owner: AnyObject, moved: @escaping () -> Void) {
        self.owner = owner
        self.moved = moved
    }
}
