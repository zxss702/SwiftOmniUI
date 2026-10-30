// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The cut and the hit outline a view is wrapped for.
//
// `.clipShape` wraps the view in a layout carrying `shape` and
// `clipsContent`; `.clipped` is the same by the bounds' own rectangle.
// `.contentShape` wraps the same way carrying `hitShape`, which the host's
// hit test honours.

import XCTest
@_spi(Host) @testable import SwiftOmniUICore

@MainActor final class ClipShapeTests: XCTestCase {
    /// The layout the view was wrapped in: the clip and the hit outline stand
    /// on a `ZStack`, so the whole room the view was given is what they name.
    private func wrapper(of content: ModifiedContent) -> Node {
        content.node
    }

    func testAClipShapeWrapsWithItsOutlineAndTheClip() throws {
        let wrapper = wrapper(of: Text("avatar").clipShape(Circle()))

        XCTAssertEqual(wrapper.type, .zStack)
        XCTAssertEqual(wrapper.props[.shape], ContainerShape.circle.propValue)
        XCTAssertEqual(wrapper.props[.clipsContent], .bool(true))
    }

    func testClippedIsTheClipByTheBoundsRectangle() throws {
        let wrapper = wrapper(of: Text("…").clipped())

        XCTAssertEqual(wrapper.props[.shape], ContainerShape.rectangle.propValue)
        XCTAssertEqual(wrapper.props[.clipsContent], .bool(true))
    }

    func testAContentShapeWrapsWithTheHitOutline() throws {
        let wrapper = wrapper(of: Text("dot").contentShape(Circle()))

        XCTAssertEqual(wrapper.type, .zStack)
        XCTAssertEqual(wrapper.props[.hitShape], ContainerShape.circle.propValue)
        XCTAssertNil(wrapper.props[.clipsContent], "a hit outline clips nothing drawn")
    }

    func testTheRoundedShapesStandForTheirOutlines() throws {
        XCTAssertEqual(RoundedRectangle(cornerRadius: 8).outline, .roundedRectangle(8))
        XCTAssertEqual(RoundedRectangle(cornerRadius: 8, style: .continuous).outline, .roundedRectangle(8))
        XCTAssertEqual(Capsule().outline, .capsule)
        XCTAssertEqual(Capsule(style: .continuous).outline, .capsule)
        XCTAssertEqual(Circle().outline, .circle)
    }

    /// The member modifier a wrapped layout can be handed directly.
    func testTheHitShapeMemberWritesItsOutline() throws {
        let stack = ZStack { Text("dot") }.hitShape(.capsule)

        XCTAssertEqual(stack.node.props[.hitShape], ContainerShape.capsule.propValue)
    }

    /// Where a line that will not fit is cut, said the SwiftUI way.
    func testTruncationModeWritesTheCutItNames() throws {
        XCTAssertEqual(
            Text("/very/long/path").truncationMode(.middle).node.props[.lineBreak],
            LineBreak.middleTruncation.propValue)
        XCTAssertEqual(
            Text("…").truncationMode(.head).node.props[.lineBreak],
            LineBreak.headTruncation.propValue)
        XCTAssertEqual(
            Text("…").truncationMode(.tail).node.props[.lineBreak],
            LineBreak.tailTruncation.propValue)
    }
}
