// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) @testable import SwiftOmniUICore
@_spi(Host) @testable import SwiftOmniUIHost
import XCTest

/// Where a page's content stands against the window's safe area.
final class SafeAreaTests: XCTestCase {
    private let whole = Rect(x: 0, y: 0, width: 400, height: 800)
    private let safe = Rect(x: 0, y: 60, width: 400, height: 710)

    func testAColumnRebasesItsEdgeContributionsWithoutClippingANewProposalToOldBounds() {
        let window = SafeAreaContext(
            bounds: Rect(0, -48, 800, 648), layout: Rect(0, 0, 800, 600),
            container: Rect(0, 0, 800, 600), consumed: EdgeInsets(3))
        let column = window.child(in: Rect(256, 0, 544, 600))
        for proposal in [Rect(0, 0, 900, 1800), Rect(0, 0, 80, 30), Rect(0, 0, 544, 600)] {
            let context = column.resizedLayout(to: proposal)
            XCTAssertEqual(context.safe, proposal)
            XCTAssertEqual(context.bounds, Rect(0, -48, proposal.width, proposal.height + 48))
            XCTAssertEqual(context.insets, EdgeInsets(top: 48, leading: 0, bottom: 0, trailing: 0))
            XCTAssertEqual(context.consumed, window.consumed)
            XCTAssertEqual(context.resizedLayout(to: column.layout), column)
        }
    }

    /// Content that says nothing, or stands clear of the bars, stands in the safe area; content let under the bars
    /// reaches the window's edge on every edge it says so.
    func testContentReachesTheWindowsEdgeWhereItLetsItselfUnderTheBars() {
        XCTAssertEqual(SafeAreaArithmetic.room(safe: safe, whole: whole, edges: nil), safe)
        XCTAssertEqual(SafeAreaArithmetic.room(safe: safe, whole: whole, edges: .uniform(.container)), safe)
        XCTAssertEqual(SafeAreaArithmetic.room(safe: safe, whole: whole, edges: .uniform(.all)), safe)
        XCTAssertEqual(SafeAreaArithmetic.room(safe: safe, whole: whole, edges: .uniform(.none)), whole)
        XCTAssertEqual(SafeAreaArithmetic.room(safe: safe, whole: whole, edges: .uniform(.keyboard)), whole)
        XCTAssertEqual(
            SafeAreaArithmetic.room(
                safe: safe, whole: whole, edges: .edges(left: .container, top: .none, right: .container, bottom: .all)),
            Rect(x: 0, y: 0, width: 400, height: 770), "under the top bar alone")
    }
}
