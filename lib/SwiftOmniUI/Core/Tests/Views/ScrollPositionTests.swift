// SPDX-FileCopyrightText: 2026 Pawe? Krzywdzi?ski and Contributors
// SPDX-License-Identifier: Apache-2.0

import Foundation
@_spi(Host) @testable import SwiftOmniUICore
import XCTest

final class ScrollPositionTests: XCTestCase {
    func testPublicConstructorsAndTypedIdentity() {
        let empty = ScrollPosition()
        XCTAssertNil(empty.edge)
        XCTAssertNil(empty.point)
        XCTAssertFalse(empty.isPositionedByUser)
        let id = UUID()
        var position = ScrollPosition(idType: UUID.self)
        position.scrollTo(id: id, anchor: .center)
        XCTAssertEqual(position.viewID(type: UUID.self), id)
        XCTAssertNil(position.viewID(type: String.self))
        position.scrollTo(edge: .bottom)
        XCTAssertEqual(position.edge, .bottom)
        XCTAssertNil(position.viewID)
        let previous = position
        position.scrollTo(edge: .bottom)
        XCTAssertNotEqual(position, previous, "a repeated command must reach the new content extent")
    }

    func testPointAndSingleAxisRequestsReplaceThePreviousDestination() {
        var position = ScrollPosition(idType: String.self, point: CGPoint(x: 20, y: 30))
        XCTAssertEqual(position.point, CGPoint(x: 20, y: 30))
        position.scrollTo(x: 50)
        XCTAssertEqual(position.x, 50)
        XCTAssertNil(position.y)
        XCTAssertNil(position.point)
        position.scrollTo(y: 80)
        XCTAssertNil(position.x)
        XCTAssertEqual(position.y, 80)
        position.scrollTo(x: 10, y: 90)
        XCTAssertEqual(position.point, CGPoint(x: 10, y: 90))
        position.scrollTo(id: "row")
        XCTAssertNil(position.point)
        XCTAssertEqual(position.viewID(type: String.self), "row")
    }

    @MainActor
    func testScrollGeometryComputesBoundsVisibleRectAndAttachesHandler() {
        var insets = EdgeInsets(0)
        insets.top = 10
        insets.left = 8
        insets.bottom = 12
        insets.right = 4
        let geometry = ScrollGeometry(
            contentOffset: CGPoint(x: 20, y: 30),
            contentSize: CGSize(width: 400, height: 600),
            contentInsets: insets,
            containerSize: CGSize(width: 240, height: 180)
        )
        XCTAssertEqual(geometry.visibleRect, CGRect(x: 20, y: 30, width: 240, height: 180))
        XCTAssertEqual(geometry.bounds, CGRect(x: -8, y: -10, width: 412, height: 622))

        let view = ScrollView(.horizontal) { Text("item") }
            .onScrollGeometryChange(for: Double.self) { $0.containerSize.width } action: { _, _ in }
        XCTAssertNotNil(view.node.events[ScrollViewContract.scrollGeometryChanged.token])
    }
}

