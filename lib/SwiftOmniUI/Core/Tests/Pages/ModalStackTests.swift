// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// What is presented over the window, as Swift describes it.
//
// A modal stack is an array the author holds, exactly as a navigation path is,
// and it rides as a list of pages under one wrapper node beside the window's
// own page. The page underneath hands the window its stack as it comes into
// the tree - written once into the window's session, the stack reads the array
// every time the window builds - and what it and the sheets write as they
// arrive is in the message that brings them, which is what `Renders.settled`
// answers. Coming back there is one report, and it says how many are STILL
// presented - the sheet the user dragged down has already gone.
//
import XCTest
@_spi(Host) @testable import SwiftOmniUICore

/// What an application presents over itself. An enum, because the destination
/// is a `switch` and the compiler is what says every case has a page.
private enum Sheet: Hashable {
    case settings
    case about
}

/// The page underneath, which is what presents - and what hands its window the
/// modal stack as it comes into the tree.
private struct HomePage: View {
    @Environment private var page: PageSession
    @Environment private var window: WindowSession
    @Binding var sheets: [Sheet]

    var body: some View {
        Button("Settings")
            .onClicked { sheets.append(.settings) }
            .onAppear {
                page.title = "Home"

                window.modalStack = ModalStack($sheets) { sheet in
                    switch sheet {
                    case .settings: SheetPage(sheets: $sheets, name: "Settings")
                    case .about: SheetPage(sheets: $sheets, name: "About")
                    }
                }
            }
    }
}

/// A presented page. It carries its own way out, because a modal covers the
/// bars as well as the content and there is nothing else to close it with -
/// and it says what it is called as it comes into the tree.
private struct SheetPage: View {
    @Environment private var page: PageSession
    @Binding var sheets: [Sheet]

    let name: String

    var body: some View {
        Button("Close")
            .onClicked { sheets.removeLast() }
            .onAppear {
                page.title = name
            }
    }
}

/// The window under test, over whatever state is lent to it.
private struct TestWindow: WindowScene {
    let sheets: Binding<[Sheet]>

    /// The stack the window shows, for the one test that puts a navigation page
    /// under the sheets. Nil is the plain home page.
    var path: Binding<[Int]>?

    var page: any Page {
        guard let path else { return HomePage(sheets: sheets) }

        return NavigationStack(path) {
            HomePage(sheets: sheets)
        } destination: { _ in
            HomePage(sheets: sheets)
        }
        .title("Diary")
    }
}

/// The window under test, over whatever state is lent to it.
private func window(_ sheets: Binding<[Sheet]>) -> WindowScene {
    TestWindow(sheets: sheets)
}

/// What `sheet(item:)` shows - Identifiable alone, as SwiftUI asks, and
/// deliberately NOT Hashable.
private struct Request: Identifiable {
    let id: Int
    let remote: String
}

/// The page underneath, offering a sheet for whichever request is in force.
private struct RequestHome: View {
    @Binding var request: Request?

    var body: some View {
        Text("Home")
            .sheet(item: $request) { shown in
                Text("Cloning \(shown.remote)")
            }
    }
}

/// The window under test for `sheet(item:)`.
private struct RequestWindow: WindowScene {
    let request: Binding<Request?>

    var page: any Page { RequestHome(request: request) }
}

private func requestWindow(_ request: Binding<Request?>) -> WindowScene {
    RequestWindow(request: request)
}

/// The page underneath for `sheet(isPresented:)` - the same anchor, keyed by
/// a bool.
private struct FlagHome: View {
    @Binding var shown: Bool

    var body: some View {
        Text("Home")
            .sheet(isPresented: $shown) { Text("Sheet") }
    }
}

private struct FlagWindow: WindowScene {
    let shown: Binding<Bool>

    var page: any Page { FlagHome(shown: shown) }
}

@MainActor final class ModalStackTests: XCTestCase {
    // MARK: - What goes out

    /// A window with nothing presented still says so: the list is there and it
    /// is empty, which is what tells the host to dismiss whatever it is still
    /// holding.
    func testAWindowWithNothingPresentedCarriesAnEmptyList() {
        let sheets = State<[Sheet]>([])

        let patch = Renders().settled(window(sheets.projectedValue).node)

        XCTAssertEqual(patch.children.map { $0.type.name }, ["Page", "ModalStack"])
        XCTAssertEqual(patch.children.last?.children.count, 0)
    }

    /// One presented page is one child of the list, and its identity carries
    /// its DEPTH as well as its value - the rule a navigation stack follows,
    /// for the reason a stack has it: two identical sheets are two pages.
    func testAPresentedPageIsAChildOfTheListWearingItsDepth() {
        let sheets = State<[Sheet]>([.settings, .about])

        let list = Renders().settled(window(sheets.projectedValue).node).children.last

        XCTAssertEqual(list?.children.map { $0.id }, [.manual("0/settings"), .manual("1/about")])
        XCTAssertEqual(list?.children.map { $0.props["title"] },
                       [.string("Settings"), .string("About")])
    }

    /// Presenting is appending, and that is the whole of it: the tap on the
    /// page underneath writes the array, and the next render carries a page
    /// that was not there before - the stack was written once, and the window
    /// is what read the array.
    func testPresentingIsAppendingToTheArray() {
        let sheets = State<[Sheet]>([])
        let renders = Renders()

        let first = renders.settled(window(sheets.projectedValue).node)
        let button = first.children.first?.children.first

        XCTAssertTrue(renders.fire(button?.events?["clicked"] ?? -1))
        XCTAssertEqual(sheets.wrappedValue, [.settings])

        let patch = renders.settled(
            window(sheets.projectedValue).node, changed: Renderer.shared.pendingChanges)
        let list = patch.children.first { $0.type == "ModalStack" }

        XCTAssertEqual(list?.children.map { $0.id }, [.manual("0/settings")])
    }

    /// And closing is the array getting shorter. The button is on the SHEET,
    /// which is where it has to be: a modal covers the bar the page underneath
    /// would have offered.
    func testClosingIsTheArrayGettingShorter() {
        let sheets = State<[Sheet]>([.settings])
        let renders = Renders()

        let first = renders.settled(window(sheets.projectedValue).node)
        let close = first.children.first { $0.type == "ModalStack" }?
            .children.first?.children.first

        XCTAssertTrue(renders.fire(close?.events?["clicked"] ?? -1))
        XCTAssertEqual(sheets.wrappedValue, [])

        let patch = renders.settled(
            window(sheets.projectedValue).node, changed: Renderer.shared.pendingChanges)

        XCTAssertEqual(patch.children.first { $0.type == "ModalStack" }?.children.count, 0)
    }

    // MARK: - What comes back

    /// A native dismissal reports what survived, and the array is truncated to
    /// that depth.
    func testADismissalTruncatesTheArray() {
        let sheets = State<[Sheet]>([.settings])
        let renders = Renders()

        let patch = renders.settled(window(sheets.projectedValue).node)

        XCTAssertTrue(renders.fire(patch.events?["modalPopped"] ?? -1, with: [.number(0)]))
        XCTAssertEqual(sheets.wrappedValue, [])
    }

    /// Only the top one went: a report of one surviving over a stack of two
    /// leaves the first sheet presented.
    func testADismissalOfTheTopLeavesWhatIsUnderIt() {
        let sheets = State<[Sheet]>([.settings, .about])
        let renders = Renders()

        let patch = renders.settled(window(sheets.projectedValue).node)

        XCTAssertTrue(renders.fire(patch.events?["modalPopped"] ?? -1, with: [.number(1)]))
        XCTAssertEqual(sheets.wrappedValue, [.settings])
    }

    /// A report that would LENGTHEN the array is refused - it has been
    /// overtaken by something this side already did, and obeying it would put a
    /// dismissed sheet back on the screen.
    func testAReportThatWouldPresentSomethingAgainIsRefused() {
        let sheets = State<[Sheet]>([])
        let renders = Renders()

        let patch = renders.settled(window(sheets.projectedValue).node)

        XCTAssertTrue(renders.fire(patch.events?["modalPopped"] ?? -1, with: [.number(2)]))
        XCTAssertEqual(sheets.wrappedValue, [])
    }

    /// A payload of the wrong shape leaves the array alone.
    func testAValueOfTheWrongKindLeavesTheArrayAlone() {
        let sheets = State<[Sheet]>([.settings])
        let renders = Renders()

        let patch = renders.settled(window(sheets.projectedValue).node)

        XCTAssertTrue(renders.fire(patch.events?["modalPopped"] ?? -1, with: [.string("0")]))
        XCTAssertEqual(sheets.wrappedValue, [.settings])
    }

    // MARK: - What `sheet(item:)` asks of an item

    /// An item is its `id`: `sheet(item:)` asks Identifiable and no more, so a
    /// request that is not Hashable presents as well as one that is.
    func testAnIdentifiableOnlyItemPresentsItsPage() {
        let request = State<Request?>(nil)
        let renders = Renders()

        _ = renders.settled(requestWindow(request.projectedValue).node)
        request.wrappedValue = Request(id: 7, remote: "git@example.test")

        let patch = renders.settled(
            requestWindow(request.projectedValue).node,
            changed: Renderer.shared.pendingChanges)
        let modal = patch.children.first { $0.type == "ModalStack" }

        XCTAssertEqual(modal?.children.map(\.id), [.manual("0/7")])
    }

    /// Swapping to another item under the one presentation replaces the page,
    /// which still stands at depth 0.
    func testAnotherItemSwapsThePageThePresentationShows() {
        let request = State<Request?>(Request(id: 7, remote: "a"))
        let renders = Renders()

        _ = renders.settled(requestWindow(request.projectedValue).node)
        request.wrappedValue = Request(id: 9, remote: "b")

        let patch = renders.settled(
            requestWindow(request.projectedValue).node,
            changed: Renderer.shared.pendingChanges)
        let modal = patch.children.first { $0.type == "ModalStack" }

        XCTAssertEqual(modal?.children.map(\.id), [.manual("0/9")])
    }

    /// The bool twin of the item sheet presents the same way - the one modal
    /// stack the window can hold.
    func testAPresentedFlagShowsItsSheet() {
        let shown = State<Bool>(true)

        let patch = Renders().settled(FlagWindow(shown: shown.projectedValue).node)
        let modal = patch.children.first { $0.type == "ModalStack" }

        XCTAssertEqual(modal?.children.count, 1)
    }

    /// A native dismissal writes `nil` back to the binding, and the modal
    /// leaves with it.
    func testADismissalWritesTheItemAway() {
        let request = State<Request?>(Request(id: 7, remote: "a"))
        let renders = Renders()

        let patch = renders.settled(requestWindow(request.projectedValue).node)

        XCTAssertTrue(renders.fire(patch.events?["modalPopped"] ?? -1, with: [.number(0)]))

        // The report truncated the anchor's tickets; the walk that follows
        // runs the watch which writes the item away.
        _ = renders.settled(
            requestWindow(request.projectedValue).node,
            changed: Renderer.shared.pendingChanges)
        XCTAssertNil(request.wrappedValue)
    }

    // MARK: - The contract a host reads

    /// The whole thing: a window whose page is a navigation stack, with two
    /// pages presented over all of it - as the message that brings them
    /// carries them, each page of the stack having handed the window the same
    /// modal stack on its way in, so there is one.
    func testTwoPagesArePresentedOverTheWholeWindow() throws {
        let sheets = State<[Sheet]>([.settings, .about])
        let path = State<[Int]>([1])

        let window = Renders().settled(
            TestWindow(sheets: sheets.projectedValue, path: path.projectedValue).node)

        XCTAssertEqual(window.children.map(\.type), [.navigationStack, .modalStack])
        XCTAssertEqual(window.eventNames, (HostPatch.windowEvents + ["modalPopped"]).sorted())
        XCTAssertEqual(window.at(.auto(2))?.arrangement, [.manual("root"), .manual("0/1")])

        let modal = try XCTUnwrap(window.at(.auto(5)))
        XCTAssertEqual(modal.arrangement, [.manual("0/settings"), .manual("1/about")])
        XCTAssertEqual(modal.children.map { $0.props["title"] }, [.string("Settings"), .string("About")])
        XCTAssertTrue(modal.children.allSatisfy { $0.eventNames == HostPatch.pageEvents })
    }
}
