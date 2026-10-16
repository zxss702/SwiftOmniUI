// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// Which elements say how their children animate. A lazy column or grid stands
// its children from native measurement exactly as a stack does, so the timing a
// change arrives under - `withAnimation`, or a query's own - must reach it.

import XCTest

@_spi(Host) @testable import SwiftOmniUICore

final class LazyMotionTests: XCTestCase {
    func testLazyLayoutsPlaceTheirChildren() {
        for contract in [LazyVStackContract.nodeType, LazyHStackContract.nodeType,
                         LazyVGridContract.nodeType, LazyHGridContract.nodeType] {
            XCTAssertTrue(NodeType.places.contains(contract),
                          "\(contract) arranges children from native measurement")
            XCTAssertTrue(NodeType.saysMotion.contains(contract),
                          "\(contract) says how its children animate")
        }
    }

    func testStacksAndGridsStillPlaceTheirChildren() {
        for contract in [VStackContract.nodeType, HStackContract.nodeType,
                         GridContract.nodeType, ZStackContract.nodeType] {
            XCTAssertTrue(NodeType.places.contains(contract))
        }
    }
}
