// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

@MainActor
private final class ScrollPlanMeasureProbe: WinUILayoutView {
    var nativeMeasurements = 0
    var measuredDuringArrange = false

    override func measure(width: Double, height: Double) -> LayoutSize {
        nativeMeasurements += 1
        measuredDuringArrange = measuredDuringArrange || WinUIView.arranging > 0
        return super.measure(width: width, height: height)
    }

    override func contentSize(width: Double?) -> LayoutSize {
        LayoutSize(width: width ?? 80, height: 40)
    }
}

final class WinUIScrollLayoutPlanTests: XCTestCase {
    func testUnspecifiedHeightPreparesTheNativeScrollerBeforeAnEqualHeightArrange() {
        onUIThread {
            let child = ScrollPlanMeasureProbe()
            let scroll = WinUIScrollView()
            scroll.setItems([WinUILayoutItem(view: child)])

            scroll.prepareMeasure(width: 320)

            XCTAssertGreaterThan(child.nativeMeasurements, 0,
                                 "the native scroller must measure its document during the unspecified-height Measure")
            XCTAssertFalse(child.measuredDuringArrange)
            let measurements = child.nativeMeasurements
            let desired = scroll.scroller.desiredSize
            XCTAssertGreaterThan(desired.height, 0)

            scroll.arrange(width: 320, height: 40)

            XCTAssertEqual(scroll.scroller.placedFrame, Rect(0, 0, 320, 40))
            XCTAssertEqual(child.nativeMeasurements, measurements,
                           "an equal finite Arrange must consume the completed viewport plan")
            XCTAssertFalse(child.measuredDuringArrange,
                           "the first native document Measure must not be deferred until Arrange")
        }
    }

    func testRestoringTheViewportPlanDoesNotAccumulateSafeAreaPadding() throws {
        try onUIThread {
            let child = ScrollPlanMeasureProbe()
            let scroll = WinUIScrollView()
            scroll.setItems([WinUILayoutItem(view: child)])
            scroll.safeAreaContext = SafeAreaContext(
                bounds: Rect(0, 0, 320, 200), container: Rect(0, 20, 320, 160))
            scroll.apply(orientation: .vertical,
                         padding: EdgeInsets(top: 3, leading: 5, bottom: 7, trailing: 11),
                         verticalBar: .automatic, horizontalBar: .automatic,
                         defaultAnchor: nil, offset: nil, bounce: .automatic, bounceAxes: .vertical)
            let document = try XCTUnwrap(child.placingLayout as? WinUIScrollDocument)
            let expected = EdgeInsets(top: 23, leading: 5, bottom: 27, trailing: 11)

            for _ in 0..<3 {
                scroll.prepareMeasure(width: 320, height: 200)
                scroll.arrange(width: 320, height: 200)
                XCTAssertEqual(document.layoutPadding, expected)
                XCTAssertEqual(document.consumedInsets, EdgeInsets(top: 20, leading: 0, bottom: 20, trailing: 0))
                XCTAssertEqual(scroll.scroller.placedFrame, Rect(0, 0, 320, 200))
            }
        }
    }
}
