// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIGTK
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIGTK
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
            XCTAssertEqual(gtk_widget_has_css_class(window.widget, red), 0)
            let blue = GTKStyleSheet.fill(try XCTUnwrap(GTKBrush(Color.blue.propValue).firstColor))
            XCTAssertNotEqual(gtk_widget_has_css_class(window.widget, blue), 0)

            visible.wrappedValue = false
            host.runtime.pump.turn()
            host.layOut()
            XCTAssertTrue(window.floatingControls == controls, "the GTK window controls are reused")
            XCTAssertNotEqual(gtk_widget_get_mapped(controls), 0)
            XCTAssertTrue(window.content === content)
        }
    }
}
