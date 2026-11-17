// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@_spi(Host) @testable import SwiftOmniUICore

private struct InnerMarkdownPrepared: View {
    let items: [String]
    @State var suffix: String

    var body: some View {
        ForEach(items, id: \.self) { item in
            Text("\(item)\(suffix)")
        }
    }
}

private struct OuterMarkdownStub: View {
    let items: [String]
    let suffix: String

    var body: some View {
        InnerMarkdownPrepared(items: items, suffix: suffix)
    }
}

private struct BubbleWrapperStub<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(EdgeInsets(top: 10, leading: 16, bottom: 15, trailing: 16))
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.blue)
            }
    }
}

private struct SingleBubbleChildStub: View {
    @State var label = "Initial"

    var body: some View {
        BubbleWrapperStub {
            Text(label)
        }
    }
}

@MainActor final class FragmentDistributionTests: XCTestCase {
    func testForEachDistributesFrameBackgroundOverlayAndClipShapePerChild() {
        let patch = Renders().render(VStack {
            ForEach(["One", "Two", "Three"], id: \.self) { item in
                Text(item)
            }
            .padding(8)
            .frame(maxWidth: 320, alignment: .leading)
            .background { Color.red }
            .overlay { Color.blue }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }.node)

        XCTAssertEqual(patch.children.count, 3, "every ForEach child must become its own wrapped item")
        XCTAssertTrue(patch.children.allSatisfy { $0.type == .zStack })
        let texts = patch.subtree.filter { $0.type == .text }.compactMap { $0.props[.text]?.string }
        XCTAssertEqual(texts, ["One", "Two", "Three"])
        XCTAssertEqual(patch.subtree.filter { $0.type == .rectangle }.count, 6)
    }

    func testComposedFragmentDistributesComposedWrapperPerItemInVStack() {
        let patch = Renders().render(VStack {
            BubbleWrapperStub {
                OuterMarkdownStub(items: ["Alpha", "Beta", "Gamma"], suffix: "!")
            }
            .padding(.trailing, 48)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
        }.node)

        XCTAssertEqual(patch.children.count, 3, "composed wrapper must apply to each expanded ForEach element")
        for (index, bubble) in patch.children.enumerated() {
            let zStacks = bubble.subtree.filter { $0.type == .zStack }
            XCTAssertEqual(zStacks.count, 1, "item \(index) should hold one background ZStack")
            let texts = bubble.subtree.filter { $0.type == .text }.compactMap { $0.props[.text]?.string }
            XCTAssertEqual(texts.count, 1)
        }
        let allTexts = patch.subtree.filter { $0.type == .text }.compactMap { $0.props[.text]?.string }
        XCTAssertEqual(allTexts, ["Alpha!", "Beta!", "Gamma!"])
    }

    func testComposedFragmentDistributesPerItemInsideLazyVStackRow() throws {
        let renders = Renders()
        let page = ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(["msg-1"], id: \.self) { _ in
                    BubbleWrapperStub {
                        OuterMarkdownStub(items: ["Para 1", "Code 2"], suffix: "")
                    }
                    .padding(.trailing, 48)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        let root = renders.render(page.node)

        let lazy = try XCTUnwrap(root.subtree.first { $0.type == .lazyVStack })
        let id = try XCTUnwrap(lazy.lazyRows?.identities.first)
        let realize = try XCTUnwrap(lazy.events?[.realizedChanged])
        renders.fire(realize, with: [.strings([id])])
        let settled = renders.render(page.node)

        let realizedRow = try XCTUnwrap(settled.subtree.first { $0.type == .lazyVStack }?.children.first)
        XCTAssertEqual(realizedRow.type, .vStack)
        XCTAssertEqual(realizedRow.children.count, 2, "each markdown block in the row must get its own bubble")
        XCTAssertEqual(realizedRow.subtree.filter { $0.type == .zStack }.count, 2)
    }

    func testStateChangeInsideExpandedComposedFragmentKeepsEnclosingWrappersDistributed() throws {
        let count = State(wrappedValue: 0)
        struct StatefulBlockList: View {
            @Binding var count: Int
            @State var local = "saved"

            var body: some View {
                ForEach(count == 0 ? ["A", "B"] : ["A", "B", "C"], id: \.self) { item in
                    Text("\(item):\(local)")
                }
            }
        }

        let differ = Differ()
        func tree() -> Node {
            VStack {
                BubbleWrapperStub {
                    StatefulBlockList(count: count.projectedValue)
                }
                .padding(.trailing, 24)
            }.node
        }

        let first = differ.reconcile(nil, with: tree())
        XCTAssertEqual(first.patch.children.count, 2)
        XCTAssertEqual(first.patch.subtree.filter { $0.type == .zStack }.count, 2)

        Renderer.shared.clearInvalidation()
        count.wrappedValue = 1
        let update = differ.revisit(first.node, changed: Renderer.shared.pendingChanges)
        XCTAssertEqual(update.node.children.count, 1)
        let updatedTexts = update.node.children[0].children.flatMap { bubble in
            bubble.type == .fragment ? [] : [bubble]
        }
        XCTAssertEqual(updatedTexts.count, 3, "incremental state change must preserve outer wrappers across new count")
        let incrementalTexts = update.patch.subtree.filter { $0.type == .text }.compactMap { $0.props[.text]?.string }
        XCTAssertEqual(incrementalTexts, ["C:saved"])
        XCTAssertEqual(update.patch.subtree.filter { $0.type == .zStack }.count, 1)
        let described = differ.reconcile(update.node, with: tree(), describeAll: true)
        let renderedTexts = described.patch.subtree.filter { $0.type == .text }.compactMap { $0.props[.text]?.string }
        XCTAssertEqual(renderedTexts, ["A:saved", "B:saved", "C:saved"])
        XCTAssertEqual(described.patch.subtree.filter { $0.type == .zStack }.count, 3)
    }

    func testEmptyFragmentAndScrollViewDistributionMatchSwiftUI() throws {
        let emptyPatch = Renders().render(VStack {
            BubbleWrapperStub {
                OuterMarkdownStub(items: [], suffix: "")
            }
        }.node)
        XCTAssertTrue(emptyPatch.children.isEmpty, "an empty fragment emits zero wrapped bubbles")

        let scrollPatch = Renders().render(ScrollView {
            BubbleWrapperStub {
                OuterMarkdownStub(items: ["X", "Y"], suffix: "")
            }
        }.node)
        let contentStack = try XCTUnwrap(scrollPatch.children.first)
        XCTAssertEqual(contentStack.type, .vStack)
        XCTAssertEqual(contentStack.children.count, 2)
        XCTAssertEqual(contentStack.children.filter { $0.type == .zStack }.count, 2)
    }

    func testRepeatedStateChangesInsideDistributedFragmentNeverOverflowTheBuildCounter() throws {
        let count = State(wrappedValue: 0)
        struct Blocks: View {
            @Binding var count: Int
            @State var local = "x"
            var body: some View {
                ForEach(Array(0...(count % 3)), id: \.self) { item in
                    Text("\(item):\(local)")
                }
            }
        }
        func tree() -> Node {
            VStack {
                BubbleWrapperStub { Blocks(count: count.projectedValue) }.padding(.trailing, 24)
            }.node
        }
        let differ = Differ()
        var current = differ.reconcile(nil, with: tree()).node
        // Each full re-description of the distributed element once doubled its
        // build count; 64 doublings trap with an arithmetic overflow.
        for step in 1...200 {
            Renderer.shared.clearInvalidation()
            count.wrappedValue = step
            current = differ.reconcile(current, with: tree(), describeAll: true).node
            Renderer.shared.clearInvalidation()
            current = differ.revisit(current, changed: Renderer.shared.pendingChanges).node
        }
        XCTAssertFalse(current.children.isEmpty)
    }

    func testSingleNonFragmentChildDoesNotDuplicateWrapper() {
        let patch = Renders().render(VStack {
            SingleBubbleChildStub()
        }.node)
        XCTAssertEqual(patch.children.count, 1)
        XCTAssertEqual(patch.children[0].type, .zStack)
        XCTAssertEqual(patch.subtree.filter { $0.type == .text }.compactMap { $0.props[.text]?.string }, ["Initial"])
    }
}
