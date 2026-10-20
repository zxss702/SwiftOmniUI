// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import CSwiftOmniUIWinUI
import XCTest

/// Records real native MeasureOverride callbacks, including any speculative
/// proposal a parent incorrectly commits while consuming an allocation plan.
@MainActor
private final class PlanConsumptionChild: WinUILayoutView {
    var nativeMeasurements: [ProposedViewSize] = []
    var extent = 40.0

    override func measure(width: Double, height: Double) -> LayoutSize {
        nativeMeasurements.append(ProposedViewSize(width: width, height: height))
        return super.measure(width: width, height: height)
    }

    override func contentSize(width: Double?) -> LayoutSize {
        LayoutSize(width: 80, height: extent)
    }
}

final class WinUILayoutPlanConsumptionTests: XCTestCase {
    func testWidthOnlyAllocationObservesAWritingBatchsSecondLayoutChange() throws {
        try onUIThread {
            let input = WinUIZStackView()
            let controls = WinUIZStackView()
            var inputItem = WinUILayoutItem(view: input)
            inputItem.values.expandingAxes = .horizontal
            inputItem.values.height = 128
            var controlsItem = WinUILayoutItem(view: controls)
            controlsItem.values.width = 40
            controlsItem.values.height = 40
            let row = WinUIStackView(axis: .horizontal)
            row.setItems([inputItem, controlsItem])

            try ProgramWrite.perform {
                row.spacing = 8
                // Allocation can consume arithmetic without a native Measure.
                row.prepareAllocation(in: Rect(0, 0, 320, 128))
                // The container and both children's declared heights stay put.
                // A second layout write must discard the just-prepared plan.
                row.spacing = 24
                row.arrange(width: 320, height: 128)
                let inputFrame = try XCTUnwrap(input.committedFrame)
                let controlsFrame = try XCTUnwrap(controls.committedFrame)
                XCTAssertEqual(inputFrame, Rect(0, 0, 256, 128))
                XCTAssertEqual(controlsFrame.x, 280)
                XCTAssertEqual(controlsFrame.width, 40)
                XCTAssertEqual(controlsFrame.x - inputFrame.width, 24)
            }
        }
    }

    func testOpeningTabbedScrollContentInAWindowReachesAnIdleNativeLayout() {
        onUIThread {
            for extent in [40.0, 2000] {
                let child = PlanConsumptionChild()
                child.extent = extent
                let scroll = WinUIScrollView()
                scroll.setItems([WinUILayoutItem(view: child)])
                let tabs = WinUITabbedView()
                tabs.setItems([WinUILayoutItem(view: scroll)])
                tabs.show(["Content"], requested: 0)
                WinUITestHost.window.show(tabs)
                defer { WinUITestHost.window.show(nil) }

                for _ in 0..<8 {
                    swiftomniui_winui_update_layout(tabs.handle)
                    WinUIDoorbell.commitPending()
                }
                XCTAssertGreaterThan(child.laidOutFrame.width, 0)
                XCTAssertEqual(child.laidOutFrame.height, extent, accuracy: 1)
                let measurements = child.nativeMeasurements.count
                let sizings = WinUILayoutView.sizings
                for _ in 0..<4 {
                    swiftomniui_winui_update_layout(tabs.handle)
                    WinUIDoorbell.commitPending()
                }
                XCTAssertEqual(child.nativeMeasurements.count, measurements,
                               "opening the window must not keep restarting native measurement")
                XCTAssertEqual(WinUILayoutView.sizings, sizings)
            }
        }
    }

    func testScrollDocumentArrangeKeepsThePreparedFiniteChildProposal() {
        onUIThread {
            let child = PlanConsumptionChild()
            let document = WinUIScrollDocument()
            document.setItems([WinUILayoutItem(view: child)])
            document.prepareMeasure(width: 320, height: 240)
            document.arrange(width: 320, height: 240)
            child.nativeMeasurements.removeAll()

            for _ in 0..<3 { document.arrange(width: 320, height: 240) }

            XCTAssertEqual(child.placedFrame, Rect(0, 0, 320, 40))
            XCTAssertTrue(child.nativeMeasurements.allSatisfy { $0.height == 40 },
                          "Arrange must consume its plan without alternating unbounded and allocated child heights")
        }
    }

    func testTabbedArrangeKeepsThePreparedFiniteProposalOfAnIntrinsicPage() {
        onUIThread {
            let child = PlanConsumptionChild()
            var page = WinUILayoutItem(view: child)
            page.values.horizontal = 0
            page.values.vertical = 0
            let tabs = WinUITabbedView()
            tabs.setItems([page])
            tabs.show(["First"], requested: 0)
            tabs.prepareMeasure(width: 320, height: 240)
            tabs.arrange(width: 320, height: 240)
            child.nativeMeasurements.removeAll()

            for _ in 0..<3 { tabs.arrange(width: 320, height: 240) }

            XCTAssertEqual(child.placedFrame.width, 80)
            XCTAssertEqual(child.placedFrame.height, 40)
            XCTAssertEqual(child.placedFrame.y, tabs.row.placedFrame.height)
            XCTAssertTrue(child.nativeMeasurements.allSatisfy { $0.width == 80 && $0.height == 40 },
                          "the intrinsic page must not be remeasured at an unbounded height during tab arrangement")
        }
    }

    func testWindowHostedTabsLeaveNoLocalTabRowInThePlan() {
        onUIThread {
            let child = PlanConsumptionChild()
            let tabs = WinUITabbedView()
            tabs.setItems([WinUILayoutItem(view: child)])
            tabs.show(["First"], requested: 0)
            tabs.tabsShownByWindow = true
            tabs.prepareMeasure(width: 320, height: 240)
            tabs.arrange(width: 320, height: 240)
            child.nativeMeasurements.removeAll()

            for _ in 0..<3 { tabs.arrange(width: 320, height: 240) }

            XCTAssertEqual(child.placedFrame, Rect(0, 0, 320, 240))
            XCTAssertTrue(child.nativeMeasurements.allSatisfy { $0.width == 320 && $0.height == 240 })
        }
    }
}
