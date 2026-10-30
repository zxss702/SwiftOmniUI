// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) @testable import SwiftOmniUICore
@_spi(Host) @testable import SwiftOmniUIHost
import XCTest

@MainActor
final class StackDistributionTests: XCTestCase {
    func testLongInputAcceptsRemainingWidthBetweenIntrinsicButtons() {
        let offers = StackOffers()
        var input = StackChild(width: 1_000, height: 20)
        input.values.expandingAxes = .horizontal
        input.offers = offers
        let children = [StackChild(width: 40, height: 20), input, StackChild(width: 40, height: 20)]

        let measured = StackArithmetic.size(
            of: children, axis: .horizontal, spacing: 0, padding: EdgeInsets(0), width: 400)
        let arranged = places(children, length: 400)

        XCTAssertEqual(measured.width, 400)
        XCTAssertEqual(arranged.map { $0?.width }, [40, 320, 40])
        XCTAssertEqual(arranged.map { $0?.x }, [0, 40, 360])
        XCTAssertEqual(offers.widths.last ?? nil, 320, "measurement and placement must offer the same input width")
    }

    func testExpandingEditorLeavesIntrinsicHeaderAndFooterTheirHeights() {
        var editor = StackChild(width: 20, height: 1_000)
        editor.values.expandingAxes = .both

        let arranged = places(
            [StackChild(width: 20, height: 40), editor, StackChild(width: 20, height: 40)],
            axis: .vertical, length: 300)

        XCTAssertEqual(arranged.map { $0?.height }, [40, 220, 40])
        XCTAssertEqual(arranged.map { $0?.y }, [0, 40, 260])
    }

    func testScrollViewportAcceptsRemainingHeightBesideFixedFooter() {
        var scroll = StackChild(width: 20, height: 1_000)
        scroll.values.scrollAxes = .vertical
        var footer = StackChild(width: 20, height: 40)
        footer.values.height = 40

        let arranged = places([scroll, footer], axis: .vertical, length: 300)

        XCTAssertEqual(arranged.map { $0?.height }, [260, 40])
        XCTAssertEqual(arranged[1]?.y, 260)
    }

    func testPriorityTakesPrecedenceOverExpansion() {
        var intrinsic = StackChild(width: 100, height: 20)
        var input = StackChild(width: 400, height: 20)
        input.values.expandingAxes = .horizontal
        input.values.priority = 1

        XCTAssertEqual(places([intrinsic, input], length: 300).map { $0?.width }, [0, 300])

        intrinsic.values.priority = 2
        XCTAssertEqual(places([intrinsic, input], length: 300).map { $0?.width }, [100, 200])
    }

    func testIntrinsicRowKeepsSmallMarkersAndGivesTheRemainderToText() {
        let arranged = places([StackChild(width: 10, height: 20), StackChild(width: 100, height: 20)], length: 50)

        XCTAssertEqual(arranged.map { $0?.width }, [10, 40])
        XCTAssertEqual(arranged[1]?.x, 10)
    }

    func testPaddedFixedIconKeepsItsMinimumBesideHigherPriorityFilename() {
        // The fixed frame is inside padding, so the outer row item has no
        // explicit width. Its zero-proposal answer still reserves 32 points.
        var icon = StackChild(width: 32, height: 16)
        icon.minimumProposalWidth = 32
        var filename = StackChild(width: 1_000, height: 20)
        filename.values.priority = 1
        filename.values.expandingAxes = .horizontal
        var actions = StackChild(width: 42, height: 18)
        actions.values.width = 42
        var status = StackChild(width: 16, height: 20)
        status.values.width = 16

        let arranged = places([icon, filename, actions, status], length: 240)
        XCTAssertEqual(arranged.map { $0?.width }, [32, 150, 42, 16])
        XCTAssertEqual(arranged.map { $0?.x }, [0, 32, 182, 224])
    }

    func testUnconstrainedRowDoesNotProbeMinimumWidths() {
        let offers = StackOffers()
        var icon = StackChild(width: 32, height: 16)
        icon.minimumProposalWidth = 32
        icon.offers = offers
        _ = places([icon, StackChild(width: 80, height: 20)], length: 240)
        XCTAssertFalse(offers.widths.contains { $0 == 0 })
    }

    func testIntrinsicSharingReservesLargeMinimaBeforeAcceptingShortIdealWidths() {
        let marker = StackChild(width: 10, height: 20)
        var text = StackChild(width: 100, height: 20)
        text.values.minimumWidth = 80
        XCTAssertEqual(places([marker, text], length: 80).map { $0?.width }, [0, 80])
        XCTAssertEqual(places([marker, text], length: 90).map { $0?.width }, [10, 80])
    }

    func testIntrinsicRowDistributesSeveralSmallAndLargeChildrenSymmetrically() {
        let children = [StackChild(width: 10, height: 20), StackChild(width: 100, height: 20),
                        StackChild(width: 20, height: 20), StackChild(width: 200, height: 20)]
        XCTAssertEqual(places(children, length: 100).map { $0?.width }, [10, 35, 20, 35])
    }

    func testCompressionRedistributesWithinPriorityBeforeTouchingHigherPriority() {
        var small = StackChild(width: 20, height: 20)
        small.values.minimumWidth = 15
        var large = StackChild(width: 100, height: 20)
        large.values.minimumWidth = 10
        var protected = StackChild(width: 40, height: 20)
        protected.values.priority = 1

        let arranged = places([small, large, protected], length: 90)

        XCTAssertEqual(arranged.map { $0?.width }, [20, 30, 40])
        XCTAssertEqual(arranged[2]?.x, 50)
    }

    func testSpacerCanShrinkItsNaturalExtentAndKeepsItsMinimum() {
        var spacer = StackChild(width: 100, height: 0)
        spacer.values.flex = 20
        let button = StackChild(width: 40, height: 20)

        XCTAssertEqual(places([spacer, button], length: 100).map { $0?.width }, [60, 40])
        XCTAssertEqual(places([spacer, button], length: 50).map { $0?.width }, [20, 30])
    }

    func testExplicitMainAxisSizeRemainsFixedEvenWithFlexibility() {
        var fixed = StackChild(width: 120, height: 20)
        fixed.values.width = 120
        fixed.values.flex = 0
        fixed.values.expandingAxes = .horizontal
        let sibling = StackChild(width: 40, height: 20)

        XCTAssertEqual(places([fixed, sibling], length: 100).map { $0?.width }, [120, 0])

        var spacer = StackChild(width: 0, height: 0)
        spacer.values.flex = 0
        XCTAssertEqual(places([fixed, spacer], length: 200).map { $0?.width }, [120, 80])
    }

    func testUnsatisfiedMinimaKeepAuthoredOverflow() {
        var input = StackChild(width: 200, height: 20)
        input.values.expandingAxes = .horizontal
        input.values.minimumWidth = 80
        var fixed = StackChild(width: 40, height: 20)
        fixed.values.width = 40

        let arranged = places([input, fixed], length: 100)

        XCTAssertEqual(arranged.map { $0?.width }, [80, 40])
        XCTAssertEqual(arranged[1]?.x, 80)
    }

    func testExpansionRedistributesAfterMaximumSaturatesOnEitherAxis() {
        for axis in [StackArithmetic.Axis.horizontal, .vertical] {
            var first = StackChild(width: 0, height: 0)
            first.values.flex = 0
            var second = first
            let third = first
            if axis == .horizontal {
                first.values.maximumWidth = 10
                second.values.maximumWidth = 30
            } else {
                first.values.maximumHeight = 10
                second.values.maximumHeight = 30
            }

            let arranged = places([first, second, third], axis: axis, length: 120)
            let extents = arranged.map { axis == .horizontal ? $0?.width : $0?.height }
            XCTAssertEqual(extents, [10, 30, 80])
        }
    }

    func testAllMaximumBoundsLeaveUnusedRoomCentered() {
        var first = StackChild(width: 0, height: 0)
        first.values.flex = 0
        first.values.maximumWidth = 20
        var second = first
        second.values.maximumWidth = 40

        let arranged = places([first, second], length: 100)

        XCTAssertEqual(arranged.map { $0?.width }, [20, 40])
        XCTAssertEqual(arranged.map { $0?.x }, [20, 40])
    }

    func testSpacerMinimumWinsAContradictingMaximum() {
        var spacer = StackChild(width: 0, height: 0)
        spacer.values.flex = 40
        spacer.values.maximumWidth = 20

        XCTAssertEqual(places([spacer], length: 100)[0]?.width, 40)
    }

    func testDistributionCountsMarginsSpacingPaddingAndHiddenChildren() {
        var input = StackChild(width: 1_000, height: 20)
        input.values.expandingAxes = .horizontal
        input.values.margin = EdgeInsets(4)
        var hidden = StackChild(width: 1_000, height: 20)
        hidden.isShown = false
        let children = [StackChild(width: 40, height: 20), input, hidden, StackChild(width: 40, height: 20)]

        let arranged = StackArithmetic.places(
            of: children, axis: .horizontal, spacing: 6, padding: EdgeInsets(10),
            in: Rect(0, 0, 400, 48), direction: .rightToLeft)

        XCTAssertEqual(arranged.map { $0?.width }, [40, 280, nil, 40])
        XCTAssertEqual(arranged.map { $0?.x }, [350, 60, nil, 10])
    }

    private func places(_ children: [StackChild], axis: StackArithmetic.Axis = .horizontal, length: Double) -> [Rect?] {
        StackArithmetic.places(
            of: children, axis: axis, spacing: 0, padding: EdgeInsets(0),
            in: axis == .horizontal ? Rect(0, 0, length, 20) : Rect(0, 0, 20, length), direction: .leftToRight)
    }
}

private struct StackChild: LayoutChild {
    var values = LayoutValues()
    let natural: LayoutSize
    var isShown = true
    var offers: StackOffers?
    var minimumProposalWidth = 0.0

    init(width: Double, height: Double) {
        natural = LayoutSize(width: width, height: height)
    }

    func size(offered width: Double?) -> LayoutSize {
        offers?.widths.append(width)
        let offered = values.offer(width)
        let measured = LayoutSize(width: offered.map { max(minimumProposalWidth, min(natural.width, $0)) } ?? natural.width,
                                  height: natural.height)
        return values.sized(measured, offered: width)
    }
}

@MainActor
private final class StackOffers {
    var widths: [Double?] = []
}
