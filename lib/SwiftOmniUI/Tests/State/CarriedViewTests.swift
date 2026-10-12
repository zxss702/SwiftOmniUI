// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// A composed view is described again when what it was built with changed, or
// when a state it read changed - and CARRIED, subtree and all, otherwise. Its
// inputs are its stored properties, compared by what they are: a value by
// equality, a lent state by the storage it lends, an object by identity, and a
// closure never - whatever cannot be compared counts as changed.
//
// These count the builds, because that is the only way to tell.

import XCTest
@_spi(Host) @testable import SwiftOmniUICore

private final class Builds {
    var count = 0
}

/// A composed view over one value, counting how often its content runs.
private struct Caption: View {
    let text: String
    let builds: Builds

    var body: some View {
        builds.count += 1
        return Text(text)
    }
}

/// The same, handed a closure - an input nothing can compare.
private struct Pressed: View {
    let text: String
    let builds: Builds
    let tapped: () -> Void

    var body: some View {
        builds.count += 1
        return Button(text).onClicked { tapped() }
    }
}

/// A composed view that READS what it is lent.
private struct Shown: View {
    @Binding var text: String
    let builds: Builds

    var body: some View {
        builds.count += 1
        return Text(text)
    }
}

/// A composed view that hands what it is lent straight on, reading nothing.
private struct Typed: View {
    @Binding var text: String
    let builds: Builds

    var body: some View {
        builds.count += 1
        return TextField($text)
    }
}

/// Equality is about the caption, while the counter and keyboard focus belong to the view's lifetime.
private struct EquatableStatefulCaption: View, Equatable {
    let text: String
    let builds: Builds
    @State var counter = 0
    @FocusState var focused: Bool

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.text == rhs.text }

    var body: some View {
        builds.count += 1
        return Text("\(text):\(counter):\(focused)")
    }
}

private final class CaptionContext {
    let text: String
    init(_ text: String) { self.text = text }
}

/// A comparable view's environment must resolve even when its ordinary inputs compare equal.
private struct EquatableEnvironmentCaption: View, Equatable {
    let text: String
    @Environment private var context: CaptionContext?

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.text == rhs.text }

    var body: some View { Text(context?.text ?? "missing") }
}

@MainActor final class CarriedViewTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Renderer.shared.clearInvalidation()
    }

    private var changed: Set<ObjectIdentifier> { Renderer.shared.pendingChanges }

    // MARK: - What it was built with

    func testAnEquatableViewsStateAndFocusSurviveNewInputs() {
        let renders = Renders()
        let builds = Builds()
        let first = EquatableStatefulCaption(text: "before", builds: builds)
        renders.render(first.id("caption").node)
        first.counter = 7
        first.focused = true

        let rebuilt = EquatableStatefulCaption(text: "after", builds: builds)
        let patch = renders.render(rebuilt.id("caption").node, changed: changed)

        XCTAssertEqual(rebuilt.counter, 7, "owned state adopts its previous storage")
        XCTAssertTrue(rebuilt.focused, "a parent's rebuild must not reset keyboard focus")
        XCTAssertEqual(patch.props[.text], .string("after:7:true"))
        XCTAssertFalse(patch.replace)
    }

    func testAnEquatableViewKeepsItsComparisonAndAdoptsStateWhenCarried() {
        let renders = Renders()
        let builds = Builds()
        renders.render(EquatableStatefulCaption(text: "same", builds: builds).id("caption").node)

        let rebuilt = EquatableStatefulCaption(text: "same", builds: builds)
        renders.render(rebuilt.id("caption").node)
        XCTAssertEqual(builds.count, 1, "equal ordinary inputs still carry the body")

        rebuilt.focused = true
        rebuilt.counter = 8
        let patch = renders.revisit(changed: changed)
        XCTAssertEqual(builds.count, 2, "the fresh view lends the same owned state to the carried body")
        XCTAssertEqual(patch.props[.text], .string("same:8:true"))
    }

    func testAnEquatableViewsEnvironmentStillResolvesAndChanges() {
        let renders = Renders()
        let first = CaptionContext("first")
        let second = CaptionContext("second")
        let made = renders.render(EquatableEnvironmentCaption(text: "same").environment(first).id("caption").node)
        XCTAssertEqual(made.props[.text], .string("first"))

        let changed = renders.render(EquatableEnvironmentCaption(text: "same").environment(second).id("caption").node)
        XCTAssertEqual(changed.props[.text], .string("second"))
    }

    func testAComposedViewBuiltWithTheSameInputsIsCarried() {
        let renders = Renders()
        let builds = Builds()

        func tree(_ n: Int) -> Node {
            VStack {
                Text("n \(n)")
                Caption(text: "fixed", builds: builds)
            }.node
        }

        renders.render(tree(1))
        XCTAssertEqual(builds.count, 1)

        let patch = renders.render(tree(2))
        XCTAssertEqual(
            builds.count, 1,
            "the stack was described again and the caption's inputs had not moved")
        XCTAssertEqual(patch.children.count, 1, "only the label travels")
    }

    func testAComposedViewBuiltWithANewValueIsDescribedAgain() {
        let renders = Renders()
        let builds = Builds()

        func tree(_ n: Int) -> Node {
            VStack {
                Text("n \(n)")
                Caption(text: "caption \(n)", builds: builds)
            }.node
        }

        renders.render(tree(1))
        let patch = renders.render(tree(2))
        XCTAssertEqual(builds.count, 2, "a value it was built with moved")
        XCTAssertEqual(texts(in: patch).last, .string("caption 2"))
    }

    func testAClosureHandedToAComposedViewCountsAsChanged() {
        let renders = Renders()
        let builds = Builds()

        func tree(_ n: Int) -> Node {
            VStack {
                Text("n \(n)")
                Pressed(text: "fixed", builds: builds) {}
            }.node
        }

        renders.render(tree(1))
        renders.render(tree(2))
        XCTAssertEqual(
            builds.count, 2,
            "a closure cannot be compared, so the view is built as if it had changed")
    }

    // MARK: - What it read

    func testAStateReadInACarriedViewRebuildsItWhenTheStateMoves() {
        let renders = Renders()
        let builds = Builds()
        let text = State("a")
        let other = State(0)

        func tree() -> Node {
            VStack {
                Text("other \(other.wrappedValue)")
                Shown(text: text.projectedValue, builds: builds)
            }.node
        }

        renders.render(tree())
        XCTAssertEqual(builds.count, 1)

        // The stack is the reader of `other` and is described again for it;
        // the view under it is lent the same storage, so it is carried.
        other.wrappedValue = 1
        renders.revisit(changed: changed)
        XCTAssertEqual(builds.count, 1, "the same storage is lent, so nothing here moved")

        // The view READ the text, so it is the reader of it - and the stack,
        // which reads no text, is left alone.
        Renderer.shared.clearInvalidation()
        text.wrappedValue = "b"
        let patch = renders.revisit(changed: changed)
        XCTAssertEqual(builds.count, 2, "the view read what moved")
        XCTAssertEqual(texts(in: patch).first, .string("b"))
    }

    func testAStateHandedOnByACarriedViewRendersNobodyWhenItMoves() {
        let renders = Renders()
        let builds = Builds()
        let text = State("a")
        let other = State(0)

        func tree() -> Node {
            VStack {
                Text("other \(other.wrappedValue)")
                Typed(text: text.projectedValue, builds: builds)
            }.node
        }

        renders.render(tree())
        other.wrappedValue = 1
        renders.revisit(changed: changed)
        XCTAssertEqual(builds.count, 1, "lent the same storage, the field is carried")

        Renderer.shared.clearInvalidation()
        text.wrappedValue = "b"
        XCTAssertFalse(
            Renderer.shared.needsRender,
            "a state handed on is read by nobody, so a write to it asks for nothing")
    }

    // MARK: - What was written on it

    func testAHandlerWrittenOnACarriedViewIsTheNewestOne() throws {
        let renders = Renders()
        let builds = Builds()
        var heard: [Int] = []

        func tree(_ n: Int) -> Node {
            VStack {
                Text("n \(n)")
                Caption(text: "fixed", builds: builds)
                    .onTapGesture { heard.append(n) }
            }.node
        }

        let first = renders.render(tree(1))
        let id = try XCTUnwrap(first.children.last?.events?["tapGesture"])

        renders.render(tree(2))
        XCTAssertEqual(builds.count, 1, "the caption is carried")

        XCTAssertTrue(renders.fire(id))
        XCTAssertEqual(
            heard, [2],
            "the handler the parent wrote LAST is the one that runs - a handler captures "
                + "what the parent's closure computed, and that closure ran again")
    }

    func testAChangedModifierOnACarriedViewReachesThePatch() {
        let renders = Renders()
        let builds = Builds()

        func tree(_ n: Int) -> Node {
            VStack {
                Caption(text: "fixed", builds: builds)
                    .opacity(Double(n) / 10)
            }.node
        }

        renders.render(tree(5))
        let patch = renders.render(tree(6))
        XCTAssertEqual(
            patch.children.first?.props["opacity"], .number(0.6),
            "what is written ON the view is the parent's to change, carried or not")
    }

    // MARK: - Identity and the message

    func testMovingCarriedViewsReportsOnlyTheirPositions() {
        let renders = Renders()
        let builds = Builds()

        func row(_ text: String) -> Node {
            Caption(text: text, builds: builds).id(text).node
        }

        renders.render(stack([row("a"), row("b")], id: "root"))
        XCTAssertEqual(builds.count, 2)

        let patch = renders.render(stack([row("b"), row("a")], id: "root"))
        XCTAssertEqual(builds.count, 2, "swapping two rows builds neither")
        XCTAssertTrue(patch.arranged)
        XCTAssertEqual(
            patch.children.map(\.id), [.manual("b"), .manual("a")],
            "the list itself says they swapped")
    }

    func testAResyncDescribesWhatACarriedViewWouldOmit() {
        let renders = Renders()
        let builds = Builds()

        func tree() -> Node {
            stack([Caption(text: "a", builds: builds).id("a").node], id: "root")
        }

        renders.render(tree())
        let resync = renders.renderFromScratch(tree())
        XCTAssertEqual(builds.count, 2, "a complete message builds everything")
        XCTAssertEqual(resync.child("a")?.props["text"], .string("a"))
    }

    private func texts(in patch: HostPatch) -> [PropValue] {
        var found: [PropValue] = []

        func walk(_ patch: HostPatch) {
            if let text = patch.props[.text] { found.append(text) }
            patch.children.forEach(walk)
        }

        walk(patch)
        return found
    }
}
