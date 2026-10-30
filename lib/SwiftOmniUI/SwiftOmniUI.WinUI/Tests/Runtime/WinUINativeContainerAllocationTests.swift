// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

@MainActor
private final class ContainerAllocationPage: WinUISingleChildView {
    var nativeMeasures = 0

    override func measure(width: Double, height: Double) -> LayoutSize {
        nativeMeasures += 1
        return super.measure(width: width, height: height)
    }
}

@MainActor
private final class ContainerAllocationDocument: WinUILayoutView {
    override func contentSize(width: Double?) -> LayoutSize {
        LayoutSize(width: width ?? 320, height: 2000)
    }
}

final class WinUINativeContainerAllocationTests: XCTestCase {
    func testPreparingAFractionalSplitAllocationDoesNotMeasureItsNativeContainerOrPages() {
        onUIThread {
            let pane = ContainerAllocationPage()
            let text = WinUILabelView()
            text.setText("Sidebar")
            pane.setItems([WinUILayoutItem(view: text)])
            let detail = ContainerAllocationPage()
            detail.setItems([WinUILayoutItem(view: ContainerAllocationDocument())])
            let split = WinUISplitView()
            split.setItems([WinUILayoutItem(view: pane), WinUILayoutItem(view: detail)])
            split.prepareFirstPresentation(width: 1280)
            split.present(false)
            let root = WinUISingleChildView()
            root.setItems([WinUILayoutItem(view: split)])
            root.prepareMeasure(width: 1280, height: 792)
            let desired = split.sidebar.desiredSize
            let measures = [pane.nativeMeasures, detail.nativeMeasures]
            let allocation = Rect(0, 0, 1280, Double(Float(792 + 1 / 1.75)))

            root.withNativeArrange { split.prepareAllocation(in: allocation) }

            XCTAssertEqual(split.sidebar.desiredSize, desired,
                           "preparing an Arrange slot must retain the native SplitView's Measure result")
            XCTAssertEqual([pane.nativeMeasures, detail.nativeMeasures], measures,
                           "a fractional final slot cannot trigger another native measurement of every page")
            // Both the parent's preparation and WinUIView.layout must obey
            // the same allocation contract before native Arrange begins.
            swiftomniui_winui_arrange(root.handle, 0, 0, allocation.width, allocation.height)
            XCTAssertEqual(split.sidebar.desiredSize, desired)
            XCTAssertGreaterThan(detail.laidOutFrame.width, 0)
            XCTAssertGreaterThan(detail.laidOutFrame.height, 0)
            let committed = [pane.nativeMeasures, detail.nativeMeasures]
            for _ in 0..<8 {
                root.prepareMeasure(width: 1280, height: 792)
                swiftomniui_winui_arrange(root.handle, 0, 0, allocation.width, allocation.height)
            }
            XCTAssertEqual([pane.nativeMeasures, detail.nativeMeasures], committed,
                           "the original measured height and fractional arranged height must settle together")
        }
    }

    func testPreparingAFractionalScrollAllocationKeepsItsMeasuredViewport() {
        onUIThread {
            let scroll = WinUIScrollView()
            scroll.setItems([WinUILayoutItem(view: ContainerAllocationDocument())])
            let root = WinUISingleChildView()
            root.setItems([WinUILayoutItem(view: scroll)])
            root.prepareMeasure(width: 320, height: 128)
            let desired = scroll.scroller.desiredSize
            let allocation = Rect(0, 0, 320, Double(Float(128 + 1 / 1.75)))

            root.withNativeArrange { scroll.prepareAllocation(in: allocation) }
            XCTAssertEqual(scroll.scroller.desiredSize, desired)
            swiftomniui_winui_arrange(root.handle, 0, 0, allocation.width, allocation.height)
            XCTAssertEqual(scroll.scroller.desiredSize, desired,
                           "placing a native scroller cannot overwrite its measured viewport size")
            XCTAssertEqual(scroll.scroller.placedFrame.height, allocation.height)
        }
    }

    func testARealSplitResizeStillMeasuresNewPagesAndKeepsTheirIdentity() {
        onUIThread {
            let pane = ContainerAllocationPage()
            pane.setItems([WinUILayoutItem(view: ContainerAllocationDocument())])
            let detail = ContainerAllocationPage()
            detail.setItems([WinUILayoutItem(view: ContainerAllocationDocument())])
            let split = WinUISplitView()
            split.setItems([WinUILayoutItem(view: pane), WinUILayoutItem(view: detail)])
            split.prepareFirstPresentation(width: 1280)
            split.present(false)
            split.prepareMeasure(width: 1280, height: 792)
            let measures = detail.nativeMeasures

            split.prepareMeasure(width: 640, height: 480)
            swiftomniui_winui_arrange(split.handle, 0, 0, 640, 480)

            XCTAssertGreaterThan(detail.nativeMeasures, measures)
            XCTAssertTrue(detail.nativeLayoutOwner === split)
            XCTAssertTrue(pane.nativeLayoutOwner === split)
            XCTAssertGreaterThan(detail.laidOutFrame.width, 0)
            XCTAssertGreaterThan(detail.laidOutFrame.height, 0)
        }
    }

    func testTravellingTextStillPreparesItsDestinationRatherThanItsPresentationWidth() {
        onUIThread {
            let text = WinUILabelView()
            text.setText("Text must wrap at its destination while the narrower presentation frame is travelling")
            let destination = Rect(0, 0, 320, 80)
            let expected = text.measure(width: destination.width, height: destination.height)
            text.prepareMeasure(width: 80, height: 160)
            let narrow = text.desiredSize
            text.travels(to: destination)

            text.prepareAllocation(in: Rect(0, 0, 80, 160))

            XCTAssertEqual(text.desiredSize, expected)
            XCTAssertNotEqual(text.desiredSize, narrow)
            text.travels(to: nil)
        }
    }
}
