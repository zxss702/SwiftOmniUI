// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@_spi(Host) @testable import SwiftOmniUICore

private struct PaddedFrameLabel: View {
    var body: some View { Text("card").padding(16) }
}

@MainActor final class FramePaddingTests: XCTestCase {
    func testAFramePreservesItsComposedContentsAndLaterFont() {
        let patch = Renders().render(PaddedFrameLabel().frame(width: 256, height: 256).font(.system(size: 24)).node)
        XCTAssertEqual(patch.props["width"], .number(256))
        XCTAssertEqual(patch.props["height"], .number(256))
        // Padding owns its room, so it wraps the words in a cell of the
        // frame's grid: the wrapper holds the padding, the text the rest.
        let cell = patch.children.first
        XCTAssertEqual(cell?.props["contentPadding"], .numbers([16, 16, 16, 16]))
        XCTAssertEqual(cell?.children.first?.props["text"], .string("card"))
        XCTAssertEqual(cell?.children.first?.props["fontSize"], .number(24))
    }

    func testAFramedControlStillAcceptsItsNativePadding() {
        let node = Button(icon: "test.png").padding(16).frame(width: 40).frame(height: 40)
            .contentPadding(8).onClicked {}.node
        // Each frame owns a wrapper of its own: the height's outside, the
        // width's inside it, and the padding's cell within that - the
        // control the padding and the click fall through to.
        XCTAssertEqual(node.props[.height], .number(40))
        XCTAssertEqual(node.children.first?.props[.width], .number(40))
        let cell = node.children.first?.children.first
        XCTAssertEqual(cell?.props[.contentPadding], .numbers([16, 16, 16, 16]))
        let button = cell?.children.first
        XCTAssertEqual(button?.props[.contentPadding], .numbers([8, 8, 8, 8]))
        XCTAssertNotNil(button?.events[.clicked])
    }

    /// An overlay's layer is marked, so a host knows which child is the
    /// decoration and which the base whose room it shares.
    func testAnOverlayLayerIsMarkedAsDecoration() {
        let patch = Renders().render(Text("base").overlay { Text("over") }.node)
        let layer = patch.subtree.first { $0.props["text"] == .string("over") }
        XCTAssertEqual(layer?.props["isLayoutDecoration"], .bool(true))
    }

    /// A safe-area bar's stack carries the edge it stands on, so the host
    /// knows which side's inset it answers.
    func testASafeAreaInsetCarriesItsEdge() {
        let patch = Renders().render(
            Text("body").safeAreaInset(edge: VerticalEdge.bottom) { Text("bar") }.node)
        XCTAssertEqual(patch.subtree.first {
            $0.props["safeAreaInsetEdge"] != nil }?.props["safeAreaInsetEdge"], .enumeration(4))
    }
}
