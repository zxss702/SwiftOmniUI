// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) @testable import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

final class WinUIDeferredMenuTests: XCTestCase {
    func testNativeOpeningRequestsOneLevelAndPreservesTheFlyout() throws {
        try onUIThread {
            let previous = HostRealizations.current
            CoreLink().setRealization(WinUIRegistrations.registry.realization, unrealized: WinUIRealization.unmade)
            defer { HostRealizations.current = previous }
            let trace = WinUIMenuTrace()
            let entries = State(wrappedValue: ["Leaf"])
            let host = WinUIRenderer.running {
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
            let root = try XCTUnwrap(host.views(WinUIMenuButtonView.self).first)
            XCTAssertEqual(trace.root, 0)
            XCTAssertEqual(trace.child, 0)
            let identity = swiftomniui_winui_menu_identity_for_testing(root.handle)
            XCTAssertNotEqual(identity, 0)
            swiftomniui_winui_menu_open_for_testing(root.handle)
            host.settle { trace.root == 1 }
            XCTAssertEqual(trace.root, 1)
            XCTAssertEqual(trace.child, 0, "unopened directories must not recursively populate")
            XCTAssertEqual(swiftomniui_winui_menu_identity_for_testing(root.handle), identity)
            host.step()
            host.layOut()
            XCTAssertEqual(trace.child, 0, "initial native focus must not load a closed submenu")
            let branch = try XCTUnwrap(host.runtime.tree.root?.first(id: .manual("branch")))
            XCTAssertTrue(swiftomniui_winui_menu_open_submenu_for_testing(root.handle, branch.mount))
            host.settle { trace.child == 1 }
            XCTAssertEqual(trace.child, 1)
            XCTAssertEqual(trace.appeared, 1)
            XCTAssertEqual(swiftomniui_winui_menu_identity_for_testing(root.handle), identity)
            XCTAssertTrue(host.views(WinUIMenuButtonView.self).first === root)
            entries.wrappedValue = ["First", "Second"]
            host.settle { root.shown.titles.contains("Second") }
            XCTAssertTrue(root.shown.titles.contains("First"))
            XCTAssertTrue(root.shown.titles.contains("Second"))
            XCTAssertEqual(swiftomniui_winui_menu_identity_for_testing(root.handle), identity)
        }
    }

    func testPlainMenuRestoresItsNativeFrameWhenTheStyleChanges() throws {
        try onUIThread {
            let style = State(wrappedValue: ButtonStyleKind.plain)
            let host = WinUIRenderer.running {
                Menu { MenuItem("Item") } label: { Text("Trigger") }.buttonStyle(style.projectedValue)
            }
            let menu = try XCTUnwrap(host.views(WinUIMenuButtonView.self).first)
            XCTAssertEqual(Self.read(menu, "background"), "#00000000")
            XCTAssertEqual(Self.read(menu, "borderThickness"), "0,0,0,0")
            XCTAssertEqual(Self.read(menu, "padding"), "0,0,0,0")
            style.wrappedValue = .automatic
            host.settle { Self.read(menu, "borderThickness") != "0,0,0,0" }
            XCTAssertNotEqual(Self.read(menu, "borderThickness"), "0,0,0,0")
            XCTAssertNotEqual(Self.read(menu, "padding"), "0,0,0,0")
            XCTAssertTrue(host.views(WinUIMenuButtonView.self).first === menu)
        }
    }

    @MainActor private static func read(_ view: WinUIView, _ what: String) -> String {
        WinUIStrings.read { swiftomniui_winui_read(view.handle, what, $0, $1) }
    }
}

@MainActor private final class WinUIMenuTrace {
    var root = 0
    var child = 0
    var appeared = 0
}
