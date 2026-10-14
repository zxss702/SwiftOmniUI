// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The children of a lazy container as the core sends them: every identity in
// order, and only the rows a host's window asks for built - each on its own.

import XCTest
import Observation

@_spi(Host) @testable import SwiftOmniUICore

/// How many times each row was built - a class, so the closure that counts
/// into it is not walked for state.
private final class Built {
    var count = 0
    var identityReads = 0
    var numbers: [Int: Int] = [:]
    var appeared: [Int] = []
    var disappeared: [Int] = []
    var rows: [Int: OwnedLazyRow] = [:]
}

/// Count actual identity reads, rather than only String conversions. Reusing
/// interned names can otherwise conceal a scan of the whole collection.
private struct ReadCountedLazyItem: Identifiable {
    let value: Int
    let built: Built
    var id: Int {
        built.identityReads += 1
        return value
    }
}

private final class LazyRowContext {
    let prefix: String
    init(_ prefix: String) { self.prefix = prefix }
}

@Observable private final class ObservedLazyItem {
    var value = 0
}

private struct OwnedLazyRow: View {
    let number: Int
    @State var counter = 0
    @FocusState var focused: Bool
    @Environment private var context: LazyRowContext?

    var body: some View { Text("\(context?.prefix ?? "missing"):\(number):\(counter):\(focused)") }
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

private struct SameSpellingLazyID: Hashable, CustomStringConvertible {
    let value: Int
    var description: String { "file" }
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

    func testFolderEditsInternOnlyNewIDsAndKeepFreshVisibleBuilders() throws {
        let built = Built()
        let renders = Renders()
        let original = (0..<10_000).map { CountedLazyIdentity(value: $0, built: built) }
        func page(_ items: [CountedLazyIdentity], version: Int) -> LazyPage {
            LazyPage {
                LazyVStack {
                    ForEach(items) { item in
                        built.numbers[item.value, default: 0] += 1
                        return Text("v\(version):\(item.value)")
                    }
                    .transition(.opacity)
                }
            }
        }
        let first = try lazy(.lazyVStack, in: renders.render(page(original, version: 0).node))
        let source = try XCTUnwrap(first.lazyRows)
        XCTAssertNil(first.props[.items], "managed lazy sources no longer copy IDs through properties")
        XCTAssertEqual(built.count, 10_000)
        _ = try realize([source.identities[3], source.identities[4]], in: renders, lazy: first)
        let before = built.count
        let inserted = (10_000..<10_100).map { CountedLazyIdentity(value: $0, built: built) }
        let expanded = Array(original[..<5]) + inserted + Array(original[5...])
        let change = try lazy(.lazyVStack, in: renders.render(page(expanded, version: 1).node))
        let next = try XCTUnwrap(change.lazyRows)
        XCTAssertEqual(next.predecessor, ObjectIdentifier(source))
        XCTAssertEqual(built.count - before, 102, "100 new host names and two requested row keys")
        XCTAssertEqual(Set(built.numbers.keys), [3, 4], "expanded offscreen rows do not build")
        XCTAssertEqual(change.child(source.identities[3])?.props[.text], .string("v1:3"))
        XCTAssertEqual(next.identities[3], source.identities[3])
        XCTAssertEqual(next.inserted.count, 100)

        let collapsed = try lazy(.lazyVStack, in: renders.render(page(original, version: 2).node))
        XCTAssertEqual(collapsed.lazyRows?.removed.count, 100)
        XCTAssertEqual(collapsed.lazyRows?.identities, source.identities)
        XCTAssertEqual(Set(built.numbers.keys), [3, 4])
    }

    func testHashableIdentityDoesNotCollapseRowsWithTheSameDescription() throws {
        let renders = Renders()
        let first = try lazy(.lazyVStack, in: renders.render(LazyPage {
            LazyVStack {
                ForEach([SameSpellingLazyID(value: 1), SameSpellingLazyID(value: 2)]) {
                    Text("Row \($0.value)")
                }
            }
        }.node))
        let ids = try XCTUnwrap(first.lazyRows?.identities)
        XCTAssertEqual(Set(ids).count, 2)
        let shown = try lazy(.lazyVStack, in: realize(ids, in: renders, lazy: first))
        XCTAssertEqual(shown.children.compactMap { $0.props[.text]?.string }, ["Row 1", "Row 2"])
        let reordered = try lazy(.lazyVStack, in: renders.render(LazyPage {
            LazyVStack {
                ForEach([SameSpellingLazyID(value: 2), SameSpellingLazyID(value: 1)]) {
                    Text("Updated \($0.value)")
                }
            }
        }.node))
        XCTAssertEqual(reordered.lazyRows?.identities, ids.reversed().map { $0 })
        XCTAssertEqual(reordered.children.map(\.id), ids.reversed().map { .manual($0) })
        XCTAssertEqual(reordered.children.compactMap { $0.props[.text]?.string }, ["Updated 2", "Updated 1"])
    }

    func testForegroundOnAModifiedRowSourceFillsOnlyRequestedShapes() throws {
        let built = Built()
        let renders = Renders()
        let container = try lazy(.lazyVStack, in: renders.render(LazyPage {
            LazyVStack {
                ForEach(0..<10_000) { number in
                    built.numbers[number, default: 0] += 1
                    return Capsule(style: .continuous)
                }
                .transition(.opacity)
                .foregroundStyle(.black.opacity(0.03))
            }
        }.node))
        let ids = try XCTUnwrap(container.lazyRows?.identities)
        XCTAssertTrue(built.numbers.isEmpty)

        let shown = try lazy(.lazyVStack, in: realize([ids[20], ids[21]], in: renders, lazy: container))
        XCTAssertEqual(Set(built.numbers.keys), [20, 21])
        XCTAssertEqual(shown.children.count, 2)
        for child in shown.children {
            XCTAssertEqual(child.props[.fill], Brush.solidColor(.black.opacity(0.03)).propValue)
        }
    }

    func testModifiedSourcesBuildOnlyRequestedRowsInEveryLazyContainer() throws {
        for type in [NodeType.lazyVStack, .lazyHStack, .lazyVGrid, .lazyHGrid] {
            let built = Built()
            let renders = Renders()
            let page = LazyPage {
                let content = ForEach(0..<10_000) { number in
                    built.numbers[number, default: 0] += 1
                    return OwnedLazyRow(number: number)
                }
                .transition(.blur.combined(with: .offset(y: -48)))
                .opacity(0.75)
                .environment(LazyRowContext("configured"))
                switch type {
                case .lazyVStack: LazyVStack { content }
                case .lazyHStack: LazyHStack { content }
                case .lazyVGrid: LazyVGrid(columns: [GridItem()]) { content }
                default: LazyHGrid(rows: [GridItem()]) { content }
                }
            }
            let container = try lazy(type, in: renders.render(page.node))
            let ids = try XCTUnwrap(container.lazyRows?.identities)
            XCTAssertEqual(ids.count, 10_000)
            XCTAssertTrue(built.numbers.isEmpty, "node modifiers must not execute offscreen row closures")

            let shown = try lazy(type, in: realize([ids[20], ids[21]], in: renders, lazy: container))
            XCTAssertEqual(Set(built.numbers.keys), [20, 21])
            for child in shown.children {
                XCTAssertEqual(child.props[.opacity], .number(0.75))
                XCTAssertNotNil(child.props[.transition])
                XCTAssertTrue(child.props[.text]?.string?.hasPrefix("configured:") == true)
            }
        }
    }

    func testModifiedGroupsAndBranchesKeepSourcesAndStatementKeys() throws {
        let built = Built()
        let renders = Renders()
        let container = try lazy(.lazyVStack, in: renders.render(LazyPage {
            LazyVStack {
                Text("Before")
                Group {
                    Text("Section")
                    if true {
                        ForEach(0..<10_000) { number in
                            built.numbers[number, default: 0] += 1
                            return Text("Row \(number)").id("row-\(number)")
                        }
                        .transition(.opacity)
                    }
                }
                .opacity(0.5)
                Text("After")
            }
        }.node))
        let ids = try XCTUnwrap(container.lazyRows?.identities)
        XCTAssertEqual(ids.count, 10_003)
        XCTAssertEqual(ids.first, "#0")
        XCTAssertEqual(ids.last, "#2")
        XCTAssertTrue(ids[2].hasPrefix("1."), "group rows keep their statement and branch scope")
        XCTAssertTrue(built.numbers.isEmpty)

        let shown = try lazy(.lazyVStack, in: realize([ids[0], ids[1], ids[44], ids.last!], in: renders, lazy: container))
        XCTAssertEqual(Set(built.numbers.keys), [42])
        let row = try XCTUnwrap(shown.child("row-42"))
        XCTAssertEqual(row.lazyIdentity, ids[44])
        XCTAssertEqual(row.props[.opacity], .number(0.5))
        XCTAssertNotNil(row.props[.transition])
        XCTAssertEqual(shown.children.compactMap { $0.props[.text]?.string }, ["Before", "Section", "Row 42", "After"])
    }

    func testModifiedSourcesKeepOwnedStateAndFocusDuringExpansionAndReordering() throws {
        let built = Built()
        let renders = Renders()
        func tree(_ items: [Int], version: Int) -> Node {
            LazyPage {
                LazyVStack {
                    Text("Header")
                    ForEach(items) { number in
                        built.numbers[number, default: 0] += 1
                        let row = OwnedLazyRow(number: number)
                        built.rows[number] = row
                        return row
                    }
                    .environment(LazyRowContext("v\(version)"))
                    .transition(.opacity)
                }
            }.node
        }
        let items = Array(0..<10_000)
        let container = try lazy(.lazyVStack, in: renders.render(tree(items, version: 0)))
        let ids = try XCTUnwrap(container.lazyRows?.identities)
        _ = try realize([ids[1], ids[2]], in: renders, lazy: container)
        let first = try XCTUnwrap(built.rows[1])
        first.counter = 7
        first.focused = true

        let changes = [[0, 1, 10_000, 10_001] + Array(2..<10_000), items, [0, 2, 1] + Array(3..<10_000)]
        for (version, changedItems) in changes.enumerated() {
            let updated = try lazy(.lazyVStack, in: renders.render(
                tree(changedItems, version: version + 1), changed: Renderer.shared.pendingChanges))
            let retained = try XCTUnwrap(built.rows[1])
            XCTAssertEqual(retained.counter, 7)
            XCTAssertTrue(retained.focused)
            XCTAssertEqual(Set(built.numbers.keys), [0, 1], "expansion and moves do not execute offscreen builders")
            let row = try XCTUnwrap(updated.child(ids[2]))
            XCTAssertFalse(row.replace)
            XCTAssertEqual(row.props[.text], .string("v\(version + 1):1:7:true"))
        }
    }

    func testModifiedSourcesReuseIdentityIndexesButRefreshRowsAndModifiers() throws {
        let built = Built()
        let items = (0..<10_000).map { CountedLazyIdentity(value: $0, built: built) }
        let renders = Renders()
        var ids: [String] = []
        for version in 0..<3 {
            let before = built.count
            let container = try lazy(.lazyVStack, in: renders.render(LazyPage {
                LazyVStack {
                    ForEach(items) { item in Text("v\(version):\(item.value)") }
                        .opacity(version == 0 ? 1 : 0.5)
                        .transition(.opacity)
                }
            }.node))
            if version == 0 {
                ids = try XCTUnwrap(container.lazyRows?.identities)
                XCTAssertEqual(built.count, 10_000)
                _ = try realize([ids[3], ids[4]], in: renders, lazy: container)
            } else {
                XCTAssertEqual(built.count - before, 2, "parent updates reuse the prepared identity index")
                XCTAssertEqual(container.child(ids[3])?.props[.text], .string("v\(version):3"))
                if version == 1 { XCTAssertEqual(container.child(ids[3])?.props[.opacity], .number(0.5)) }
            }
        }
    }

    func testOrdinaryContainersAndPickersStillExpandModifiedSources() throws {
        let built = Built()
        let renders = Renders()
        let stack = renders.render(VStack {
            ForEach([3, 1, 2]) { number in
                built.numbers[number, default: 0] += 1
                return Text("Row \(number)")
            }
            .opacity(0.5)
            .transition(.opacity)
        }.node)
        XCTAssertEqual(stack.children.compactMap { $0.props[.text]?.string }, ["Row 3", "Row 1", "Row 2"])
        XCTAssertEqual(built.numbers, [3: 1, 1: 1, 2: 1])
        for row in stack.children {
            XCTAssertEqual(row.props[.opacity], .number(0.5))
            XCTAssertNotNil(row.props[.transition])
        }

        let selection = State(wrappedValue: 1)
        let picker = Picker("Choice", selection: selection.projectedValue) {
            ForEach([3, 1, 2]) { number in Text("Choice \(number)").tag(number) }
                .transition(.opacity)
        }
        let pickerRenders = Renders()
        let patch = pickerRenders.render(picker.node)
        XCTAssertEqual(patch.props[.options], .strings(["Choice 3", "Choice 1", "Choice 2"]))
        XCTAssertEqual(patch.props[.selectedIndex], .number(1))
        let changed = try XCTUnwrap(patch.events?[.selectedIndexChanged])
        pickerRenders.fire(changed, with: [.number(2)])
        XCTAssertEqual(selection.wrappedValue, 2, "tags still write the selected value back")
    }

    func testDeferredFragmentsKeepEveryChildOfACompositeRow() {
        let patch = Renders().render(VStack {
            Group {
                ForEach([0, 1]) { number in
                    Text("Heading \(number)")
                    Text("Detail \(number)")
                }
                .transition(.opacity)
            }
            .opacity(0.5)
        }.node)
        XCTAssertEqual(patch.children.compactMap { $0.props[.text]?.string },
                       ["Heading 0", "Detail 0", "Heading 1", "Detail 1"])
        XCTAssertEqual(Set(patch.children.map(\.id)).count, 4, "composite rows keep distinct child paths")
        for child in patch.children {
            XCTAssertEqual(child.props[.opacity], .number(0.5))
            XCTAssertNotNil(child.props[.transition])
        }
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
            let ids = try XCTUnwrap(grid.lazyRows?.identities)
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
        let ids = try XCTUnwrap(stack.lazyRows?.identities)
        let shown = try lazy(.lazyVStack, in: realize([ids[0]], in: renders, lazy: stack))
        XCTAssertNil(shown.subtree.first { $0.props["lazyRowStack"] != nil })
    }

    func testACompositeRowKeepsUnspecifiedAndExplicitStackSpacing() throws {
        let spacings: [Double?] = [nil, 0, 12]
        for spacing in spacings {
            let renders = Renders()
            let stack = try lazy(.lazyVStack, in: renders.render(LazyPage {
                LazyVStack(spacing: spacing) {
                    ForEach(0..<2) { row in
                        Text("name \(row)")
                        Text("detail \(row)")
                    }
                }
            }.node))
            let identity = try XCTUnwrap(stack.lazyRows?.identities.first)
            let shown = try lazy(.lazyVStack, in: realize([identity], in: renders, lazy: stack))
            let row = try XCTUnwrap(shown.subtree.first { $0.type == .vStack })
            XCTAssertEqual(row.props[.spacing]?.number, spacing)
            XCTAssertEqual(row.children.filter { $0.type == .text }.count, 2)
        }
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

    func testArrayViewportUpdatesReadOnlyRequestedIdsAtDifferentDataScales() throws {
        for count in [1_000, 10_000, 100_000] {
            Renderer.shared.clearInvalidation()
            Renderer.shared.clearStates()
            let built = Built()
            let items = (0..<count).map { ReadCountedLazyItem(value: $0, built: built) }
            let renders = Renders()
            let stack = try lazy(.lazyVStack, in: renders.render(LazyPage {
                LazyVStack {
                    ForEach(items) { item in
                        built.count += 1
                        return Text("Row \(item.value)")
                    }
                }
            }.node))
            let source = try XCTUnwrap(stack.lazyRows)
            XCTAssertEqual(built.identityReads, count, "initial source identification reads each ID once")
            XCTAssertEqual(built.count, 0, "identifying the source must not build rows")

            for first in [0, 4, count / 2, count - 8] {
                let before = built.identityReads, made = built.count
                let shown = try lazy(.lazyVStack, in: realize(
                    Array(source.identities[first..<first + 8]), in: renders, lazy: stack))
                XCTAssertLessThanOrEqual(built.identityReads - before, 8,
                                         "scrolling an array of \(count) items must not enumerate every ID")
                XCTAssertLessThanOrEqual(built.count - made, 8)
                XCTAssertNil(shown.lazyRows, "viewport changes retain the existing identity source")
                XCTAssertEqual(shown.children.count, 8, "rows outside the requested window leave the tree")
                XCTAssertEqual(Set(shown.children.map(\.id)),
                               Set(source.identities[first..<first + 8].map { .manual($0) }))
            }
        }
    }

    func testRepeatedArrayDescriptionReusesItsIdentityBufferWithoutReadingRows() {
        let built = Built()
        let items = (0..<10_000).map { ReadCountedLazyItem(value: $0, built: built) }
        let before = ForEach(items) { item in Text("Row \(item.value)") }
        let again = ForEach(items) { item in Text("Updated \(item.value)") }
        XCTAssertTrue(again.hasSameLazyIdentities(as: before))
        XCTAssertEqual(built.identityReads, 0)

        var changed = items
        changed.insert(ReadCountedLazyItem(value: -1, built: built), at: 5)
        let expanded = ForEach(changed) { item in Text("Row \(item.value)") }
        XCTAssertFalse(expanded.hasSameLazyIdentities(as: before))
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

    /// The shared snapshot names every identity, and no row's content runs
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

        XCTAssertEqual(stack.lazyRows?.identities, (0..<1_000).map { "0.\($0)" })
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
        XCTAssertEqual(built.numbers[4], 1, "a retained row must be reused before executing its builder")
        XCTAssertEqual(built.numbers[3], 1, "the row let go was never rebuilt")
    }

    func testScrollingDropsDepartedRowClosureDependencies() throws {
        let states = (0..<1_000).map { State(wrappedValue: $0) }
        let renders = Renders()
        let stack = try lazy(.lazyVStack, in: renders.render(LazyPage {
            LazyVStack {
                ForEach(0..<1_000) { number in
                    Text("\(states[number].wrappedValue)")
                }
            }
        }.node))
        _ = try realize(["0.3", "0.4"], in: renders, lazy: stack)
        XCTAssertTrue(Renderer.shared.isRead(states[3].storage))
        XCTAssertTrue(Renderer.shared.isRead(states[4].storage))
        _ = try realize(["0.4", "0.500"], in: renders, lazy: stack)
        XCTAssertFalse(Renderer.shared.isRead(states[3].storage), "a departed closure is no longer a live reader")
        XCTAssertTrue(Renderer.shared.isRead(states[4].storage), "reuse preserves the retained closure's reads")
        XCTAssertTrue(Renderer.shared.isRead(states[500].storage))
        Renderer.shared.clearInvalidation()
        states[3].wrappedValue = 30
        XCTAssertFalse(Renderer.shared.needsRender, "offscreen rows must not accumulate invalidations")
        states[4].wrappedValue = 40
        let changed = try lazy(.lazyVStack, in: renders.revisit(changed: Renderer.shared.pendingChanges))
        XCTAssertEqual(changed.child("0.4")?.props[.text], .string("40"))
    }

    func testViewportReuseKeepsExplicitIdsAndFragmentRowsWithoutBuildingThemAgain() throws {
        let built = Built()
        let renders = Renders()
        let stack = try lazy(.lazyVStack, in: renders.render(LazyPage {
            LazyVStack {
                ForEach(0..<1_000) { number in
                    built.numbers[number, default: 0] += 1
                    return Group {
                        Text("Row \(number)").id("label-\(number)")
                        Text("Kind")
                    }
                    .id("entry-\(number)")
                    .transition(.opacity)
                }
            }
        }.node))
        _ = try realize(["0.3", "0.4"], in: renders, lazy: stack)
        let moved = try lazy(.lazyVStack, in: realize(["0.4", "0.5"], in: renders, lazy: stack))
        XCTAssertEqual(built.numbers, [3: 1, 4: 1, 5: 1])
        XCTAssertNotNil(moved.child("label-4"))
        XCTAssertNotNil(moved.child("label-5"))
    }

    func testWindowObservationsStayBoundedWhileTraversingTheWholeSource() throws {
        let differ = Differ()
        var root = differ.reconcile(nil, with: LazyPage {
            LazyVStack {
                ForEach(0..<10_000) { Text("Row \($0)") }
            }
        }.node).node
        func find(_ node: RenderedNode) -> RenderedNode? {
            if node.lazySource != nil { return node }
            return node.children.lazy.compactMap(find).first
        }
        let list = try XCTUnwrap(find(root))
        let sourceReads = list.lazySourceReads.count
        let window = try XCTUnwrap(list.lazySource?.lazyWindow)
        for first in stride(from: 0, through: 9_990, by: 90) {
            let id = try XCTUnwrap(list.events[.realizedChanged])
            let callback = try XCTUnwrap(differ.handler(id))
            EventBuffer.current = [.strings((first..<first + 8).map { "0.\($0)" })]
            Renderer.shared.start(callback)
            root = differ.revisit(root, changed: [window]).node
            XCTAssertEqual(list.lazySourceReads.count, sourceReads, "scrolling does not append source observation tokens")
            XCTAssertLessThanOrEqual(list.reads.count, sourceReads + 8, "only current row observations remain live")
            XCTAssertEqual(list.children.count, 8)
        }
    }

    func testAnOffscreenObservableItemNoLongerInvalidatesTheContainer() throws {
        let items = (0..<1_000).map { _ in ObservedLazyItem() }
        let renders = Renders()
        let stack = try lazy(.lazyVStack, in: renders.render(LazyPage {
            LazyVStack {
                ForEach(items.indices) { number in
                    Text("\(items[number].value)")
                }
            }
        }.node))
        _ = try realize(["0.3", "0.4"], in: renders, lazy: stack)
        _ = try realize(["0.4", "0.500"], in: renders, lazy: stack)
        Renderer.shared.clearInvalidation()
        items[3].value = 30
        XCTAssertFalse(Renderer.shared.needsRender)
        items[4].value = 40
        XCTAssertTrue(Renderer.shared.needsRender)
        let changed = try lazy(.lazyVStack, in: renders.revisit(changed: Renderer.shared.pendingChanges))
        XCTAssertEqual(changed.child("0.4")?.props[.text], .string("40"))
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
        let items = try XCTUnwrap(stack.lazyRows?.identities)
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

        let items = try XCTUnwrap(stack.lazyRows?.identities)
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

        let items = try XCTUnwrap(stack.lazyRows?.identities)
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

        XCTAssertEqual(grid.lazyRows?.identities, (0..<200).map { "0.\($0)" })
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

        let items = try XCTUnwrap(stack.lazyRows?.identities)
        XCTAssertEqual(items.count, 101)
        XCTAssertEqual(items[0], "#0")
        XCTAssertTrue(items[1].hasSuffix("0"), "the branch keys the row: \(items[1])")
        XCTAssertTrue(built.numbers.isEmpty)

        let shown = try lazy(.lazyVStack, in: realize([items[1]], in: renders, lazy: stack))
        XCTAssertEqual(shown.children.count, 1)
        XCTAssertEqual(built.numbers[0], 1)
    }
}
