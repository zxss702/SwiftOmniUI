// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIGTK

/// Holding the hover of what a popup stands over.
///
/// SwiftUI holds a view's `onHover` state while a context menu, a popover or a picker's list stands over the pointer:
/// the pointer did not leave the view it was on, so the view is not told it did. GTK takes the pointer to such a popup
/// all the same - a popover is a surface of its own - so the views under it are told the pointer left, and are told
/// nothing when the popup goes, since the pointer never moved. So the exit such a popup caused is withheld while any
/// of them stands, and the last one going takes the truth again from the pointer's own place: a view the pointer is
/// still on keeps its hover, and one the pointer has left is handed the exit it was owed.
///
/// Only a view the motion controller told an exit is ever held, so no walk of the element tree is needed, and a
/// popup's own relatedness to what it covers is never asked. A popup is counted where it is made - the popover a page
/// shows, a context menu's, a picker's face, the list a drop-down holds of GTK's own, the popover a menu button makes
/// with its menu model - and uncounted where GTK says it left the screen: the popover's own `visible` for one the
/// host hid, and the `unmap` of one whose widget went without being told to - its button leaving the tree with it,
/// its window closing - each counted by the popover's own identity, so one popover gone in two ways at once is one
/// popover gone, and no count outlives what it counted.
/// Design: docs/design/platforms/gtk/input.md#a-popup-over-the-pointer
@MainActor
enum GTKHoverHold {
    /// A view whose exit is being withheld, and the exit itself. Weak: the rule holds a view no longer than the view
    /// stands, and a view that left the tree is let go of in `detach()`.
    private struct Held {
        weak var view: GTKView?
        var exit: HeardInput
    }

    /// The popovers standing over the pointer, by their own identity. A set, because one popover says it left in
    /// more than one way - unmapped and unrealized - and that is still one popover gone, not two.
    private static var standing: Set<UInt> = []

    /// What is being withheld, in the order it was - the pointer's place may fall on more than one.
    private static var withheld: [Held] = []

    /// Where the pointer stands in the native widget's own coordinates, in logical pixels; nil where it stands over
    /// no part of that widget's surface, or GTK cannot say. The host's own answer, which a test stands aside for one
    /// of its own.
    static let livePointerPlace: (GTKView) -> Point? = { view in
        guard let native = gtk_widget_get_native(view.widget),
              let surface = gtk_native_get_surface(native),
              let display = gtk_widget_get_display(view.widget),
              let seat = gdk_display_get_default_seat(display),
              let pointer = gdk_seat_get_pointer(seat) else { return nil }
        var x = 0.0
        var y = 0.0
        // False where the pointer stands over no part of this surface.
        guard gdk_surface_get_device_position(surface, pointer, &x, &y, nil) != 0 else { return nil }
        // The shift from the surface's own place to the native widget's: taken away, as GTK's own
        // conversion does.
        var shiftX = 0.0
        var shiftY = 0.0
        gtk_native_get_surface_transform(native, &shiftX, &shiftY)
        return Point(x: x - shiftX, y: y - shiftY)
    }

    /// Where the pointer stands, as the rule asks it: a seam for tests, as `GTKStrings.lookup` is
    /// (`Runtime/GTKStrings.swift`).
    static var pointerPlace: (GTKView) -> Point? = livePointerPlace

    /// Whether a popup stands over the pointer - what withholds an exit.
    static var isStanding: Bool { !standing.isEmpty }

    /// How many views are holding an exit - what a test reads.
    static var holding: Int { withheld.count }

    /// A popup the user sees stand over the pointer opened.
    static func began(_ popup: UnsafeMutableRawPointer) {
        standing.insert(UInt(bitPattern: popup))
    }

    /// `popup` went - the host asked GTK to hide it, or its widget left the screen. With the last one gone, what was
    /// withheld is settled: what the popup covered is holding its hover, and what it does not cover is owed the exit
    /// it was denied.
    static func ended(_ popup: UnsafeMutableRawPointer) {
        guard standing.remove(UInt(bitPattern: popup)) != nil, standing.isEmpty, !withheld.isEmpty else { return }

        let settling = withheld
        withheld.removeAll(keepingCapacity: true)
        for held in settling {
            guard let view = held.view else { continue }
            if let place = pointerPlace(view), reaches(view, place) {
                continue  // the pointer is still on the view: its hover never left.
            }
            view.deliver(held.exit)
        }
    }

    /// Whether a place of the view's native widget reaches the view, or what stands in it: the question a tap asks
    /// GTK before it is the view's (`GTKListening.tapReleased`), asked of the native the place is measured in.
    static func reaches(_ view: GTKView, _ place: Point) -> Bool {
        guard let native = gtk_widget_get_native(view.widget) else { return false }
        var from = graphene_point_t(x: Float(place.x), y: Float(place.y))
        var to = graphene_point_t()
        let nativeWidget = UnsafeMutableRawPointer(native).assumingMemoryBound(to: GtkWidget.self)
        guard gtk_widget_compute_point(nativeWidget, view.widget, &from, &to) != 0 else { return false }
        return gtk_widget_contains(view.widget, Double(to.x), Double(to.y)) != 0
    }

    /// Counts `popover` as a popup over the pointer while it shows, and stops counting it where it goes: a popover
    /// GTK makes of its own is counted the same as one the host made.
    static func watch(_ popover: GTKWidget) {
        let instance = UnsafeMutableRawPointer(popover)
        // The host asking GTK to show it or take it away: counted from before the pointer is taken, and uncounted as
        // the popover goes, as a WinUI popup's opening and closing are.
        connectNotify(instance, "visible", number: 0) { popover, _, _ in
            MainActor.assumeIsolated {
                guard let popover else { return }
                let showing = gtk_widget_get_visible(popover.assumingMemoryBound(to: GtkWidget.self)) != 0
                if showing { began(popover) } else { ended(popover) }
            }
        }
        // A popover that left the screen without being told to hide would stand in the count over nothing: its
        // widget went - the button it hangs on left the tree with it, its window closed with it. Uncounted as it
        // goes, so no count outlives what it counted.
        let left: GTKArgumentHandler = { popover, _, _ in
            MainActor.assumeIsolated {
                guard let popover else { return }
                let showing = gtk_widget_get_visible(popover.assumingMemoryBound(to: GtkWidget.self)) != 0
                if showing { ended(popover) }
            }
        }
        connectSignal(instance, "unmap", number: 0, left)
        connectSignal(instance, "unrealize", number: 0, left)
    }

    /// Counts a menu button's own popover - GTK's, made with the menu model it was handed - while it shows: a menu
    /// stands over what its button drops on.
    static func watch(menuButton button: GTKWidget) {
        guard let popover = gtk_menu_button_get_popover(button.opaque)?.of(GtkWidget.self) else { return }
        watch(popover)
    }

    /// The pointer was told to leave a view while a popup stood over it: the exit is held until the last one goes.
    static func withhold(_ exit: HeardInput, for view: GTKView) {
        if let at = withheld.firstIndex(where: { $0.view === view }) {
            withheld[at].exit = exit
        } else {
            withheld.append(Held(view: view, exit: exit))
        }
    }

    /// The pointer came back on the view: nothing is owed it.
    static func resumed(_ view: GTKView) {
        withheld.removeAll { $0.view === view || $0.view == nil }
    }

    /// The view left the tree: it is owed nothing, and the rule keeps no hold on it.
    static func letGo(of view: GTKView) {
        withheld.removeAll { $0.view === view || $0.view == nil }
    }
}
