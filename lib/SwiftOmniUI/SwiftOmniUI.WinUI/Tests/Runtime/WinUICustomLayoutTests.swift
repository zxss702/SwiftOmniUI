// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

@MainActor private final class ProposalMeasuredView: WinUIView {
    var proposals: [ProposedViewSize] = []

    init() { super.init { _ in swiftomniui_winui_text_make() } }

    override func measure(width: Double?, height: Double?) -> LayoutSize {
        proposals.append(ProposedViewSize(width: width, height: height))
        return LayoutSize(width: width ?? 37, height: height ?? 23)
    }
}

private final class HeightAwareTestLayout: Layout, @unchecked Sendable {
    typealias Cache = Void
    var proposals: [ProposedViewSize] = []
    var queriedSizes: [SwiftOmniUICore.Size] = []
    var queriedDimensions: [SwiftOmniUICore.Size] = []
    var placementsDuringArrange = 0
    var placementCalls = 0
    var defaultHeight = 160.0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> Size {
        proposals.append(proposal)
        if let child = subviews.first {
            queriedSizes.append(child.sizeThatFits(proposal))
            let dimensions = child.dimensions(in: proposal)
            queriedDimensions.append(Size(width: dimensions.width, height: dimensions.height))
        }
        return proposal.replacingUnspecifiedDimensions(by: Size(width: 200, height: defaultHeight))
    }

    func placeSubviews(in bounds: Rect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        placementCalls += 1
        if MainActor.assumeIsolated({ WinUIView.arranging > 0 }) { placementsDuringArrange += 1 }
        for child in subviews {
            child.place(at: Point(bounds.x + bounds.width / 2, bounds.y + bounds.height / 2),
                        anchor: .center,
                        proposal: ProposedViewSize(width: bounds.width / 2, height: bounds.height / 2))
        }
    }
}

final class WinUICustomLayoutTests: XCTestCase {
    func testReplacingTheUserLayoutInvalidatesAnUnchangedChildList() {
        onUIThread {
            let child = ProposalMeasuredView()
            let custom = WinUICustomLayoutView()
            let collapsed = HeightAwareTestLayout()
            collapsed.defaultHeight = 40
            custom.setItems([WinUILayoutItem(view: child)], layout: LayoutBox(collapsed))
            XCTAssertEqual(custom.naturalSize(width: 200).height, 40)

            let expanded = HeightAwareTestLayout()
            expanded.defaultHeight = 128
            custom.setItems([WinUILayoutItem(view: child)], layout: LayoutBox(expanded))
            XCTAssertEqual(custom.naturalSize(width: 200).height, 128)
        }
    }

    func testCustomLayoutPreservesHeightInSizeDimensionsAndPlacementProposals() throws {
        try onUIThread {
            let layout = HeightAwareTestLayout()
            let child = ProposalMeasuredView()
            let custom = WinUICustomLayoutView()
            custom.padding = EdgeInsets(10)
            custom.setItems([WinUILayoutItem(view: child)], layout: LayoutBox(layout))

            for height in [160.0, 80, 160] {
                let size = custom.naturalSize(proposal: ProposedViewSize(width: 200, height: height))
                XCTAssertEqual(size, LayoutSize(width: 200, height: height))
            }
            XCTAssertTrue(child.proposals.contains(ProposedViewSize(width: 180, height: 140)))
            XCTAssertTrue(child.proposals.contains(ProposedViewSize(width: 180, height: 60)))
            XCTAssertEqual(layout.queriedSizes, layout.queriedDimensions)

            let plan = WinUILayoutView.querySize {
                custom.makeLayoutPlan(in: Rect(0, 0, 200, 160))
            }
            let placement = try XCTUnwrap(plan.first)
            XCTAssertTrue(placement.view === child)
            XCTAssertEqual(placement.place, Rect(55, 45, 90, 70),
                           "the anchor uses the child's response to both proposed axes")
            XCTAssertEqual(child.proposals.last, ProposedViewSize(width: 90, height: 70))
        }
    }

    func testNativeArrangeConsumesTheMeasuredCustomPlanWithoutCallingUserLayoutAgain() throws {
        try onUIThread {
            let layout = HeightAwareTestLayout()
            let height = State(wrappedValue: 160.0)
            let host = WinUIRenderer.running(reducesMotion: true) {
                layout {
                    Rectangle().frame(maxWidth: .infinity, maxHeight: .infinity).id("child")
                }.frame(width: 240, height: height.wrappedValue)
            }
            for _ in 0..<8 { host.step(); host.frame() }
            let custom = try XCTUnwrap(host.views(WinUICustomLayoutView.self).first)
            let child = try XCTUnwrap(host.view(id: .manual("child")))
            XCTAssertEqual(child.laidOutFrame.width, 120, accuracy: 1)
            XCTAssertEqual(child.laidOutFrame.height, 80, accuracy: 1)
            let placements = layout.placementCalls
            for _ in 0..<4 { custom.invalidateArrange(); host.layOut() }
            XCTAssertEqual(layout.placementCalls, placements,
                           "Arrange consumes a recorded plan and performs no child-size queries")
            XCTAssertEqual(layout.placementsDuringArrange, 0)

            height.wrappedValue = 240
            host.settle { child.laidOutFrame.height == 120 }
            XCTAssertEqual(child.laidOutFrame.height, 120, accuracy: 1)
            XCTAssertTrue(host.view(id: .manual("child")) === child)
            XCTAssertTrue(layout.proposals.contains(ProposedViewSize(width: 240, height: 240)))
            XCTAssertEqual(layout.placementsDuringArrange, 0)
        }
    }
}
