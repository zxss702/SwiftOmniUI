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
    func testNestedLazyScrollerFitsShortContentAndScrollsOnlyAboveItsMaximum() throws {
        try onUIThread {
            let paragraphs = State(wrappedValue: 2)
            let host = WinUIRenderer.running(reducesMotion: true) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Text("Before").frame(height: 24)
                        VStack(alignment: .leading, spacing: 0) {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    ForEach(0..<paragraphs.wrappedValue) { number in
                                        Text("Thought paragraph \(number)")
                                            .frame(height: 28)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }.frame(maxHeight: 256)
                        }
                        Text("After").frame(height: 24)
                    }
                }.frame(width: 320, height: 480)
            }
            // Includes just below / above the cap and shrinkage after scrolling.
            for count in [2, 9, 10, 300, 1, 2] {
                paragraphs.wrappedValue = count
                let height = min(Double(count * 28), 256)
                host.settle {
                    guard let inner = host.views(WinUIScrollView.self).dropFirst().first else { return false }
                    return abs(inner.scroller.laidOutFrame.height - height) < 1
                        && (count * 28 <= 256 ? inner.scroller.standing.reach.y < 1
                                             : inner.scroller.standing.reach.y > 0)
                }
                let inner = try XCTUnwrap(host.views(WinUIScrollView.self).dropFirst().first)
                XCTAssertEqual(inner.scroller.laidOutFrame.height, height, accuracy: 1)
                if count * 28 <= 256 {
                    XCTAssertEqual(inner.scroller.standing.reach.y, 0, accuracy: 1)
                    XCTAssertEqual(inner.scroller.standing.offset.y, 0, accuracy: 1)
                } else {
                    XCTAssertGreaterThan(inner.scroller.standing.reach.y, 0)
                    inner.scroller.move(to: Point(0, 20))
                    host.settle { abs(inner.scroller.standing.offset.y - 20) < 1 }
                    XCTAssertEqual(inner.scroller.standing.offset.y, 20, accuracy: 1)
                }
                if count == 300 {
                    let lazy = try XCTUnwrap(host.views(WinUILazyStackView.self).last)
                    XCTAssertLessThan(lazy.cells.built.count, count)
                }
            }
        }
    }

    func testExpandingABoundedNestedLazyScrollerKeepsItsViewportHeight() throws {
        try onUIThread {
            let expanded = State(wrappedValue: false)
            let maximum = State(wrappedValue: 256.0)
            let host = WinUIRenderer.running(reducesMotion: true) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Text("Before").frame(height: 24)
                        VStack(alignment: .leading, spacing: 0) {
                            if expanded.wrappedValue {
                                ScrollView {
                                    LazyVStack(alignment: .leading, spacing: 0) {
                                        ForEach(0..<300) { number in
                                            Text("Thought paragraph \(number)")
                                                .frame(height: 28)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                }.frame(maxHeight: maximum.wrappedValue)
                            } else {
                                Text("Summary").frame(height: 24)
                            }
                        }
                        Text("After").frame(height: 24)
                    }
                }.frame(width: 320, height: 480)
            }
            XCTAssertEqual(host.views(WinUIScrollView.self).count, 1)
            for _ in 0..<2 {
                expanded.wrappedValue = true
                for limit in [256.0, 128.0, 256.0] {
                    maximum.wrappedValue = limit
                    host.settle {
                        host.views(WinUIScrollView.self).count == 2
                            && abs((host.views(WinUIScrollView.self).last?.scroller.laidOutFrame.height ?? 0) - limit) < 1
                    }
                    let inner = try XCTUnwrap(host.views(WinUIScrollView.self).last)
                    XCTAssertEqual(inner.scroller.laidOutFrame.height, limit, accuracy: 1)
                    XCTAssertGreaterThan(inner.scroller.standing.reach.y, 0)
                    let lazy = try XCTUnwrap(host.views(WinUILazyStackView.self).last)
                    XCTAssertLessThan(lazy.cells.built.count, 300,
                                      "the inner document must remain lazy when its viewport is measured")
                    inner.scroller.move(to: Point(0, 140))
                    host.settle { abs(inner.scroller.standing.offset.y - 140) < 1 }
                    XCTAssertEqual(inner.scroller.standing.offset.y, 140, accuracy: 1)
                }
                expanded.wrappedValue = false
                host.settle { host.views(WinUIScrollView.self).count == 1 }
                XCTAssertEqual(host.views(WinUIScrollView.self).count, 1)
            }
        }
    }

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
