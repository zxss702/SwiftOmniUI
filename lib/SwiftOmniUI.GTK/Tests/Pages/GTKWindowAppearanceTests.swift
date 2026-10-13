// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIGTK
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIGTK
import SwiftOmniUIConformance
import XCTest

final class GTKWindowAppearanceTests: XCTestCase {
    func testHiddenToolbarKeepsNativeCloseControlsWithoutReservingContentHeight() throws {
        try onUIThread {
            let visible = State(wrappedValue: false)
            let background = State(wrappedValue: Color.red)
            let host = GTKRenderer.running(reducesMotion: true) {
                HStack(spacing: 0) {
                    Text("Recent").frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider().frame(maxHeight: .infinity)
                    Text("Welcome").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: 480, height: 320)
                .windowBackground(background.wrappedValue)
                .toolbarVisibility(visible.wrappedValue ? .visible : .hidden, for: .windowToolbar)
            }
            let window = try XCTUnwrap(host.window)
            let frame = try XCTUnwrap(window.pageFrame)
            let content = try XCTUnwrap(window.content)
            let controls = try XCTUnwrap(window.floatingControls)
            let handle = try XCTUnwrap(window.dragHandle)
            XCTAssertEqual(gtk_window_handle_get_child(handle.opaque), frame.widget)
            XCTAssertEqual(gtk_widget_get_parent(frame.widget), handle)
            XCTAssertEqual(gtk_widget_get_parent(controls), gtk_widget_get_parent(handle),
                           "the close controls stay outside the draggable content")
            XCTAssertEqual(gtk_widget_get_mapped(frame.header), 0)
            XCTAssertNotEqual(gtk_widget_get_mapped(controls), 0)
            XCTAssertEqual(String(cString: try XCTUnwrap(gtk_window_controls_get_decoration_layout(controls.opaque))), ":close")

            var bounds = graphene_rect_t()
            XCTAssertNotEqual(gtk_widget_compute_bounds(content.widget, frame.widget, &bounds), 0)
            XCTAssertEqual(bounds.origin.y, 0, accuracy: 1)
            XCTAssertEqual(bounds.size.height, Float(gtk_widget_get_height(frame.widget)), accuracy: 1,
                           "the page reaches both edges without a hidden toolbar's reserved height")
            let red = GTKStyleSheet.fill(try XCTUnwrap(GTKBrush(Color.red.propValue).firstColor))
            XCTAssertNotEqual(gtk_widget_has_css_class(window.widget, red), 0)

            visible.wrappedValue = true
            background.wrappedValue = .blue
            host.runtime.pump.turn()
            host.layOut()
            XCTAssertNotEqual(gtk_widget_get_mapped(frame.header), 0)
            XCTAssertEqual(gtk_widget_get_visible(controls), 0)
            XCTAssertNil(gtk_window_handle_get_child(handle.opaque), "a visible toolbar restores ordinary content hosting")
            XCTAssertNotEqual(gtk_widget_get_parent(frame.widget), handle)
            XCTAssertEqual(gtk_widget_has_css_class(window.widget, red), 0)
            let blue = GTKStyleSheet.fill(try XCTUnwrap(GTKBrush(Color.blue.propValue).firstColor))
            XCTAssertNotEqual(gtk_widget_has_css_class(window.widget, blue), 0)

            visible.wrappedValue = false
            host.runtime.pump.turn()
            host.layOut()
            XCTAssertTrue(window.floatingControls == controls, "the GTK window controls are reused")
            XCTAssertEqual(window.dragHandle, handle, "the GTK drag handle is reused")
            XCTAssertEqual(gtk_window_handle_get_child(handle.opaque), frame.widget)
            XCTAssertNotEqual(gtk_widget_get_mapped(controls), 0)
            XCTAssertTrue(window.content === content)
        }
    }

    /// The native drag surface covers scroller whitespace without covering buttons or consuming row taps.
    func testToolbarlessContentKeepsNativeInputAndScrollerBackgroundInsideTheDragHandle() throws {
        try onUIThread {
            let chosen = Received<String>()
            let host = GTKRenderer.running(reducesMotion: true) {
                HStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 0) {
                            HStack { Text("Recent") }
                                .frame(width: 180, height: 36)
                                .onTapGesture { chosen.values.append("recent") }
                                .contextMenu {
                                    Button("Reveal") { chosen.values.append("reveal") }
                                }
                            Spacer().frame(height: 180)
                        }
                    }
                    .frame(width: 200)
                    VStack {
                        Button("Open") { chosen.values.append("open") }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: 480, height: 320)
                .toolbarVisibility(.hidden, for: .windowToolbar)
            }
            let window = try XCTUnwrap(host.window)
            let handle = try XCTUnwrap(window.dragHandle)
            let scroller = try XCTUnwrap(host.views(GTKScrollerView.self).first)
            let button = try XCTUnwrap(host.views(GTKButtonView.self).first)
            let row = try XCTUnwrap(host.views(GTKStackView.self).first { $0.hearing.contains(.taps) })

            let controllers = try XCTUnwrap(gtk_widget_observe_controllers(handle))
            defer { g_object_unref(UnsafeMutableRawPointer(controllers)) }
            XCTAssertGreaterThanOrEqual(g_list_model_get_n_items(controllers), 2, "GTK owns the click and move gestures")
            for index in 0..<g_list_model_get_n_items(controllers) {
                let controller = try XCTUnwrap(g_list_model_get_item(controllers, index))
                XCTAssertEqual(gtk_event_controller_get_propagation_phase(OpaquePointer(controller)), GTK_PHASE_BUBBLE,
                               "descendant controls receive their input before the window handle")
                g_object_unref(controller)
            }

            @MainActor func picked(_ view: GTKView, x: Double, y: Double) throws -> GTKWidget {
                var from = graphene_point_t(x: Float(x), y: Float(y))
                var at = graphene_point_t()
                XCTAssertNotEqual(gtk_widget_compute_point(view.widget, window.widget, &from, &at), 0)
                return try XCTUnwrap(gtk_widget_pick(window.widget, Double(at.x), Double(at.y), GTK_PICK_DEFAULT))
            }
            let blank = try picked(scroller, x: 100, y: 280)
            XCTAssertNotEqual(gtk_widget_is_ancestor(blank, handle), 0,
                              "empty space below recent rows reaches the native drag surface")
            let target = try picked(button, x: button.frame.width / 2, y: button.frame.height / 2)
            XCTAssertTrue(target == button.widget || gtk_widget_is_ancestor(target, button.widget) != 0)
            button.click()
            let taps = try XCTUnwrap(row.listening?.controllers[.taps]?.first)
            GTKTestHost.emit(taps, "pressed", [1, 20, 20])
            GTKTestHost.emit(taps, "released", [1, 20, 20])
            XCTAssertEqual(chosen.values, ["open", "recent"])

            let context = try XCTUnwrap(row.contextMenu)
            context.open(atX: 20, y: 20)
            XCTAssertNotEqual(gtk_widget_get_visible(context.popover), 0)
            XCTAssertNotEqual(gtk_widget_activate_action_variant(row.widget, GTKMenu.actionGroup + ".e0", nil), 0)
            XCTAssertEqual(chosen.values, ["open", "recent", "reveal"])
            gtk_popover_popdown(context.popover.of(GtkPopover.self))
        }
    }
}
