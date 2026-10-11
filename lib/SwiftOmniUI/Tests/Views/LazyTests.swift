// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The children of a lazy container as the core sends them: every identity in
// order, and only the rows a host's window asks for built - each on its own.

import XCTest

@_spi(Host) @testable import SwiftOmniUICore

/// How many times each row was built - a class, so the closure that counts
/// into it is not walked for state.
private final class Built {
    var count = 0
    var numbers: [Int: Int] = [:]
    var appeared: [Int] = []
    var disappeared: [Int] = []
}

private struct CountedLazyIdentity: Hashable, CustomStringConvertible {
    let value: Int
    let built: Built

    var description: String {
        built.count += 1
        return String(value)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.value == rhs.value && lhs.built === rhs.built
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }
}

/// The lazy view under test, built inside a body - where it always stands
/// when an application writes it, so its `@State` is read at build, not at
/// a test's convenience.
private struct LazyPage: View {
    let build: () -> any View

    init(@ViewBuilder _ build: @escaping () -> any View) {
        self.build = build
    }

    var body: some View { build() }
}

@MainActor final class LazyStackTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Renderer.shared.clearInvalidation()
        Renderer.shared.clearStates()
    }

    /// The lazy element in a patch, however deep it sits.
    private func lazy(_ type: NodeType, in patch: HostPatch) throws -> HostPatch {
        try XCTUnwrap(patch.subtree.first { $0.type == type }, "no \(type) in the patch")
    }

    /// What a host says stands in its window.
    private func realize(_ identities: [String], in renders: Renders, lazy list: HostPatch) throws -> HostPatch {
        let handler = try XCTUnwrap(list.events?[.realizedChanged], "the lazy stack hears no realizedChanged")
        renders.fire(handler, with: [.strings(identities)])
        return renders.revisit(changed: Renderer.shared.pendingChanges)
    }

    func testLazyDefaultsRespectFramesAndAlignmentInsideBuilderFragments() throws {
        for horizontal in [false, true] {
            let renders = Renders()
            let type: NodeType = horizontal ? .lazyHGrid : .lazyVGrid
            let patch = renders.render(LazyPage {
                if horizontal {
                    LazyHGrid(rows: [GridItem(.fixed(100))]) {
                        ForEach(0..<3) { row in
                            Text("\(row)").frame(maxHeight: .infinity)
                        }
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.fixed(100))]) {
                        ForEach(0..<3) { row in
                            Text("\(row)").frame(maxWidth: .infinity)
                        }
                    }
                }
            }.node)
            let grid = try lazy(type, in: patch)
            let ids = try XCTUnwrap(grid.props[.items]?.strings)
            let shown = try lazy(type, in: realize(Array(ids.prefix(2)), in: renders, lazy: grid))
            let words = shown.subtree.filter { $0.type == .text }
            XCTAssertEqual(words.count, 2)
            for item in shown.children {
                XCTAssertEqual(item.props[horizontal ? .verticalAlignment : .horizontalAlignment], .enumeration(3))
            }
        }
    }

    /// `lazyRowStack` is core wiring: the differ reads it to turn a row's
    /// fragment into the stack its children stand in - it never crosses to a
    /// host, so a patch carries no such key.
    func testARowStackMarkerStaysInTheCore() throws {
        let renders = Renders()
        let stack = try lazy(.lazyVStack, in: renders.render(LazyPage {
            LazyVStack(spacing: 8) { ForEach(0..<4) { Text("\($0)") } }
        }.node))
        let ids = try XCTUnwrap(stack.props[.items]?.strings)
        let shown = try lazy(.lazyVStack, in: realize([ids[0]], in: renders, lazy: stack))
        XCTAssertNil(shown.subtree.first { $0.props["lazyRowStack"] != nil })
    }

    func testScrollingReusesThePreparedSourceAndDataChangesRebuildIt() throws {
        let built = Built()
        let renders = Renders()
        let stack = try lazy(.lazyVStack, in: renders.render(LazyPage {
            LazyVStack {
                let _ = { built.count += 1 }()
                ForEach(0..<10_000) { Text("\($0)") }
            }
        }.node))
        XCTAssertEqual(built.count, 1)
        for first in stride(from: 0, through: 900, by: 10) {
            _ = try realize((first..<first + 8).map { "0.\($0)" }, in: renders, lazy: stack)
        }
        XCTAssertEqual(built.count, 1, "a viewport update must not rebuild ten thousand identities")
        _ = renders.render(LazyPage {
            LazyVStack {
                let _ = { built.count += 1 }()
                ForEach(0..<100) { Text("Updated \($0)") }
            }
        }.node)
        XCTAssertEqual(built.count, 2, "a fresh source replaces the cached content")
    }

    func testParentUpdatesReuseIdentitiesAndKeepFreshRowBuilders() throws {
        let built = Built()
        let items = (0..<1_000).map { CountedLazyIdentity(value: $0, built: built) }
        let renders = Renders()
        for version in 0..<3 {
            let before = built.count
            let patch = renders.render(LazyPage {
                LazyVStack {
                    ForEach(items) { item in Text("Version \(version / 2), row \(item.value)") }
                }
            }.node)
            if version == 0 {
                XCTAssertEqual(built.count, 1_000)
                let stack = try lazy(.lazyVStack, in: patch)
                _ = try realize(["0.3", "0.4"], in: renders, lazy: stack)
            } else {
                XCTAssertEqual(built.count - before, 2, "only the two mounted rows stringify their identities")
                if version == 1 {
                    XCTAssertTrue(patch.isEmpty, "fresh closures with unchanged output must not invalidate measurements")
                } else {
                    let stack = try lazy(.lazyVStack, in: patch)
                    XCTAssertTrue(stack.lazyContentChanged)
                    XCTAssertEqual(stack.child("0.3")?.props[.text], .string("Version 1, row 3"))
                    XCTAssertEqual(stack.child("0.4")?.props[.text], .string("Version 1, row 4"))
                }
            }
        }
    }

    func testCompositeRowsRetainTheirEntireSubtreeWhenTheWindowMoves() throws {
        let built = Built()
        let renders = Renders()
        let stack = try lazy(.lazyVStack, in: renders.render(LazyPage {
            LazyVStack {
                ForEach(0..<100) { row in
                    Grid {
                        Text("Row \(row)")
                        Button("Delete") {}
                    }
                    .frame(maxWidth: .infinity)
                    .onAppear { built.appeared.append(row) }
                    .onDisappear { built.disappeared.append(row) }
                }
            }
        }.node))
        _ = try realize(["0.3", "0.4"], in: renders, lazy: stack)
        XCTAssertEqual(built.appeared.sorted(), [3, 4])
        let moved = try lazy(.lazyVStack, in: realize(["0.4", "0.5"], in: renders, lazy: stack))
        XCTAssertEqual(built.appeared.sorted(), [3, 4, 5], "row 4 must not appear again")
        XCTAssertEqual(built.disappeared, [3], "only the departing row ends its lifetime")
        let retained = try XCTUnwrap(moved.child("0.4"))
        XCTAssertTrue(retained.children.isEmpty, "the retained row's label and button need no new arrangement")
    }

    /// Every identity crosses in `items`, and no `ForEach` row's content runs
    /// before a host asks for it - the laziness SwiftUI's name promises.
    func testTheIdentitiesCrossAndNoRowIsBuiltUnasked() throws {
        let built = Built()
        let renders = Renders()
        let stack = try lazy(.lazyVStack, in: renders.render(LazyPage {
            LazyVStack {
                ForEach(0..<1_000) { number in
                    built.count += 1
                    built.numbers[number, default: 0] += 1
                    return Text("\(number)")
                }
            }
        }.node))

        XCTAssertEqual(stack.props[.items], .strings((0..<1_000).map { "0.\($0)" }))
        XCTAssertEqual(stack.children.count, 0, "no row is built before the host asks")
        XCTAssertEqual(built.count, 0, "no row's content ran")
    }

    /// A row the window asks for is built as a child of its own, keyed by its
    /// identity; one the window leaves, leaves.
    func testARowAskedIsBuiltAndOneLetGoLeaves() throws {
        let built = Built()
        let renders = Renders()
        let stack = try lazy(.lazyVStack, in: renders.render(LazyPage {
            LazyVStack {
                ForEach(0..<1_000) { number in
                    built.count += 1
                    built.numbers[number, default: 0] += 1
                    return Text("\(number)")
                }
            }
        }.node))

        let shown = try lazy(.lazyVStack, in: realize(["0.3", "0.4"], in: renders, lazy: stack))
        XCTAssertEqual(shown.children.map(\.id), [.manual("0.3"), .manual("0.4")], "in the order they show")
        XCTAssertEqual(shown.child("0.3")?.props[.text], .string("3"))
        XCTAssertEqual(built.count, 2, "only the two asked rows were built")
        XCTAssertEqual(built.numbers[3], 1)
        XCTAssertEqual(built.numbers[4], 1)

        let moved = try lazy(.lazyVStack, in: realize(["0.4", "0.500"], in: renders, lazy: stack))
        XCTAssertEqual(moved.children.map(\.id), [.manual("0.4"), .manual("0.500")])
        XCTAssertNil(moved.child("0.3"), "the row the window left is let go")
        XCTAssertEqual(built.numbers[500], 1, "the new row was built once")
        XCTAssertEqual(built.numbers[3], 1, "the row let go was never rebuilt")
    }

    /// A row's own `.id()` names it - the window's asking follows it rather
    /// than its place.
    func testARowsOwnIdNamesIt() throws {
        let renders = Renders()
        let stack = try lazy(.lazyVStack, in: renders.render(LazyPage {
            LazyVStack {
                ForEach(0..<50) { number in
                    Text("\(number)").id("row-\(number)")
                }
            }
        }.node))

        // A row's `.id()` is read when the row is built - the names the host
        // is asked to realize are the items' identities, built or not.
        let items = try XCTUnwrap(stack.props[.items]?.strings)
        XCTAssertEqual(items.first, "0.0")
        XCTAssertEqual(items[49], "0.49")

        let shown = try lazy(.lazyVStack, in: realize(["0.2"], in: renders, lazy: stack))
        XCTAssertEqual(shown.children.map(\.id), [.manual("row-2")], "the author's id names the row")
        XCTAssertEqual(shown.child("row-2")?.props[.text], .string("2"))
        XCTAssertEqual(shown.child("row-2")?.lazyIdentity, "0.2", "geometry follows the source row")
    }

    @MainActor
    func testExplicitIdsKeepSourceGeometryThroughComposedRowsInEveryLazyContainer() throws {
        for type in [NodeType.lazyVStack, .lazyHStack, .lazyVGrid, .lazyHGrid] {
            let renders = Renders()
            let content = { ForEach(0..<10) { row in LazyPage { Text("Row \(row)") }.id("row-\(row)") } }
            let patch = renders.render(LazyPage {
                switch type {
                case .lazyVStack: LazyVStack { content() }
                case .lazyHStack: LazyHStack { content() }
                case .lazyVGrid: LazyVGrid(columns: [GridItem()]) { content() }
                default: LazyHGrid(rows: [GridItem()]) { content() }
                }
            }.node)
            let container = try lazy(type, in: patch)
            let shown = try lazy(type, in: realize(["0.2", "0.3"], in: renders, lazy: container))
            XCTAssertEqual(shown.children.map(\.id), [.manual("row-2"), .manual("row-3")])
            XCTAssertEqual(shown.children.map(\.lazyIdentity), ["0.2", "0.3"])
            let moved = try lazy(type, in: realize(["0.3", "0.4"], in: renders, lazy: container))
            XCTAssertEqual(moved.child("row-4")?.lazyIdentity, "0.4")
            XCTAssertNil(moved.child("row-2"))
        }
    }

    /// Static children beside a `ForEach` are named by place, built when the
    /// window covers them, and the rows beside them still come lazily.
    func testStaticChildrenBesideARowSource() throws {
        let built = Built()
        let renders = Renders()
        let stack = try lazy(.lazyVStack, in: renders.render(LazyPage {
            LazyVStack {
                Text("Header")
                ForEach(0..<1_000) { number in
                    built.numbers[number, default: 0] += 1
                    return Text("Row \(number)")
                }
                Text("Footer")
            }
        }.node))

        let items = try XCTUnwrap(stack.props[.items]?.strings)
        XCTAssertEqual(items.count, 1_002, "the header, every row's identity, the footer")
        XCTAssertEqual(items.first, "#0", "a static child is named by its path")
        XCTAssertEqual(items.last, "#2")
        XCTAssertEqual(items[1], "1.0", "a row's name rides its statement's segment")
        XCTAssertTrue(built.numbers.isEmpty)

        let shown = try lazy(.lazyVStack, in: realize(["#0", "1.9"], in: renders, lazy: stack))
        XCTAssertEqual(shown.children.map(\.id), [.manual("#0"), .manual("1.9")])
        XCTAssertEqual(shown.child("#0")?.props[.text], .string("Header"))
        XCTAssertEqual(built.numbers[9], 1)
        XCTAssertNil(built.numbers[0], "no row outside the window ran")
    }

    /// Row sources the builder's `for` makes keep their rows lazy, the rows
    /// of each flattened into the same run, keyed under their statement.
    func testRowSourcesInsideAForOfTheBuilder() throws {
        let built = Built()
        let renders = Renders()
        let stack = try lazy(.lazyVStack, in: renders.render(LazyPage {
            LazyVStack {
                for section in 0..<2 {
                    Text("Section \(section)")
                    ForEach(0..<100) { number in
                        built.numbers[section * 100 + number, default: 0] += 1
                        return Text("Cell \(section)-\(number)")
                    }
                }
            }
        }.node))

        let items = try XCTUnwrap(stack.props[.items]?.strings)
        XCTAssertEqual(items.count, 202, "two headers and two hundred cells, all flat")
        XCTAssertEqual(items[0], "#0.0.0", "the first section's header, under turn and statement")
        XCTAssertEqual(items[1], "0.0.1.0", "statement.turn.statement.item")
        XCTAssertEqual(items[100], "0.0.1.99")
        XCTAssertEqual(items[101], "#0.1.0", "the second section's header")
        XCTAssertEqual(items[102], "0.1.1.0")
        XCTAssertTrue(built.numbers.isEmpty, "no cell ran for the names")

        let shown = try lazy(.lazyVStack, in: realize(["0.0.1.42"], in: renders, lazy: stack))
        XCTAssertEqual(shown.children.map(\.id), [.manual("0.0.1.42")])
        XCTAssertEqual(shown.child("0.0.1.42")?.props[.text], .string("Cell 0-42"))
        XCTAssertEqual(built.numbers.count, 1, "one cell built")
    }

    /// The lazy grid names its cells the same way - the host, not the core,
    /// counts the rows they make.
    func testAGridsCellsAreNamedAndAskedForTheSameWay() throws {
        let built = Built()
        let renders = Renders()
        let grid = try lazy(.lazyVGrid, in: renders.render(LazyPage {
            LazyVGrid(columns: [GridItem(), GridItem()]) {
                ForEach(0..<200) { number in
                    built.numbers[number, default: 0] += 1
                    return Text("\(number)")
                }
            }
        }.node))

        XCTAssertEqual(grid.props[.items], .strings((0..<200).map { "0.\($0)" }))
        XCTAssertTrue(built.numbers.isEmpty)

        let shown = try lazy(.lazyVGrid, in: realize(["0.0", "0.1", "0.2", "0.3"], in: renders, lazy: grid))
        XCTAssertEqual(shown.children.map(\.id),
                       [.manual("0.0"), .manual("0.1"), .manual("0.2"), .manual("0.3")])
        XCTAssertEqual(built.numbers.count, 4)
    }

    /// An `if` around a `ForEach` keeps its rows lazy - the branch's name
    /// keys them, and the rows ask only what the window holds.
    func testARowSourceInsideAnIf() throws {
        let built = Built()
        let renders = Renders()
        let stack = try lazy(.lazyVStack, in: renders.render(LazyPage {
            LazyVStack {
                Text("Top")
                if true {
                    ForEach(0..<100) { number in
                        built.numbers[number, default: 0] += 1
                        return Text("Row \(number)")
                    }
                }
            }
        }.node))

        let items = try XCTUnwrap(stack.props[.items]?.strings)
        XCTAssertEqual(items.count, 101)
        XCTAssertEqual(items[0], "#0")
        XCTAssertTrue(items[1].hasSuffix("0"), "the branch keys the row: \(items[1])")
        XCTAssertTrue(built.numbers.isEmpty)

        let shown = try lazy(.lazyVStack, in: realize([items[1]], in: renders, lazy: stack))
        XCTAssertEqual(shown.children.count, 1)
        XCTAssertEqual(built.numbers[0], 1)
    }
}
