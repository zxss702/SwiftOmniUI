// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIGTK

/// A popover: a `GtkPopover` on the widget of the view it hangs off, holding the popover's content in this layout -
/// which no parent's layout places: the popover is its room, sized to the content's own.
@MainActor
final class GTKPopoverView: GTKSingleChildView {
    /// The popover, holding this layout's panel; a child of its anchor's widget while one is found.
    let popover: GTKWidget

    /// The view the popover stands beside, read each time it opens.
    var anchor: () -> GTKView? = { nil }

    /// The edge of the anchor the popover prefers.
    var edge = Edge.top

    /// The user took the popover away: a click beside it, Escape.
    var onDismissed: (() -> Void)?

    /// Whether the popover is to show, as the element last said.
    private(set) var isOpen = false

    /// The anchor's widget the popover waits on to be mapped - held while it waits - and the handler of its `map`.
    private var waiting: (widget: GTKWidget, handler: gulong)?

    override init() {
        popover = gtk_popover_new()!
        super.init()
        g_object_ref_sink(popover)
        gtk_popover_set_child(popover.of(GtkPopover.self), widget)
        connectSignal(UnsafeMutableRawPointer(popover), "closed", number: number) { (_: UnsafeMutableRawPointer?, data) in
            MainActor.assumeIsolated { (GTKView.find(viewNumber(data)) as? GTKPopoverView)?.closed() }
        }
        GTKHoverHold.watch(popover)
    }

    isolated deinit {
        stopWaiting()
        if gtk_widget_get_parent(popover) != nil { gtk_widget_unparent(popover) }
        gtk_popover_set_child(popover.of(GtkPopover.self), nil)
        g_object_unref(popover)
    }

    /// Whether GTK shows the popover - what a test reads.
    var showsPopover: Bool { gtk_widget_get_visible(popover) != 0 }

    /// Opens the popover beside its anchor or takes it away; written only where it differs.
    func setOpen(_ open: Bool) {
        guard open != isOpen else { return }
        isOpen = open
        if open { show() } else { hide() }
    }

    /// Hangs the popover on its anchor's widget - a panel presents it where it stands on each allocation - and opens
    /// it there; an anchor not yet shown in a window, once it is: a popover realizes as it shows, on its anchor's
    /// surface.
    private func show() {
        guard let anchor = anchor() else { return }
        stopWaiting()
        let parent = gtk_widget_get_parent(popover)
        if parent != anchor.widget {
            if parent != nil { gtk_widget_unparent(popover) }
            gtk_widget_set_parent(popover, anchor.widget)
        }
        gtk_popover_set_position(popover.of(GtkPopover.self), Self.position(edge))
        guard gtk_widget_get_mapped(anchor.widget) != 0, gtk_widget_get_root(anchor.widget) != nil else {
            g_object_ref(anchor.widget)
            let handler = connectSignal(UnsafeMutableRawPointer(anchor.widget), "map", number: number) {
                (_: UnsafeMutableRawPointer?, data) in
                MainActor.assumeIsolated { (GTKView.find(viewNumber(data)) as? GTKPopoverView)?.anchorMapped() }
            }
            waiting = (anchor.widget, handler)
            return
        }
        gtk_popover_popup(popover.of(GtkPopover.self))
    }

    /// The anchor came into its window: the popover opens beside it once GTK has laid it out, if it is still to.
    private func anchorMapped() {
        stopWaiting()
        GTKDoorbell.afterLayout { [weak self] in
            guard let self, isOpen, waiting == nil else { return }
            show()
        }
    }

    private func stopWaiting() {
        guard let waiting else { return }
        self.waiting = nil
        g_signal_handler_disconnect(UnsafeMutableRawPointer(waiting.widget), waiting.handler)
        g_object_unref(waiting.widget)
    }

    private func hide() {
        stopWaiting()
        gtk_popover_popdown(popover.of(GtkPopover.self))
    }

    private static func position(_ edge: Edge) -> GtkPositionType {
        switch edge {
        case .top: GTK_POS_TOP
        case .leading: GTK_POS_LEFT
        case .bottom: GTK_POS_BOTTOM
        case .trailing: GTK_POS_RIGHT
        }
    }

    /// Takes the popover away as the user does, so it is heard as their dismissal - what a test does.
    func dismissAsUser() {
        gtk_popover_popdown(popover.of(GtkPopover.self))
    }

    /// The popover closed: of the user's accord while the element still says open, which the element hears; the
    /// host's own closing says nothing. Hidden either way - closed with its anchor, it would show again with it.
    private func closed() {
        guard isOpen else { return }
        isOpen = false
        gtk_popover_popdown(popover.of(GtkPopover.self))
        onDismissed?()
    }

    override func detach() {
        super.detach()
        onDismissed = nil
        anchor = { nil }
        isOpen = false
        hide()
        if gtk_widget_get_parent(popover) != nil { gtk_widget_unparent(popover) }
    }
}
