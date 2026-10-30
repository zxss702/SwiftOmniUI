// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// `.onAppear` and `.onDisappear`: what runs as an element comes into the
// tree and as it leaves - its lifetime in the TREE, which the differ knows and
// no platform has to report.

import XCTest
@_spi(Host) @testable import SwiftOmniUICore

/// A view that says when it comes and goes, into a log it is lent.
private struct Coming: View {
    @Binding var log: [String]
    let name: String

    var body: some View {
        Text(name)
            .onAppear { log.append("created \(name)") }
            .onDisappear { log.append("destroying \(name)") }
    }
}

/// A view holding another, both saying when they come and go.
private struct Holding: View {
    @Binding var log: [String]

    var body: some View {
        VStack {
            Coming(log: $log, name: "inner")
        }
        .onAppear { log.append("created outer") }
        .onDisappear { log.append("destroying outer") }
    }
}

/// A view whose own state is changed while it stands and read as it leaves.
private struct Drafting: View {
    @Binding var log: [String]
    @State private var draft = "typed"

    var body: some View {
        Button(draft)
            .onClicked { draft = "edited" }
            .onDisappear { log.append("saved \(draft)") }
    }
}

/// Different pages can have the same native root. Their composed view types,
/// rather than the root widget type, delimit their lifetimes.
private struct FolderLifetimePage: View {
    @Binding var log: [String]
    @State private var didLoad = false

    var body: some View {
        VStack { Text("Folders") }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                log.append("load folders")
            }
            .onDisappear { log.append("leave folders") }
    }
}

private struct SearchLifetimePage: View {
    @Binding var log: [String]

    var body: some View {
        VStack { Text("Search") }
            .onAppear { log.append("enter search") }
            .onDisappear { log.append("leave search") }
    }
}

private struct SidebarLifetimeSwitch: View {
    @Binding var showsFolders: Bool
    @Binding var log: [String]

    var body: some View {
        VStack {
            Group {
                if showsFolders {
                    FolderLifetimePage(log: $log)
                } else {
                    SearchLifetimePage(log: $log)
                }
            }
            .transition(.opacity)
        }
    }
}

@MainActor final class LifetimeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Renderer.shared.clearInvalidation()
    }

    /// An element runs `.onAppear` ONCE, after the render that brings it into
    /// the tree - and a render that describes it again runs nothing.
    func testAnElementRunsOnCreatedOnceAsItComesIntoTheTree() {
        let log = State(wrappedValue: [String]())
        let renders = Renders()
        let tree = { VStack { Coming(log: log.projectedValue, name: "a") }.node }

        renders.render(tree())
        XCTAssertEqual(log.wrappedValue, ["created a"])

        renders.render(tree(), changed: Renderer.shared.pendingChanges)
        renders.renderFromScratch(tree())
        XCTAssertEqual(log.wrappedValue, ["created a"])
    }

    /// An element runs `.onDisappear` once, after the first render that no
    /// longer describes it.
    func testAnElementRunsOnDestroyingAsItLeaves() {
        let log = State(wrappedValue: [String]())
        let shown = State(wrappedValue: true)
        let renders = Renders()
        let tree = {
            VStack {
                if shown.wrappedValue {
                    Coming(log: log.projectedValue, name: "a")
                }
            }.node
        }

        renders.render(tree())
        shown.wrappedValue = false
        renders.render(tree(), changed: Renderer.shared.pendingChanges)

        XCTAssertEqual(log.wrappedValue, ["created a", "destroying a"])
    }

    /// An element comes in before what is under it, and leaves after it - the
    /// innermost first.
    func testWhatIsUnderAnElementLeavesBeforeIt() {
        let log = State(wrappedValue: [String]())
        let shown = State(wrappedValue: true)
        let renders = Renders()
        let tree = {
            VStack {
                if shown.wrappedValue {
                    Holding(log: log.projectedValue)
                }
            }.node
        }

        renders.render(tree())
        shown.wrappedValue = false
        renders.render(tree(), changed: Renderer.shared.pendingChanges)

        XCTAssertEqual(log.wrappedValue, [
            "created outer", "created inner", "destroying inner", "destroying outer",
        ])
    }

    /// As it leaves, an element's `@State` still answers - holding what it was
    /// last written, not what it started with, which is what saving needs.
    func testAnElementsStateAnswersAsItLeaves() throws {
        let log = State(wrappedValue: [String]())
        let shown = State(wrappedValue: true)
        let renders = Renders()
        let tree = {
            VStack {
                if shown.wrappedValue {
                    Drafting(log: log.projectedValue)
                }
            }.node
        }

        let first = renders.render(tree())
        XCTAssertTrue(renders.fire(try XCTUnwrap(Self.clicked(in: first))))
        renders.render(tree(), changed: Renderer.shared.pendingChanges)

        shown.wrappedValue = false
        renders.render(tree(), changed: Renderer.shared.pendingChanges)

        XCTAssertEqual(log.wrappedValue, ["saved edited"])
    }

    /// The first clicked handler under a patch.
    private static func clicked(in patch: HostPatch) -> Int? {
        patch.events?[.clicked] ?? patch.children.lazy.compactMap { clicked(in: $0) }.first
    }

    /// A new identity is a new element: the one standing goes and the new one
    /// comes - and the one leaving says so first, so what it saves is there
    /// for the one arriving to read.
    func testANewIdentityIsANewElement() {
        let log = State(wrappedValue: [String]())
        let identity = State(wrappedValue: 1)
        let renders = Renders()
        let tree = {
            VStack {
                Coming(log: log.projectedValue, name: "\(identity.wrappedValue)")
                    .id(identity.wrappedValue)
            }.node
        }

        renders.render(tree())
        identity.wrappedValue = 2
        renders.render(tree(), changed: Renderer.shared.pendingChanges)

        XCTAssertEqual(log.wrappedValue, ["created 1", "destroying 1", "created 2"])
    }

    func testChangingComposedPageWithSameNativeRootStartsANewLifetime() {
        let log = State(wrappedValue: [String]())
        let renders = Renders()

        renders.render(AnyView(FolderLifetimePage(log: log.projectedValue)).node)
        renders.render(AnyView(SearchLifetimePage(log: log.projectedValue)).node)
        renders.render(AnyView(FolderLifetimePage(log: log.projectedValue)).node)

        XCTAssertEqual(log.wrappedValue, [
            "load folders", "leave folders", "enter search",
            "leave search", "load folders",
        ])
    }

    func testSidebarBranchReentryLoadsFreshStateWithTransition() {
        let log = State(wrappedValue: [String]())
        let showsFolders = State(wrappedValue: true)
        let renders = Renders()

        func page() -> Node {
            SidebarLifetimeSwitch(
                showsFolders: showsFolders.projectedValue,
                log: log.projectedValue
            ).node
        }

        renders.render(page())
        showsFolders.wrappedValue = false
        renders.render(page(), changed: Renderer.shared.pendingChanges)
        showsFolders.wrappedValue = true
        renders.render(page(), changed: Renderer.shared.pendingChanges)

        XCTAssertEqual(log.wrappedValue, [
            "load folders", "leave folders", "enter search",
            "leave search", "load folders",
        ])
    }

    /// What is written ON a composed view runs as well as what its body
    /// writes, the body's first.
    func testWhatIsWrittenOnAComposedViewRunsToo() {
        let log = State(wrappedValue: [String]())
        let renders = Renders()

        renders.render(VStack {
            Coming(log: log.projectedValue, name: "a")
                .onAppear { log.wrappedValue.append("written on it") }
        }.node)

        XCTAssertEqual(log.wrappedValue, ["created a", "written on it"])
    }

    /// A page the library builds runs them too.
    func testAPageRunsThemToo() {
        let log = State(wrappedValue: [String]())
        let path = State(wrappedValue: [Int]())
        let renders = Renders()

        renders.render(
            NavigationStack(path.projectedValue) {
                LifetimePage()
            } destination: { _ in
                LifetimePage()
            }
            .onAppear { log.wrappedValue.append("created stack") }
            .node)

        XCTAssertEqual(log.wrappedValue, ["created stack"])
    }

    // MARK: - In the message that brings it

    /// What `.onAppear` writes is in the message that brings the element -
    /// a window's title given by its page as it comes in reaches the host
    /// with the window, not a render after it.
    func testWhatOnCreatedWritesIsInTheMessageThatBringsTheElement() throws {
        Scenes.shared.reset()
        defer { Scenes.shared.reset() }
        Renderer.shared.setApplication(Titling())

        let first = Renderer.shared.renderHost(baseline: 0)
        let window = try XCTUnwrap(first.root.children.first?.children.first)

        XCTAssertEqual(window.type, .windowScene)
        XCTAssertEqual(
            window.props["title"], .string("Titled"),
            "the title the page wrote as it came in waited for a render of its own")
        XCTAssertFalse(
            Renderer.shared.needsRender,
            "what the handler wrote was sent, and nothing is left to render")
    }

    /// A chain of handlers - each render's write firing the next - is walked
    /// into the message a few times and no more; what is left runs after it,
    /// and nothing is lost.
    func testAChainLongerThanTheSettlingPassesGoesOnAfterTheMessage() throws {
        Scenes.shared.reset()
        defer { Scenes.shared.reset() }
        Renderer.shared.setApplication(Chaining())

        let first = Renderer.shared.renderHost(baseline: 0)

        XCTAssertEqual(
            labels(in: first.root), ["\(Renderer.settleLimit)"],
            "each settling pass walks one step of the chain into the message")

        turnTheUIThread()

        XCTAssertTrue(
            Renderer.shared.needsRender,
            "the step there was no pass left for ran after the message, and asks for the next")
    }

    /// Every label's text under a node, depth first.
    private func labels(in patch: HostPatch) -> [String] {
        var own: [String] = []

        if patch.type == .text, case .string(let text)? = patch.props[.text] {
            own.append(text)
        }

        return own + patch.children.flatMap { labels(in: $0) }
    }
}

/// An application whose page gives its window a title as it comes in.
private struct Titling: App {
    var body: some Scene { TitlingWindow() }
}

/// The window the page names.
private struct TitlingWindow: WindowScene {
    var page: any Page { TitlingPage() }
}

/// A page that names the window it is in as it comes into the tree.
private struct TitlingPage: View {
    @Environment private var window: WindowSession

    var body: some View {
        Text("hello").onAppear { window.title = "Titled" }
    }
}

/// An application whose page counts itself up, one step per render, for ever.
private struct Chaining: App {
    var body: some Scene { ChainingWindow() }
}

/// The window the counting page is in.
private struct ChainingWindow: WindowScene {
    var page: any Page { ChainingPage() }
}

/// A page whose count moves every time it is seen to have moved.
private struct ChainingPage: View {
    @State private var count = 0

    var body: some View {
        Text("\(count)")
            .onAppear { count += 1 }
            .onChange(of: count) { count += 1 }
    }
}

/// A page with nothing on it, for a stack to hold.
private struct LifetimePage: View {
    var body: some View { Text("page") }
}
