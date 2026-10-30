// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0
//
// A link pushes a page onto the stack it stands in - as Swift describes it.
//
// The pages a NavigationLink pushed live in the stack element's session, so
// the differ hands the same store back on every render, and the producer
// runs while it is in hand: a push is a state change the next render's
// children answer.

import XCTest
@_spi(Host) @testable import SwiftOmniUICore

/// A page with a link on it, named as it comes into the tree.
private struct Opener: View {
    @Environment private var page: PageSession

    var body: some View {
        NavigationLink {
            Pushed()
        } label: {
            ModifiedContent(node: label("go"))
        }
        .onAppear { page.title = "Home" }
    }
}

/// The page the link pushes, with a way back of its own - a `\.dismiss`
/// like any pushed page's.
private struct Pushed: View {
    @Environment private var page: PageSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            ModifiedContent(node: label("pushed"))
            Button("back").onClicked { dismiss() }
        }
        .onAppear { page.title = "Pushed" }
    }
}

/// A route's page on a path-bound stack, named for what it stands for.
private struct Level: View {
    @Environment private var page: PageSession
    let depth: Int

    var body: some View {
        ModifiedContent(node: label("level \(depth)"))
            .onAppear { page.title = "level \(depth)" }
    }
}

/// The stack under test: one page, and the links it carries.
private func stack() -> NavigationStack {
    NavigationStack { Opener() }
}

/// The element a `tapGesture` handler hangs on, anywhere in the tree.
private extension HostPatch {
    var tapped: Int? {
        subtree.compactMap { $0.events?["tapGesture"] }.first
    }
}

@MainActor final class NavigationLinkTests: XCTestCase {
    // MARK: - What goes out

    /// A link is its label and a push is its press: it draws no chrome of
    /// its own, so the tree holds the label with a tap gesture on it.
    func testALinkIsItsLabelAnsweringATap() {
        let patch = Renders().settled(stack().node)

        let text = patch.subtree.first { $0.props["text"] == .string("go") }
        XCTAssertNotNil(text?.events?["tapGesture"],
                        "the label carries the link's push as a tap")
    }

    /// The push puts the destination page ABOVE the root, keyed like every
    /// other page the stack describes.
    func testATapPushesTheDestinationOnTheStack() throws {
        let renders = Renders()
        let patch = renders.settled(stack().node)

        XCTAssertEqual(patch.children.count, 1)
        let tap = try XCTUnwrap(patch.tapped)

        XCTAssertTrue(renders.fire(tap))

        let next = renders.settled(stack().node)
        XCTAssertEqual(next.children.map { $0.id }, [.manual("root"), .manual("link-0")])
        XCTAssertEqual(next.children[1].props["title"], .string("Pushed"))
    }

    /// A second link pushed while the first is on the stack stands above it
    /// - the links' pages are the stack's own pages, and the links in one
    /// find the same stack.
    func testLinksPushInOrder() throws {
        let renders = Renders()
        let patch = renders.settled(stack().node)
        let tap = try XCTUnwrap(patch.tapped)

        XCTAssertTrue(renders.fire(tap))
        renders.settled(stack().node)
        XCTAssertTrue(renders.fire(tap), "the same link fires again")

        let next = renders.settled(stack().node)
        XCTAssertEqual(next.children.map { $0.id },
                       [.manual("root"), .manual("link-0"), .manual("link-1")])
    }

    // MARK: - What comes back

    /// A completed pop past the links' depth drops them - the report names
    /// the depth that stands, and the store shortens to it.
    func testACompletedPopDropsPushedLinks() throws {
        let renders = Renders()
        var patch = renders.settled(stack().node)
        let popped = try XCTUnwrap(patch.events?["popped"])

        XCTAssertTrue(renders.fire(try XCTUnwrap(patch.tapped)))
        patch = renders.settled(stack().node)
        XCTAssertEqual(patch.children.count, 2)

        XCTAssertTrue(renders.fire(popped, with: [.number(0)]))

        let next = renders.settled(stack().node)
        XCTAssertEqual(next.children.map { $0.id }, [.manual("root")])
    }

    /// `\.dismiss` inside a pushed page backs the stack out of it - the same
    /// way back a path-pushed page takes.
    func testAPushedLinkDismissesItself() throws {
        let renders = Renders()
        var patch = renders.settled(stack().node)

        XCTAssertTrue(renders.fire(try XCTUnwrap(patch.tapped)))
        patch = renders.settled(stack().node)

        let back = patch.children[1].subtree.first { $0.props["text"] == .string("back") }
        XCTAssertTrue(renders.fire(back?.events?["clicked"] ?? -1))

        let next = renders.settled(stack().node)
        XCTAssertEqual(next.children.count, 1, "the link's page is gone")
    }

    /// A stack over a path holds its routes under the links' pages: popping
    /// into the path truncates it and drops every link, and the pages a link
    /// pushed still stand above the deepest route.
    func testLinkPagesStandAboveAPaths() throws {
        let path = State<[Int]>([1])
        let renders = Renders()

        func tree() -> Node {
            NavigationStack(path.projectedValue) {
                Opener()
            } destination: { depth in
                Level(depth: depth)
            }
            .node
        }

        var patch = renders.settled(tree())
        let popped = try XCTUnwrap(patch.events?["popped"])
        XCTAssertEqual(patch.children.map { $0.id }, [.manual("root"), .manual("0/1")])

        XCTAssertTrue(renders.fire(try XCTUnwrap(patch.tapped)))
        patch = renders.settled(tree())
        XCTAssertEqual(patch.children.map { $0.id },
                       [.manual("root"), .manual("0/1"), .manual("link-0")])

        // A pop that leaves the path stands only where it was.
        XCTAssertTrue(renders.fire(popped, with: [.number(1)]))
        patch = renders.settled(tree())
        XCTAssertEqual(patch.children.map { $0.id }, [.manual("root"), .manual("0/1")])
        XCTAssertEqual(path.wrappedValue, [1])

        // And one under it truncates the path as it always did.
        XCTAssertTrue(renders.fire(popped, with: [.number(0)]))
        patch = renders.settled(tree())
        XCTAssertEqual(patch.children.count, 1)
        XCTAssertEqual(path.wrappedValue, [])
    }
}
