// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The focus chain's publish and read: `.focusedValue` on the branch holding
// the keyboard, `@FocusedValue` answering the nearest write on it, and the
// scene's own `.focusedSceneValue` beneath both.
//
// The mechanism is in FocusedValues.swift (the bag and its keys), the
// FocusedValueStore the differ keeps (the focused element, the chain fold,
// the scene fold) and FocusedValue.swift (the wrappers, resolved through the
// differ's scope like an `@Environment` slot). Every element inside a
// publishing branch hears `isFocusedChanged`, which is how the store knows
// the chain - and a moved answer rebuilds exactly the readers.

import XCTest
@_spi(Host) @testable import SwiftOmniUICore

/// A command the focused branch publishes - the run-action shape of the
/// SwiftUI example, a string here so a label can show it.
private struct RunKey: FocusedValueKey {
    typealias Value = String
}

extension FocusedValues {
    /// What `\.run` writes and reads.
    fileprivate var run: String? {
        get { self[RunKey.self] }
        set { self[RunKey.self] = newValue }
    }
}

/// Counts how often a body ran.
private final class Builds {
    var count = 0
}

/// The `@FocusedValue` reader - the command menu of the example, a label here.
private struct RunLabel: View {
    let builds: Builds
    @FocusedValue(\.run) private var run

    var body: some View {
        builds.count += 1
        return ModifiedContent(node: label(run ?? "none"))
    }
}

/// The `@FocusedSceneValue` reader - the scene's half of the same read.
private struct SceneRunLabel: View {
    let builds: Builds
    @FocusedSceneValue(\.run) private var run

    var body: some View {
        builds.count += 1
        return ModifiedContent(node: label(run ?? "none"))
    }
}

/// A window whose page is the scene reader - what a rendered `SceneElement`
/// puts the fold's answer under.
private struct ReaderWindow: WindowScene {
    let builds: Builds

    var page: any Page { SceneRunLabel(builds: builds).id("reader") }
}

extension Node {
    /// A `.focusedValue` written on the bare node, the way the modifier
    /// writes it - what a publisher's subtree carries.
    fileprivate func focusedValueWriting<Value>(
        _ keyPath: WritableKeyPath<FocusedValues, Value?>, _ value: Value
    ) -> Node {
        var node = self
        node.focusedValues[keyPath: keyPath] = value
        return node
    }

    /// A `.focusedSceneValue` written on the bare node, the same way.
    fileprivate func sceneFocusedValueWriting<Value>(
        _ keyPath: WritableKeyPath<FocusedValues, Value?>, _ value: Value
    ) -> Node {
        var node = self
        node.sceneFocusedValues[keyPath: keyPath] = value
        return node
    }
}

@MainActor final class FocusedValueTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Renderer.shared.clearInvalidation()
    }

    /// Runs the handler `patch` answers `event` with - the report the host
    /// makes when the element's focus moves.
    @discardableResult
    private func fire(
        _ renders: Renders, _ patch: HostPatch, _ event: Event, _ payload: [PropValue]
    ) -> Bool {
        Renderer.shared.clearInvalidation()
        return renders.fire(patch.events?[event] ?? -1, with: payload)
    }

    // MARK: - The bag

    /// The key reads what was written under it, and nothing where nothing was.
    func testAKeyReadsItsOwnValue() {
        var values = FocusedValues()
        XCTAssertNil(values.run)

        values.run = "go"
        XCTAssertEqual(values.run, "go")

        values.run = nil
        XCTAssertNil(values.run)
    }

    /// An overlaid bag answers the nearer write - the rule the chain fold
    /// applies outermost first.
    func testANearerWriteWins() {
        var outer = FocusedValues()
        outer.run = "outer"
        var inner = FocusedValues()
        inner.run = "inner"

        XCTAssertEqual(outer.overlaid(with: inner).run, "inner")
    }

    // MARK: - Published and read

    /// Before the focus arrives a read answers nothing - and the publisher's
    /// elements carry the report the host makes about focus moves.
    func testAReaderAnswersNothingBeforeTheFocusArrives() throws {
        let renders = Renders()
        let publisher = stack([label("words", id: "field")], id: "pub")
            .focusedValueWriting(\.run, "go")

        let first = renders.render(
            stack([publisher, RunLabel(builds: Builds()).id("reader").node], id: "root"))

        XCTAssertEqual(first.child("reader")?.props["text"], .string("none"))

        // Every element inside the publishing branch hears the platform's
        // focus report - the store's way of knowing the chain.
        let field = try XCTUnwrap(first.at(.manual("pub"), .manual("field")))
        XCTAssertNotNil(field.events?[.isFocusedChanged])
        XCTAssertNotNil(first.child("pub")?.events?[.isFocusedChanged])
    }

    /// The focus arriving inside the publisher answers the reader with its
    /// value - and leaving takes it back.
    func testTheFocusArrivingAnswersTheReader() throws {
        let builds = Builds()
        let renders = Renders()
        let publisher = stack([label("words", id: "field")], id: "pub")
            .focusedValueWriting(\.run, "go")

        let first = renders.render(
            stack([publisher, RunLabel(builds: builds).id("reader").node], id: "root"))
        let field = try XCTUnwrap(first.at(.manual("pub"), .manual("field")))

        XCTAssertTrue(fire(renders, field, .isFocusedChanged, [.bool(true)]))
        let moved = renders.revisit(changed: Renderer.shared.pendingChanges)
        XCTAssertEqual(moved.child("reader")?.props["text"], .string("go"))

        XCTAssertTrue(fire(renders, field, .isFocusedChanged, [.bool(false)]))
        let cleared = renders.revisit(changed: Renderer.shared.pendingChanges)
        XCTAssertEqual(cleared.child("reader")?.props["text"], .string("none"))
    }

    /// A move of the focus rebuilds exactly the reader - the report goes
    /// nowhere it was not read.
    func testAFocusMoveRebuildsTheReaderAlone() throws {
        let builds = Builds()
        let renders = Renders()
        let publisher = stack([label("words", id: "field")], id: "pub")
            .focusedValueWriting(\.run, "go")
        let uninvolved = stack([label("still", id: "still")], id: "still-holder")

        let first = renders.render(stack(
            [publisher, uninvolved, RunLabel(builds: builds).id("reader").node], id: "root"))
        let field = try XCTUnwrap(first.at(.manual("pub"), .manual("field")))

        XCTAssertTrue(fire(renders, field, .isFocusedChanged, [.bool(true)]))
        let before = builds.count
        let moved = renders.revisit(changed: Renderer.shared.pendingChanges)

        XCTAssertEqual(moved.child("reader")?.props["text"], .string("go"))
        XCTAssertEqual(builds.count, before + 1, "the reader rebuilt once")

        // Elements outside a publishing branch are never asked for the report.
        XCTAssertNil(first.child("still")?.events?[.isFocusedChanged])
    }

    /// Two publishers on the chain: the nearer one's write is the answer.
    func testTheNearerPublisherWins() throws {
        let renders = Renders()
        let inner = stack([label("words", id: "field")], id: "inner")
            .focusedValueWriting(\.run, "inner")
        let outer = stack([inner], id: "outer")
            .focusedValueWriting(\.run, "outer")

        let first = renders.render(
            stack([outer, RunLabel(builds: Builds()).id("reader").node], id: "root"))
        let field = try XCTUnwrap(first.at(.manual("outer"), .manual("inner"), .manual("field")))

        XCTAssertTrue(fire(renders, field, .isFocusedChanged, [.bool(true)]))
        let moved = renders.revisit(changed: Renderer.shared.pendingChanges)
        XCTAssertEqual(moved.child("reader")?.props["text"], .string("inner"))
    }

    /// The value a publisher says moved: the reader is described again with
    /// the new answer.
    func testAMovedPublishedValueRebuildsTheReader() throws {
        let builds = Builds()
        let renders = Renders()

        let tree = { (word: String) in
            stack([
                stack([label("words", id: "field")], id: "pub")
                    .focusedValueWriting(\.run, word),
                RunLabel(builds: builds).id("reader").node,
            ], id: "root")
        }

        let first = renders.render(tree("first"))
        let field = try XCTUnwrap(first.at(.manual("pub"), .manual("field")))

        XCTAssertTrue(fire(renders, field, .isFocusedChanged, [.bool(true)]))
        let moved = renders.revisit(changed: Renderer.shared.pendingChanges)
        XCTAssertEqual(moved.child("reader")?.props["text"], .string("first"))

        // The publisher's own state changed its write: the reader follows.
        Renderer.shared.clearInvalidation()
        _ = renders.render(tree("second"))
        let again = renders.revisit(changed: Renderer.shared.pendingChanges)
        XCTAssertEqual(again.child("reader")?.props["text"], .string("second"))
    }

    // MARK: - The scene's own

    /// A `.focusedSceneValue` on a view answers a `@FocusedSceneValue` wherever
    /// in the scene the reader stands - no focus asked for.
    func testASceneValueAnswersWhereverTheReaderStands() {
        let builds = Builds()
        let renders = Renders()
        let side = stack([label("x", id: "x")], id: "side")
            .sceneFocusedValueWriting(\.run, "scene")

        let patch = renders.render(
            stack([side, SceneRunLabel(builds: builds).id("reader").node], id: "root"))

        XCTAssertEqual(patch.child("reader")?.props["text"], .string("scene"))
    }

    /// `.focusedSceneValue` on a `Scene` rides to the scene's root as one
    /// offer, and a view inside reads it - the published bag folded over the
    /// whole scene.
    func testAScenePublishesItsOwnValues() throws {
        let builds = Builds()
        let renders = Renders()
        let record = SceneRecord(id: "9", handedOver: true)
        let scene = Windows(main: { ReaderWindow(builds: builds) })
            .focusedSceneValue(\.run, "go")

        let patch = renders.render(SceneElement(record: record, scene: scene).node)

        let reader = try XCTUnwrap(patch.subtree.first { $0.id == .manual("reader") })
        XCTAssertEqual(reader.props["text"], .string("go"))
    }

    /// Repeated `.focusedSceneValue` calls on a scene collect into one offer -
    /// both keys publish.
    func testRepeatedSceneValuesCollect() {
        var values = FocusedValues()
        let scene = Windows(main: { ReaderWindow(builds: Builds()) })
            .focusedSceneValue(\.run, "go")

        let offering = scene as? OfferingScene
        XCTAssertNotNil(offering)

        if let bag = offering?.object as? FocusedSceneBag {
            values = bag.values
        }
        XCTAssertEqual(values.run, "go")
    }
}
