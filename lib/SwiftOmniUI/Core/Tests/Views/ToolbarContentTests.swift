// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The `.toolbar { … }` block and what stands in it.
//
// `ToolbarContent` is to `.toolbar` what `View` is to a layout: an item, a
// group or a spacer is an entry, and a `ToolbarContent` whose `body` lists
// entries composes them. These tests pin the node shape the block writes -
// a `ToolbarItems` slot after the view's own children, each entry keyed by
// where it was written - and where each placement lands.

import XCTest
@_spi(Host) @testable import SwiftOmniUICore

/// A composed view with toolbar entries written ON it - the case a slot is
/// easiest to lose, because a View has no node of its own to keep one in.
private struct Card: View {
    var body: some View {
        VStack {
            Text("card")
        }
    }
}

/// A toolbar content made of others - `AgentToolbar` in ShenYan Code Edit
/// is one of these.
private struct Composed: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) { Text("a") }
        ToolbarSpacer(.fixed)
    }
}

@MainActor final class ToolbarContentTests: XCTestCase {
    private func slot(_ view: some View) -> Node? {
        view.node.built.children.first { $0.type == "ToolbarItems" }
    }

    /// `.toolbar` writes a ToolbarItems slot after the view's own children -
    /// the rule `contextMenu` follows.
    func testAToolbarTravelsAsASlotAfterTheViewsOwnChildren() throws {
        let node = VStack {
            Text("one")
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Text("Save") }
        }
        .node.built

        XCTAssertEqual(node.children.map { $0.type }, ["Text", "ToolbarItems"])
        let items = try XCTUnwrap(node.children.last)
        XCTAssertEqual(items.children.map { $0.type }, ["ToolbarItem"])
        XCTAssertEqual(items.children[0].props["placement"],
                       .enumeration(ToolbarItemPlacement.primaryAction.rawValue))
        XCTAssertEqual(items.children[0].children.map { $0.type }, ["Text"])
    }

    /// `.toolbar` on a COMPOSED view reaches what the view is made of.
    func testAToolbarOnAComposedViewReachesWhatItIsMadeOf() throws {
        let node = Card()
            .toolbar { ToolbarItem("Save").placement(.primaryAction) }
            .node.built

        XCTAssertEqual(node.type, "VStack")
        XCTAssertEqual(node.children.map { $0.type }, ["Text", "ToolbarItems"])
        XCTAssertEqual(node.children.last?.children.first?.props["text"],
                       .string("Save"))
    }

    /// Every statement is keyed by where it was written - the differ's name
    /// for an entry that moves or leaves.
    func testEntriesAreKeyedByWhereTheyStood() throws {
        let items = try XCTUnwrap(slot(VStack { Text("x") }.toolbar {
            ToolbarItem(placement: .confirmationAction) { Text("Done") }
            ToolbarItem(placement: .navigation) { Text("Back") }
        }))

        XCTAssertEqual(items.children.map { $0.key }, ["0", "1"])
    }

    /// An `if` branch and the statement after it are keyed apart, and a
    /// `for` turn keys each of its own.
    func testBranchesAndTurnsKeyTheEntriesTheyMake() throws {
        let items = try XCTUnwrap(slot(VStack { Text("x") }.toolbar {
            ToolbarItem { Text("first") }
            if true {
                ToolbarItem { Text("cond") }
            }
            for _ in 0..<2 {
                ToolbarItem { Text("loop") }
            }
            ToolbarItem { Text("last") }
        }))

        // Each turn's statement and each branch's are keyed apart, the same
        // nesting `ViewBuilder` writes for views.
        XCTAssertEqual(items.children.map { $0.key },
                       ["0", "1.some.0", "2.0.0.0", "2.1.1.0", "3"])
    }

    /// A `ToolbarItemGroup` stands each written view as an item of its own,
    /// in the group's placement, keyed by where the view was written.
    func testAGroupStandsEachViewAsAnItemInItsPlacement() throws {
        let items = try XCTUnwrap(slot(VStack { Text("x") }.toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Text("one")
                Text("two")
            }
        }))

        XCTAssertEqual(items.children.map { $0.type }, ["ToolbarItem", "ToolbarItem"])
        // The group's statement number, its child's place in the group, the
        // view's place in its own block.
        XCTAssertEqual(items.children.map { $0.key }, ["0.0.0", "0.1.1"])
        XCTAssertEqual(items.children.map { $0.props["placement"] },
                       [.enumeration(ToolbarItemPlacement.primaryAction.rawValue),
                        .enumeration(ToolbarItemPlacement.primaryAction.rawValue)])
        XCTAssertEqual(items.children[0].children.map { $0.type }, ["Text"])
    }

    /// A `ToolbarSpacer` is an entry of its own kind: its variant and where
    /// it stands ride the node.
    func testASpacerCarriesItsVariantAndPlacement() throws {
        let items = try XCTUnwrap(slot(VStack { Text("x") }.toolbar {
            ToolbarItem { Text("a") }
            ToolbarSpacer(placement: .primaryAction).variant(.fixed)
        }))

        let spacer = try XCTUnwrap(items.children.last)
        XCTAssertEqual(spacer.type, "ToolbarSpacer")
        XCTAssertEqual(spacer.props["variant"],
                       .enumeration(ToolbarSpacerVariant.fixed.rawValue))
        XCTAssertEqual(spacer.props["placement"],
                       .enumeration(ToolbarItemPlacement.primaryAction.rawValue))
    }

    /// A `ToolbarItem` written with more than one view keeps them together in
    /// the item's room.
    func testAnItemHoldsSeveralViewsSideBySide() throws {
        let items = try XCTUnwrap(slot(VStack { Text("x") }.toolbar {
            ToolbarItem(placement: .primaryAction) {
                Text("a")
                Text("b")
            }
        }))

        let item = try XCTUnwrap(items.children.first)
        XCTAssertEqual(item.children.map { $0.type }, ["HStack"])
        XCTAssertEqual(item.children.first?.children.map { $0.type }, ["Text", "Text"])
    }

    /// A `ToolbarContent` made of others flattens to the entries its body
    /// lists - `Composed` stands for an item and a spacer, in order.
    func testAComposedToolbarContentFlattensToWhatItsBodyLists() throws {
        let items = try XCTUnwrap(slot(VStack { Text("x") }.toolbar {
            Composed()
        }))

        XCTAssertEqual(items.children.map { $0.type }, ["ToolbarItem", "ToolbarSpacer"])
        XCTAssertEqual(items.children[0].props["placement"],
                       .enumeration(ToolbarItemPlacement.primaryAction.rawValue))
    }

    /// The classic collection keeps working alongside the block - a
    /// `ToolbarItem` still describes the same node it did.
    func testTheSessionListStillWritesTheSameNodes() throws {
        let item = ToolbarItem("Delete")
            .placement(.overflow)
            .isDestructive(true)
            .onClicked {}

        XCTAssertEqual(item.node.type, "ToolbarItem")
        XCTAssertEqual(item.node.props["text"], .string("Delete"))
        XCTAssertEqual(item.node.props["placement"],
                       .enumeration(ToolbarItemPlacement.overflow.rawValue))
        XCTAssertEqual(item.node.props["isDestructive"], .bool(true))
        XCTAssertNotNil(item.node.events["clicked"])
    }
}
