// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@_spi(Host) @testable import SwiftOmniUICore

@MainActor final class MaskTests: XCTestCase {
    func testBuilderMaskKeepsAllLayersInTheAlphaRole() throws {
        let patch = Renders().render(Rectangle().fill(.red).mask {
            Path(Rect(5, 5, 25, 25)).fill(.black)
            Path(Rect(70, 30, 20, 20)).fill(.white)
        }.node)
        XCTAssertEqual(patch.type, MaskedContract.nodeType)
        let roles = patch.children.map { $0 }
        XCTAssertEqual(roles.count, 2)
        let source = try XCTUnwrap(roles.first), alpha = try XCTUnwrap(roles.last)
        XCTAssertEqual(source.type, ZStackContract.nodeType)
        XCTAssertEqual(alpha.type, ZStackContract.nodeType)
        XCTAssertEqual(source.subtree.filter { $0.type == RectangleContract.nodeType }.count, 1)
        XCTAssertFalse(source.subtree.contains { $0.type == PathContract.nodeType })
        XCTAssertEqual(alpha.subtree.filter { $0.type == PathContract.nodeType }.count, 2)
        XCTAssertFalse(alpha.subtree.contains { $0.type == RectangleContract.nodeType })
    }

    func testComposedContentCannotBeMistakenForAMaskLayer() throws {
        let patch = Renders().render(Group {
            Text("First")
            Text("Second")
        }.mask { Circle().fill(.black) }.node)
        let roles = patch.children.map { $0 }
        XCTAssertEqual(roles.count, 2)
        let source = try XCTUnwrap(roles.first), alpha = try XCTUnwrap(roles.last)
        XCTAssertEqual(source.subtree.filter { $0.type == TextContract.nodeType }.count, 2)
        XCTAssertFalse(alpha.subtree.contains { $0.type == TextContract.nodeType })
        XCTAssertEqual(alpha.subtree.filter { $0.type == EllipseContract.nodeType }.count, 1)
    }

    func testEmptyMaskStillHasAnAlphaBoundary() throws {
        let patch = Renders().render(Rectangle().fill(.red).mask { EmptyView() }.node)
        XCTAssertEqual(patch.type, MaskedContract.nodeType)
        let roles = patch.children.map { $0 }
        XCTAssertEqual(roles.count, 2)
        let alpha = try XCTUnwrap(roles.last)
        XCTAssertEqual(alpha.type, ZStackContract.nodeType)
        XCTAssertTrue(alpha.children.isEmpty, "an empty alpha source hides content instead of removing its mask")
        XCTAssertEqual(roles.first?.subtree.filter { $0.type == RectangleContract.nodeType }.count, 1)
    }
}
