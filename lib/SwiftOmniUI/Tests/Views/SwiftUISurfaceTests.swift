// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The SwiftUI-surface additions that compose on what the library already
// knows: `Font.default`, `UnevenRoundedRectangle`, `ContentUnavailableView`,
// `defaultFocus`, `geometryGroup`, the `urlOpened` application event a host
// raises for `.onOpenURL`, and a window scene's `defaultPosition`.

import XCTest
@_spi(Host) @testable import SwiftOmniUICore

private struct MainWindow: WindowScene {
    var page: any Page { ModifiedContent(node: label("main")) }
}

@MainActor final class SwiftUISurfaceTests: XCTestCase {
    /// Touches the shared renderer, whose init installs the UI thread's
    /// executor before any task of this suite can be made - see UIThread.swift.
    override func setUp() {
        super.setUp()
        Renderer.shared.clearInvalidation()
    }

    // MARK: - Font.default

    /// `Font.default` reads as ordinary body text, as SwiftUI's does.
    func testFontDefaultIsTheBodyTextStyle() {
        XCTAssertEqual(Font.default, .body)
    }

    // MARK: - UnevenRoundedRectangle

    /// Each corner's radius crosses in its own place - leading and trailing
    /// by the platform's language direction, which here is left to right.
    func testUnevenRoundedRectangleCarriesEachCornersRadius() {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 8, bottomLeadingRadius: 0, bottomTrailingRadius: 4, topTrailingRadius: 2,
            style: .continuous)

        XCTAssertEqual(shape.node.type, "Rectangle")
        XCTAssertEqual(
            shape.node.props[RectangleContract.cornerRadius.token],
            CornerRadius.corners(topLeft: 8, topRight: 2, bottomLeft: 0, bottomRight: 4).propValue)
    }

    /// A `RectangleCornerRadii` names the same four corners.
    func testRectangleCornerRadiiNamesAllFourCorners() {
        let radii = RectangleCornerRadii(topLeading: 1, topTrailing: 2, bottomLeading: 3, bottomTrailing: 4)
        let shape = UnevenRoundedRectangle(cornerRadii: radii, style: .continuous)

        XCTAssertEqual(shape.cornerRadii, radii)
        XCTAssertEqual(
            shape.node.props[RectangleContract.cornerRadius.token],
            CornerRadius.corners(topLeft: 1, topRight: 2, bottomLeft: 3, bottomRight: 4).propValue)
    }

    // MARK: - ContentUnavailableView

    /// A label, a description and the actions stand in a column.
    func testContentUnavailableViewBuildsItsParts() throws {
        var node = ContentUnavailableView(
            "No Results", systemImage: "magnifyingglass", description: "Try again"
        ).body.node
        node.materialize()

        var texts: [String] = []
        walkTexts(in: node, into: &texts)
        XCTAssertTrue(texts.contains { $0.contains("No Results") })
        XCTAssertTrue(texts.contains { $0.contains("Try again") })
    }

    /// Collects every `Text` node's words, depth first.
    private func walkTexts(in node: Node, into texts: inout [String]) {
        if node.type == "Text", let words = node.props[TextElementContract.text.token]?.string {
            texts.append(words)
        }
        for child in node.children {
            var child = child
            child.materialize()
            walkTexts(in: child, into: &texts)
        }
    }

    // MARK: - defaultFocus

    /// `defaultFocus` asks for the focus when the element stands - an
    /// `onAppear` written on the node.
    func testDefaultFocusAsksWhenTheElementStands() {
        let binding = Binding<Bool>(get: { false }, set: { _ in })

        let node = Text("field")
            .defaultFocus(binding, true)
            .node

        XCTAssertFalse(node.created.isEmpty, "the default-focus ask stands on the element's creation")
    }

    // MARK: - geometryGroup

    /// `geometryGroup` adds nothing - the space is already one.
    func testGeometryGroupLeavesTheNodeAlone() {
        let plain = Text("words").node
        let grouped = Text("words").geometryGroup().node

        XCTAssertEqual(grouped.type, plain.type)
        XCTAssertEqual(grouped.props.count, plain.props.count)
        XCTAssertEqual(grouped.events.count, plain.events.count)
    }

    // MARK: - urlOpened

    /// A view hears the application's URL-opened event - the road
    /// `.onOpenURL` rides, built where Foundation's `URL` may stand.
    func testURLOpenedIsHeardThroughHearing() async throws {
        var heard: String?
        let node = Text("page").hearing(AppContract.urlOpened) { text in
            heard = text
        }.node

        let handler = try XCTUnwrap(node.events[.urlOpened])
        EventBuffer.current = MemberValues.encode("file:///tmp/place")
        defer { EventBuffer.current = [] }
        try await handler()

        XCTAssertEqual(heard, "file:///tmp/place")
    }

    // MARK: - defaultPosition

    /// `.defaultPosition` writes the anchor on the group.
    func testDefaultPositionWritesTheAnchor() {
        let group = WindowGroup(WindowType("main")) { MainWindow() }
            .defaultPosition(.center)

        XCTAssertEqual(group.defaultPosition, .center)
    }

    /// The fractions spelling writes the same anchor.
    func testDefaultPositionByFractions() {
        let group = WindowGroup(WindowType("main")) { MainWindow() }
            .defaultPosition(x: 0.25, y: 0.75)

        XCTAssertEqual(group.defaultPosition, UnitPoint(x: 0.25, y: 0.75))
    }

    // MARK: - WindowPlacement

    /// A `WindowPlacement` pairs an anchor with a size - the presets naming
    /// anchors, a `.zero` size asking nothing of it.
    func testWindowPlacementPairsAnAnchorWithASize() {
        let placement = WindowPlacement(position: .topLeading, size: Size(400, 300))

        XCTAssertEqual(placement.position, .topLeading)
        XCTAssertEqual(placement.size, Size(400, 300))
        XCTAssertEqual(WindowPlacement.center, WindowPlacement(position: .center))
        XCTAssertEqual(WindowPlacement.topLeading.position, .topLeading)
        XCTAssertNil(WindowPlacement.topLeading.extent)
    }

    /// `.automatic` asks nothing - its place and size come out nil, and it
    /// is not the centered placement it would otherwise read as.
    func testAutomaticPlacementAsksNothing() {
        XCTAssertNil(WindowPlacement.automatic.anchor)
        XCTAssertNil(WindowPlacement.automatic.extent)
        XCTAssertNotEqual(WindowPlacement.automatic, .center)
    }

    // MARK: - defaultPlacement

    /// `.defaultPlacement` writes both halves of the ask on the group.
    func testDefaultPlacementWritesAnchorAndSize() {
        let group = WindowGroup(WindowType("main")) { MainWindow() }
            .defaultPlacement(WindowPlacement(position: .topTrailing, size: Size(320, 480)))

        XCTAssertEqual(group.defaultPosition, .topTrailing)
        XCTAssertEqual(group.defaultSize?.width, 320)
        XCTAssertEqual(group.defaultSize?.height, 480)
    }

    /// A placement with nothing to ask of the size places without sizing,
    /// and `.automatic` takes earlier asks back.
    func testDefaultPlacementLeavesUnsaidAlone() {
        let placed = WindowGroup(WindowType("main")) { MainWindow() }
            .defaultPlacement(.topLeading)

        XCTAssertEqual(placed.defaultPosition, .topLeading)
        XCTAssertNil(placed.defaultSize)

        let automatic = WindowGroup(WindowType("main")) { MainWindow() }
            .defaultSize(width: 200, height: 100)
            .defaultPlacement(.automatic)

        XCTAssertNil(automatic.defaultPosition)
        XCTAssertNil(automatic.defaultSize)
    }

    // MARK: - A scene's placement

    /// `.defaultPosition` and `.defaultSize` on `Windows` are the scene's
    /// ask for its main window, and each group's default.
    func testWindowsCarryTheScenesPlacement() {
        let windows = Windows(main: { MainWindow() })
            .defaultPosition(.topLeading)
            .defaultSize(width: 640, height: 400)

        XCTAssertEqual(windows.defaultPosition, .topLeading)
        XCTAssertEqual(windows.defaultSize?.width, 640)
        XCTAssertEqual(windows.defaultSize?.height, 400)
    }

    /// `.defaultPlacement` writes the same two asks on `Windows`.
    func testWindowsDefaultPlacementWritesAnchorAndSize() {
        let windows = Windows(main: { MainWindow() })
            .defaultPlacement(WindowPlacement(position: .bottomTrailing, size: Size(480, 320)))

        XCTAssertEqual(windows.defaultPosition, .bottomTrailing)
        XCTAssertEqual(windows.defaultSize?.width, 480)
        XCTAssertEqual(windows.defaultSize?.height, 320)
    }
}
