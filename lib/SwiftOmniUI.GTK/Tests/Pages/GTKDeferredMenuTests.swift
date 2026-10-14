// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIGTK
@_spi(Host) @testable import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIGTK
import XCTest

final class GTKDeferredMenuTests: XCTestCase {
    func testNativeMenuRequestsOnlyTheOpenedLevelAndKeepsItsModels() throws {
        try onUIThread {
            let previous = HostRealizations.current
            CoreLink().setRealization(GTKRegistrations.registry.realization, unrealized: GTKRealization.unmade)
            defer { HostRealizations.current = previous }
            let trace = GTKMenuTrace()
            let entries = State(wrappedValue: ["Leaf"])
            let host = GTKRenderer.running {
                VStack {
                    Menu {
                        trace.root += 1
                        return Menu {
                            trace.child += 1
                            return ForEach(entries.wrappedValue, id: \.self) { name in
                                MenuItem(name).onAppear { trace.appeared += 1 }
                            }
                        } label: { Text("Directory") }.id("branch")
                    } label: { Text("Root") }.id("root")
                }.buttonStyle(.plain)
            }
            let root = try XCTUnwrap(host.views(GTKMenuButtonView.self).first)
            XCTAssertEqual(trace.root, 0)
            XCTAssertEqual(trace.child, 0)
            XCTAssertEqual(gtk_menu_button_get_has_frame(root.widget.opaque), 0)
            let model = try XCTUnwrap(root.menu).model
            let popup = gtk_menu_button_get_popover(root.widget.opaque)
            gtk_menu_button_popup(root.widget.opaque)
            host.settle { trace.root == 1 }
            XCTAssertEqual(trace.root, 1)
            XCTAssertEqual(trace.child, 0)
            XCTAssertEqual(root.menu?.model, model)
            XCTAssertTrue(gtk_menu_button_get_popover(root.widget.opaque) == popup)
            let branch = try XCTUnwrap(host.runtime.tree.root?.first(id: .manual("branch")))
            let action = try XCTUnwrap(g_action_map_lookup_action(OpaquePointer(try XCTUnwrap(root.menu).actions), "s\(branch.mount)"))
            let state = g_variant_ref_sink(g_variant_new_boolean(1))
            defer { g_variant_unref(state) }
            g_action_change_state(action, state)
            host.settle { trace.child == 1 }
            XCTAssertEqual(trace.child, 1)
            XCTAssertEqual(trace.appeared, 1)
            XCTAssertEqual(root.menu?.model, model)
            XCTAssertTrue(gtk_menu_button_get_popover(root.widget.opaque) == popup)
            entries.wrappedValue = ["First", "Second"]
            host.settle { root.menu?.drawn.contains("Second") == true }
            XCTAssertTrue(root.menu?.drawn.contains("First") == true)
            XCTAssertTrue(root.menu?.drawn.contains("Second") == true)
            XCTAssertEqual(root.menu?.model, model)
            XCTAssertTrue(gtk_menu_button_get_popover(root.widget.opaque) == popup)
            let builds = trace.child
            gtk_menu_button_popdown(root.widget.opaque)
            gtk_menu_button_popup(root.widget.opaque)
            host.step()
            XCTAssertEqual(trace.child, builds, "reopening reuses the loaded level")
        }
    }

    func testPlainMenuCanReturnToTheNativeFramedStyle() throws {
        try onUIThread {
            let style = State(wrappedValue: ButtonStyleKind.plain)
            let host = GTKRenderer.running {
                Menu { MenuItem("Item") } label: { Text("Trigger") }.buttonStyle(style.projectedValue)
            }
            let menu = try XCTUnwrap(host.views(GTKMenuButtonView.self).first)
            XCTAssertEqual(gtk_menu_button_get_has_frame(menu.widget.opaque), 0)
            style.wrappedValue = .automatic
            host.step()
            XCTAssertNotEqual(gtk_menu_button_get_has_frame(menu.widget.opaque), 0)
            XCTAssertTrue(host.views(GTKMenuButtonView.self).first === menu)
        }
    }
}

@MainActor private final class GTKMenuTrace {
    var root = 0
    var child = 0
    var appeared = 0
}
