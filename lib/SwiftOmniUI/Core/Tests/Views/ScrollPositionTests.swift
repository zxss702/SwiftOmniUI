// SPDX-FileCopyrightText: 2026 Pawe? Krzywdzi?ski and Contributors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SwiftOmniUICore
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
}

