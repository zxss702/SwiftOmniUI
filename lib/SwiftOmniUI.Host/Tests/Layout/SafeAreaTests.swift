// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) @testable import SwiftOmniUICore
@_spi(Host) @testable import SwiftOmniUIHost
import XCTest

/// Where a page's content stands against the window's safe area.
final class SafeAreaTests: XCTestCase {
    func testSafeBarScrollerUsesItsContentForThicknessWithoutChangingOrdinaryViewports() {
        var viewport = LayoutValues()
        viewport.scrollAxes = .vertical
        let content = LayoutSize(width: 380, height: 72)
        XCTAssertEqual(viewport.sized(content, offered: 380).height, 72)
        viewport.safeBarSizingAxes = .vertical
        viewport.maximumHeight = 256
        XCTAssertEqual(viewport.sized(content, offered: 380).height, 72)
        XCTAssertEqual(viewport.sized(LayoutSize(width: 380, height: 800), offered: 380).height, 256)
        viewport.height = 40
        XCTAssertEqual(viewport.sized(content, offered: 380).height, 40)

        var horizontal = LayoutValues()
        horizontal.scrollAxes = .horizontal
        XCTAssertEqual(horizontal.sized(content).width, 380)
        horizontal.safeBarSizingAxes = .horizontal
        horizontal.maximumWidth = 100
        XCTAssertEqual(horizontal.sized(content).width, 100)
    }

    private let whole = Rect(x: 0, y: 0, width: 400, height: 800)
    private let safe = Rect(x: 0, y: 60, width: 400, height: 710)

    func testFractionalChildFramesDoNotInventConsumedInsets() {
        let consumed = EdgeInsets(top: 48, leading: 0, bottom: 0, trailing: 0)
        // These are the two VStack allocations from the startup crash log.
        let allocations: [(Double, Double)] = [
            (304.9440002441406, 111.99999745686848),
            (304.94400787353516, 112),
        ]
        for (parentHeight, childHeight) in allocations {
            let parent = SafeAreaContext(bounds: Rect(0, 0, 448, parentHeight), consumed: consumed)
            let frame = Rect(64, parentHeight - childHeight, 320, childHeight)
            for preservingOutsets in [false, true] {
                let child = parent.child(in: frame, preservingOutsets: preservingOutsets)
                XCTAssertEqual(child.consumed, consumed,
                               "an interior child consumes no new edge, even at a fractional origin")
                XCTAssertEqual(child.bounds, child.layout)
                XCTAssertEqual(child.container, child.layout)
                XCTAssertEqual(child.keyboard, child.layout)
                XCTAssertEqual(child.insets, EdgeInsets(0))
                let native = child.resizedLayout(to: Rect(0, 0, 320, 112))
                XCTAssertEqual(native.safe, native.layout)
                XCTAssertEqual(native.consumed, consumed)
                XCTAssertEqual(native.insets, EdgeInsets(0))
            }
        }
    }

    func testEqualRegionsResizeExactlyToAFractionalProposal() {
        let original = Rect(13.37, 192.94400278727215, 320, 111.99999745686848)
        let context = SafeAreaContext(bounds: original)
        for proposal in [Rect(0, 0, 320, 112), Rect(27.3, -117.4, 100.2, 81.75)] {
            let resized = context.resizedLayout(to: proposal)
            XCTAssertEqual(resized.bounds, proposal)
            XCTAssertEqual(resized.layout, proposal)
            XCTAssertEqual(resized.container, proposal)
            XCTAssertEqual(resized.keyboard, proposal)
            XCTAssertEqual(resized.safe, proposal)
            XCTAssertEqual(resized.insets, EdgeInsets(0))
        }
    }

    func testContainedFractionalIntersectionsPreserveTheOriginalExtent() {
        let outer = Rect(-100.1, -200.2, 1000.3, 900.4)
        let inner = Rect(64.1, 192.94400278727215, 320.2, 111.99999745686848)
        XCTAssertEqual(SafeAreaContext.intersection(outer, inner), inner)
        XCTAssertEqual(SafeAreaContext.intersection(inner, outer), inner)
        XCTAssertEqual(SafeAreaContext.intersection(inner, inner), inner)
        XCTAssertEqual(SafeAreaContext.insets(of: inner, in: inner), EdgeInsets(0))
    }

    func testRealSmallFractionalContributionsSurviveResizingAndConsumption() {
        let unit = 1.0 / 1_048_576
        let room = Rect(0, 0, 320, 112)
        let expected = EdgeInsets(top: 2 * unit, leading: unit, bottom: 4 * unit, trailing: 3 * unit)
        let context = SafeAreaContext(
            bounds: Rect(-unit, -2 * unit, 320 + 4 * unit, 112 + 6 * unit),
            layout: room, container: room)
        XCTAssertEqual(context.insets, expected)
        XCTAssertEqual(context.child(in: room, preservingOutsets: false).consumed, expected)

        let proposal = Rect(0, 0, 125.5, 81.75)
        let resized = context.resizedLayout(to: proposal)
        XCTAssertEqual(resized.insets, expected)
        XCTAssertEqual(resized.child(in: proposal, preservingOutsets: false).consumed, expected)
        XCTAssertEqual(context.consuming(in: context.bounds).consumed, expected)
    }

    func testARegionOutsideTheChildStaysUnsafeWhenItsProposalChanges() {
        let room = Rect(0, 0, 100, 100)
        let outside = Rect(-500, 0, 100, 100)
        let context = SafeAreaContext(bounds: room, container: outside)
        let child = context.child(in: room, preservingOutsets: false)
        XCTAssertEqual(child.container, outside,
                       "an empty intersection must not become a new safe edge at the child's origin")
        XCTAssertEqual(child.safe.width, 0)
        XCTAssertEqual(child.resizedLayout(to: Rect(0, 0, 200, 100)).safe.width, 0)
    }

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
