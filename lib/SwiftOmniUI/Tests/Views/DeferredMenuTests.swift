// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@_spi(Host) @testable import SwiftOmniUICore

@MainActor final class DeferredMenuTests: XCTestCase {
    func testUnopenedLevelsDoNotBuildOrRunTheirAppearanceHandlers() throws {
        let previous = HostRealizations.current
        HostRealizations.current = HostRealization(
            elements: ["MenuButton", "ContextMenu", "Text", "MenuItem"],
            members: [.init(element: "MenuButton", owner: "MenuButton", member: "menuContentRequested")])
        defer { HostRealizations.current = previous }
        let trace = MenuBuildTrace()
        let menu = Menu {
            trace.rootBuilds += 1
            return Menu {
                trace.childBuilds += 1
                return MenuItem("Leaf").onAppear { trace.appearances += 1 }
            } label: { Text("Directory") }
        } label: { Text("Root") }
        let renders = Renders()
        let first = renders.settled(menu.node)
        XCTAssertEqual(trace.rootBuilds, 0)
        XCTAssertEqual(trace.childBuilds, 0)
        XCTAssertEqual(trace.appearances, 0)
        let slot = try XCTUnwrap(first.children.first { $0.type == .contextMenu })
        guard case .some(.replace(let handlers)) = slot.events else { return XCTFail("native content request is missing") }
        XCTAssertTrue(renders.fire(try XCTUnwrap(handlers[ContextMenuContract.contentRequested.token])))
        let opened = renders.renderFromScratch(menu.node)
        XCTAssertEqual(trace.rootBuilds, 1)
        XCTAssertEqual(trace.childBuilds, 0, "opening a directory must not enumerate its unopened subdirectories")
        XCTAssertEqual(trace.appearances, 0)
        let child = try XCTUnwrap(opened.children.first { $0.type == .contextMenu }?.children.first { $0.type == .menuButton })
        let childSlot = try XCTUnwrap(child.children.first { $0.type == .contextMenu })
        guard case .some(.replace(let childHandlers)) = childSlot.events else { return XCTFail("submenu request is missing") }
        XCTAssertTrue(renders.fire(try XCTUnwrap(childHandlers[ContextMenuContract.contentRequested.token])))
        _ = renders.renderFromScratch(menu.node)
        XCTAssertEqual(trace.childBuilds, 1)
        XCTAssertEqual(trace.appearances, 1)
    }

    func testPlainStyleIsInheritedByButtonsAndMenusAndNearestWriteWins() {
        let node = VStack {
            Button("Action")
            Menu { MenuItem("Open") } label: { Text("Menu") }
            Menu { MenuItem("Other") } label: { Text("Automatic") }.buttonStyle(.automatic)
        }.buttonStyle(.plain).node.built
        XCTAssertEqual(node.children[0].props[.buttonStyle], ButtonStyleKind.plain.propValue)
        XCTAssertEqual(node.children[1].props[.buttonStyle], ButtonStyleKind.plain.propValue)
        XCTAssertEqual(node.children[2].props[.buttonStyle], ButtonStyleKind.automatic.propValue)
    }
}

@MainActor private final class MenuBuildTrace {
    var rootBuilds = 0
    var childBuilds = 0
    var appearances = 0
}
