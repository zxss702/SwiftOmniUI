// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) @testable import SwiftOmniUICore
import XCTest

/// A `Layout`'s calls are code, so the differ keeps the object by element
/// identity and the host pulls it back; `.layoutValue` rides the same
/// registry on the child that wrote it.
@MainActor final class CustomLayoutTests: XCTestCase {
    /// A tag for the tests.
    private enum SpacingKey: LayoutValueKey {
        static let defaultValue = 0.0
    }

    /// A second tag, for the default answer.
    private enum TagKey: LayoutValueKey {
        static let defaultValue = "none"
    }

    private struct HeightLayout: Layout {
        typealias Cache = Void
        let height: Double

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> Size {
            Size(width: proposal.width ?? 100, height: height)
        }

        func placeSubviews(in bounds: Rect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
            for subview in subviews {
                subview.place(at: Point(bounds.x, bounds.y), proposal: ProposedViewSize(width: bounds.width, height: height))
            }
        }
    }

    private struct StateDrivenLayout: View {
        let height: State<Double>

        var body: some View {
            HeightLayout(height: height.wrappedValue) {
                Text("unchanged").id("child")
            }.id("layout")
        }
    }

    private struct StateTaggedChild: View {
        let value: State<Double?>
        let name: String

        var body: some View {
            var content = ModifiedContent(node: Text("unchanged").id(name).node)
            if let value = value.wrappedValue {
                content = content.layoutValue(key: SpacingKey.self, value: value)
            }
            return content
        }
    }

    private struct PlainChild: View {
        var body: some View { Text("unchanged") }
    }

    /// A layout that records each pass it is asked to run.
    private final class SpyLayout: Layout, @unchecked Sendable {
        typealias Cache = Int

        /// The times `makeCache` ran.
        var made = 0

        /// The proposals `sizeThatFits` was asked.
        var measured: [ProposedViewSize] = []

        /// The bounds `placeSubviews` was given.
        var placed: [(Rect, ProposedViewSize)] = []

        /// The times `updateCache` ran, and the cache it left.
        var updated: [Int] = []

        func makeCache(subviews: Subviews) -> Int {
            made += 1
            return 7
        }

        func updateCache(_ cache: inout Int, subviews: Subviews) {
            cache += 1
            updated.append(cache)
        }

        func sizeThatFits(
            proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache
        ) -> SwiftOmniUICore.Size {
            measured.append(proposal)
            return Size(width: 10 * Double(subviews.count) + Double(cache), height: 20)
        }

        func placeSubviews(
            in bounds: Rect, proposal: ProposedViewSize,
            subviews: Subviews, cache: inout Cache
        ) {
            placed.append((bounds, proposal))
            var y = bounds.y
            for subview in subviews {
                subview.place(at: Point(x: bounds.x, y: y), proposal: .unspecified)
                y += 20
            }
        }
    }

    /// A differ's patch and registry for `view`.
    private func differed(_ view: some View) -> (Differ, HostPatch) {
        let differ = Differ()
        let result = differ.reconcile(nil, with: view.node)
        return (differ, result.patch)
    }

    func testACallAsFunctionOnALayoutMakesACustomLayoutContainer() {
        let layout = SpyLayout()
        let (_, patch) = differed(layout { Text("a") })

        XCTAssertEqual(patch.type, "CustomLayout")
        XCTAssertEqual(patch.children.count, 1)
        XCTAssertEqual(patch.children.first?.type, "Text")
    }

    func testTheLayoutObjectRidesTheRegistryByElementId() {
        let layout = SpyLayout()
        let (differ, patch) = differed(layout { Text("a") })

        XCTAssertNotNil(differ.codeObjects(for: patch.id)?.layout)
    }

    func testStateChangingOnlyTheLayoutValueKeepsASparseHostNotification() throws {
        Renderer.shared.clearInvalidation()
        defer { Renderer.shared.clearInvalidation() }
        let height = State(wrappedValue: 40.0)
        let differ = Differ()
        let first = differ.reconcile(nil, with: StateDrivenLayout(height: height).node)
        let oldBox = try XCTUnwrap(differ.codeObjects(for: first.node.id)?.layout)
        let childIDs = first.node.children.map(\.id)

        height.wrappedValue = 128
        let second = differ.revisit(first.node, changed: Renderer.shared.pendingChanges)
        XCTAssertEqual(second.node.id, first.node.id)
        XCTAssertEqual(second.node.children.map(\.id), childIDs)
        XCTAssertTrue(second.patch.customLayoutChanged)
        XCTAssertFalse(second.patch.isEmpty, "a code-only update must reach the retained native layout")
        XCTAssertTrue(second.patch.properties.isEmpty)
        guard case .unchanged = second.patch.children else {
            return XCTFail("changing a Layout value must not re-describe unchanged children")
        }
        let newBox = try XCTUnwrap(differ.codeObjects(for: second.node.id)?.layout)
        XCTAssertFalse(oldBox === newBox)
        XCTAssertEqual(newBox.measure(proposal: .unspecified, subviews: LayoutSubviews([])).height, 128)

        Renderer.shared.clearInvalidation()
        let clean = differ.revisit(second.node, changed: [])
        XCTAssertFalse(clean.patch.customLayoutChanged)
        XCTAssertTrue(clean.patch.isEmpty)
    }

    func testCustomLayoutNotificationSurvivesPatchMerging() {
        var code = HostPatch(id: .manual("layout"), type: .customLayout)
        code.customLayoutChanged = true
        let later = HostPatch(id: code.id, type: code.type)
        XCTAssertFalse(code.merging(later).isEmpty)
        XCTAssertTrue(code.merging(later).customLayoutChanged)
        XCTAssertTrue(later.merging(code).customLayoutChanged)
    }

    func testChildLayoutValueAddUpdateAndRemovalNotifyOnlyItsCustomContainer() throws {
        Renderer.shared.clearInvalidation()
        defer { Renderer.shared.clearInvalidation() }
        let value = State<Double?>(wrappedValue: nil)
        let differ = Differ()
        let first = differ.reconcile(nil, with: HStack {
            HeightLayout(height: 40) {
                StateTaggedChild(value: value, name: "tagged").id("tagged")
            }.id("owner")
            HeightLayout(height: 40) {
                Text("sibling")
            }.id("other")
        }.node)
        let originalBox = try XCTUnwrap(differ.codeObjects(for: .manual("owner"))?.layout)
        let siblingBox = try XCTUnwrap(differ.codeObjects(for: .manual("other"))?.layout)
        var rendered = first.node

        let values: [Double?] = [20, 80, nil]
        for next in values {
            Renderer.shared.clearInvalidation()
            value.wrappedValue = next
            let update = differ.revisit(rendered, changed: Renderer.shared.pendingChanges)
            let owner = try XCTUnwrap(update.patch.subtree.first { $0.id == .manual("owner") })
            XCTAssertTrue(owner.customLayoutChanged)
            XCTAssertTrue(owner.properties.isEmpty)
            guard case .unchanged = owner.children else {
                return XCTFail("a tag-only change must preserve the child list and its native identities")
            }
            XCTAssertNil(update.patch.subtree.first { $0.id == .manual("other") },
                         "an unrelated custom layout needs no notification")
            XCTAssertTrue(differ.codeObjects(for: .manual("owner"))?.layout === originalBox)
            XCTAssertTrue(differ.codeObjects(for: .manual("other"))?.layout === siblingBox)
            XCTAssertEqual(differ.codeObjects(for: .manual("tagged"))?.values[ObjectIdentifier(SpacingKey.self)] as? Double,
                           next)
            XCTAssertTrue(differ.customLayoutOwners.isEmpty)
            XCTAssertTrue(differ.customLayoutsWithChangedValues.isEmpty)
            rendered = update.node
        }

        Renderer.shared.clearInvalidation()
        let clean = differ.revisit(rendered, changed: [])
        XCTAssertTrue(clean.patch.isEmpty)
    }

    func testNestedLayoutValuesNotifyTheNearestCustomContainer() throws {
        Renderer.shared.clearInvalidation()
        defer { Renderer.shared.clearInvalidation() }
        let value = State<Double?>(wrappedValue: 10)
        let differ = Differ()
        let first = differ.reconcile(nil, with: HeightLayout(height: 100) {
            HeightLayout(height: 40) {
                StateTaggedChild(value: value, name: "tagged").id("tagged")
            }.id("inner")
        }.id("outer").node)

        Renderer.shared.clearInvalidation()
        value.wrappedValue = 60
        let update = differ.revisit(first.node, changed: Renderer.shared.pendingChanges)
        XCTAssertFalse(update.patch.customLayoutChanged,
                       "the outer container only carries the path to its changed descendant")
        XCTAssertTrue(try XCTUnwrap(update.patch.subtree.first { $0.id == .manual("inner") }).customLayoutChanged)
        XCTAssertTrue(differ.customLayoutOwners.isEmpty)
        XCTAssertTrue(differ.customLayoutsWithChangedValues.isEmpty)
    }

    func testChangedLayoutValuesOnAComposedChildPreventStaleCarry() {
        let differ = Differ()
        func tree(_ value: Double) -> Node {
            HeightLayout(height: 40) {
                PlainChild().layoutValue(key: SpacingKey.self, value: value).id("tagged")
            }.id("owner").node
        }
        let first = differ.reconcile(nil, with: tree(10))
        let second = differ.reconcile(first.node, with: tree(70))
        XCTAssertEqual(differ.codeObjects(for: .manual("tagged"))?.values[ObjectIdentifier(SpacingKey.self)] as? Double, 70,
                       "the parent's new tag cannot be carried with the previous code registry entry")
        XCTAssertEqual(second.node.children.map(\.id), first.node.children.map(\.id))
    }

    func testALayoutValueRidesTheChildThatWroteIt() {
        let layout = SpyLayout()
        let (differ, patch) = differed(layout {
            Text("a").layoutValue(key: SpacingKey.self, value: 5)
            Text("b")
        })

        let tagged = patch.children[0]
        let plain = patch.children[1]
        XCTAssertEqual(
            differ.codeObjects(for: tagged.id)?.values[ObjectIdentifier(SpacingKey.self)] as? Double, 5)
        XCTAssertNil(differ.codeObjects(for: plain.id)?.values[ObjectIdentifier(SpacingKey.self)])
    }

    func testAFragmentSpreadsTheValueToTheChildrenItStandsFor() {
        let layout = SpyLayout()
        let (differ, patch) = differed(layout {
            Group {
                Text("a")
                Text("b")
            }
            .layoutValue(key: SpacingKey.self, value: 3)
        })

        for child in patch.subtree where child.type == "Text" {
            XCTAssertEqual(
                differ.codeObjects(for: child.id)?.values[ObjectIdentifier(SpacingKey.self)] as? Double, 3)
        }
    }

    func testTheCodeObjectDiesWithItsElement() {
        let layout = SpyLayout()
        let differ = Differ()
        let first = differ.reconcile(nil, with: layout { Text("a") }.id("flow").node)
        XCTAssertNotNil(differ.codeObjects(for: first.patch.id)?.layout)

        _ = differ.reconcile(first.node, with: Text("gone").id("flow").node)
        XCTAssertNil(differ.codeObjects(for: .manual("flow")))
    }

    func testTheBoxRunsMeasureAndPlaceWithOneCache() {
        let layout = SpyLayout()
        let box = LayoutBox(layout)
        var placedAt: [Point] = []
        let subviews = LayoutSubviews([
            LayoutSubview(
                layoutValues: [:], priority: 0,
                measureSize: { _ in Size(width: 5, height: 5) },
                measureDimensions: { _ in ViewDimensions() },
                placeView: { position, _, _ in placedAt.append(position) })
        ])

        let size = box.measure(
            proposal: ProposedViewSize(width: 50), subviews: subviews)
        box.place(
            in: Rect(x: 1, y: 2, width: 50, height: 20),
            proposal: ProposedViewSize(width: 50, height: 20), subviews: subviews)
        box.update(subviews: subviews)

        XCTAssertEqual(layout.made, 1, "one arrangement makes the cache once")
        XCTAssertEqual(size, Size(width: 17, height: 20))
        XCTAssertEqual(layout.measured, [ProposedViewSize(width: 50)])
        XCTAssertEqual(layout.placed.count, 1)
        XCTAssertEqual(placedAt, [Point(x: 1, y: 2)])
        XCTAssertEqual(layout.updated, [8])
    }

    func testASubviewAnswersTheTagOrTheKeysDefault() {
        var read: (spacing: Double, tag: String)?
        let subview = LayoutSubview(
            layoutValues: [ObjectIdentifier(SpacingKey.self): 9.0], priority: 4,
            measureSize: { _ in Size(width: 0, height: 0) },
            measureDimensions: { _ in ViewDimensions() },
            placeView: { _, _, _ in })
        read = (subview[SpacingKey.self], subview[TagKey.self])

        XCTAssertEqual(read?.spacing, 9)
        XCTAssertEqual(read?.tag, "none")
        XCTAssertEqual(subview.priority, 4)
    }
}
