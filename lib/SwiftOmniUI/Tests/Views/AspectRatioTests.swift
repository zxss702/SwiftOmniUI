// SPDX-License-Identifier: Apache-2.0
@_spi(Host) @testable import SwiftOmniUICore
import XCTest

@MainActor final class AspectRatioTests: XCTestCase {
    private func subviews(placing: @escaping (Point, UnitPoint, ProposedViewSize) -> Void = { _, _, _ in }) -> LayoutSubviews {
        LayoutSubviews([LayoutSubview(layoutValues: [:], priority: 0,
            measureSize: { $0.replacingUnspecifiedDimensions(by: Size(120, 60)) },
            measureDimensions: { _ in ViewDimensions(width: 120, height: 60) },
            placeView: placing)])
    }

    func testFitAndFillNegotiateBothAxes() {
        var cache = ()
        let proposal = ProposedViewSize(width: 120, height: 120)
        XCTAssertEqual(AspectRatioLayout(ratio: 2, mode: .fit)
            .sizeThatFits(proposal: proposal, subviews: subviews(), cache: &cache), Size(120, 60))
        XCTAssertEqual(AspectRatioLayout(ratio: 2, mode: .fill)
            .sizeThatFits(proposal: proposal, subviews: subviews(), cache: &cache), Size(240, 120))
    }

    func testWidthOnlyProposalDerivesHeightAndNilRatioUsesIdealSize() {
        var cache = ()
        XCTAssertEqual(AspectRatioLayout(ratio: 3, mode: .fit)
            .sizeThatFits(proposal: ProposedViewSize(width: 300), subviews: subviews(), cache: &cache), Size(300, 100))
        XCTAssertEqual(AspectRatioLayout(ratio: nil, mode: .fit)
            .sizeThatFits(proposal: ProposedViewSize(height: 90), subviews: subviews(), cache: &cache), Size(180, 90))
    }

    func testFillPlacesOverflowAtTheCenterWithoutClipping() {
        var cache = ()
        var placed: (Point, UnitPoint, ProposedViewSize)?
        AspectRatioLayout(ratio: 2, mode: .fill).placeSubviews(
            in: Rect(10, 20, 120, 120), proposal: ProposedViewSize(width: 120, height: 120),
            subviews: subviews { placed = ($0, $1, $2) }, cache: &cache)
        XCTAssertEqual(placed?.0, Point(70, 80))
        XCTAssertEqual(placed?.1, .center)
        XCTAssertEqual(placed?.2, ProposedViewSize(width: 240, height: 120))
    }
}
