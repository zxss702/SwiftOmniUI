// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

final class WinUIViewportClippingTests: XCTestCase {
    func testNativeClipRectangleAndItsTransformDefineTheVisibleWindow() throws {
        try onUIThread {
            let host = WinUIRenderer.running(reducesMotion: true) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(0..<100) { Text("Row \($0)").frame(height: 28) }
                    }
                }.frame(width: 260, height: 220)
            }
            let scroll = try XCTUnwrap(host.views(WinUIScrollView.self).first)
            let lazy = try XCTUnwrap(host.views(WinUILazyView.self).first)
            let nativeSize = scroll.scroller.laidOutFrame
            @MainActor func viewport() -> [Double] {
                var value = [Double](repeating: .nan, count: 6)
                XCTAssertEqual(swiftomniui_winui_scroller_viewport(scroll.scroller.handle, lazy.handle, &value),
                               SwiftOmniUIViewportReady)
                return value
            }
            let full = viewport()
            swiftomniui_winui_set_native_clip_for_testing(scroll.scroller.handle, true, 10, 20, 100, 60, 15, 25)
            let clipped = viewport()
            let scrollOrigin = scroll.scroller.origin, rowOrigin = lazy.origin
            XCTAssertEqual(clipped[0], scrollOrigin.x - rowOrigin.x + 25, accuracy: 1)
            XCTAssertEqual(clipped[1], scrollOrigin.y - rowOrigin.y + 45, accuracy: 1)
            XCTAssertEqual(clipped[2], 100, accuracy: 1)
            XCTAssertEqual(clipped[3], 60, accuracy: 1)
            XCTAssertEqual(scroll.scroller.laidOutFrame, nativeSize, "clipping does not resize the control")

            swiftomniui_winui_set_native_clip_for_testing(scroll.scroller.handle, true, 0, 0, 0, 60, 0, 0)
            XCTAssertEqual(viewport()[2], 0, "a real empty clip remains an empty viewport")
            swiftomniui_winui_set_native_clip_for_testing(scroll.scroller.handle, false, 0, 0, 0, 0, 0, 0)
            XCTAssertEqual(viewport(), full)
        }
    }

    func testReadingAndClearingAnUnauthoredClipLeavesNativeScaleAvailable() {
        onUIThread {
            let panel = WinUIGridView()
            @MainActor func clipped() -> String {
                WinUIStrings.read { swiftomniui_winui_read(panel.handle, "clipped", $0, $1) }
            }
            XCTAssertEqual(clipped(), "0")
            swiftomniui_winui_set_clip(panel.handle, false, SwiftOmniUIOutlineRectangle, 0, 200, 100)
            swiftomniui_winui_path_clip_attach(panel.handle, nil)
            XCTAssertTrue(swiftomniui_winui_set_scale_for_testing(panel.handle, 1.25, 1.25),
                          "a read or empty clear must not claim the native element's handout Visual")

            // Exercise the opposite order too: a native owner can begin using
            // its facades before SOUI inspects or clears an absent clip.
            XCTAssertEqual(clipped(), "0")
            swiftomniui_winui_set_clip(panel.handle, false, SwiftOmniUIOutlineRectangle, 0, 200, 100)
            swiftomniui_winui_path_clip_attach(panel.handle, nil)
            XCTAssertTrue(swiftomniui_winui_set_scale_for_testing(panel.handle, 1, 1))
        }
    }

    func testViewportQueriesPreserveNativeScrollContentScaleBeforeAndAfterScrolling() throws {
        try onUIThread {
            let host = WinUIRenderer.running(reducesMotion: true) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(0..<100) { number in Text("Row \(number)").frame(height: 28) }
                    }
                }.frame(width: 260, height: 220)
            }
            let scroll = try XCTUnwrap(host.views(WinUIScrollView.self).first)
            let lazy = try XCTUnwrap(host.views(WinUILazyStackView.self).first)
            let document = try XCTUnwrap(lazy.placingLayout as? WinUIScrollDocument)
            let identity = document.handle
            for offset in [0.0, 280, 0] {
                if offset != 0 || scroll.scroller.standing.offset.y != 0 {
                    scroll.scroller.move(to: Point(0, offset))
                    host.settle { abs(scroll.scroller.standing.offset.y - offset) < 1 }
                }
                var viewport = [Double](repeating: .nan, count: 6)
                XCTAssertEqual(swiftomniui_winui_scroller_viewport(scroll.scroller.handle, lazy.handle, &viewport),
                               SwiftOmniUIViewportReady)
                XCTAssertGreaterThan(viewport[2], 0)
                XCTAssertGreaterThan(viewport[3], 0)
                XCTAssertFalse(lazy.mounted.isEmpty, "the first visible window must be mounted without a scroll")
                XCTAssertEqual(WinUIStrings.read {
                    swiftomniui_winui_read(document.handle, "clipped", $0, $1)
                }, "0")
                XCTAssertTrue(swiftomniui_winui_set_scale_for_testing(document.handle, 1, 1),
                              "viewport inspection must leave ScrollPresenter's Scale facade available")
                XCTAssertEqual(document.handle, identity)
            }
        }
    }

    func testNativeViewportFailureIsDistinctFromPendingAndPreservesTheOutput() throws {
        try onUIThread {
            let host = WinUIRenderer.running(reducesMotion: true) {
                ScrollView { Text("Content") }.frame(width: 260, height: 220)
            }
            let scroll = try XCTUnwrap(host.views(WinUIScrollView.self).first)
            // This is a valid native object but cannot be a visual descendant.
            let nonVisual = try XCTUnwrap(swiftomniui_winui_path_clip_make(scroll.handle))
            defer { swiftomniui_winui_release(nonVisual) }
            var viewport = [Double](repeating: 123, count: 6)
            XCTAssertEqual(swiftomniui_winui_scroller_viewport(scroll.scroller.handle, nonVisual, &viewport),
                           SwiftOmniUIViewportFailed)
            XCTAssertEqual(viewport, [Double](repeating: 123, count: 6),
                           "a failed conversion cannot publish fabricated viewport geometry")
            for _ in 0..<4 { host.step(); host.frame() }
        }
    }

    func testNestedVerticalScrollersRealizeOnlyTheirVisibleIntersection() throws {
        try onUIThread {
            let host = WinUIRenderer.running(reducesMotion: true) {
                ScrollView {
                    VStack(spacing: 0) {
                        Text("Before").frame(height: 80)
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(0..<300) { number in
                                    Text("Row \(number)").frame(height: 28)
                                }
                            }
                        }.frame(height: 600)
                        Text("After").frame(height: 80)
                    }
                }.frame(width: 260, height: 220)
            }
            for _ in 0..<12 { host.step(); host.frame() }
            let scrolls = host.views(WinUIScrollView.self)
            let outer = try XCTUnwrap(scrolls.first)
            let inner = try XCTUnwrap(scrolls.dropFirst().first)
            let lazy = try XCTUnwrap(host.views(WinUILazyStackView.self).first)
            XCTAssertGreaterThan(inner.scroller.laidOutFrame.height, outer.scroller.laidOutFrame.height)

            inner.scroller.move(to: Point(0, 280))
            host.settle { abs(inner.scroller.standing.offset.y - 280) < 1 }
            for target in [0.0, 200, 500, 0] {
                let bounded = min(target, outer.scroller.standing.reach.y)
                outer.scroller.move(to: Point(0, target))
                host.settle { abs(outer.scroller.standing.offset.y - bounded) < 1 }
                for _ in 0..<10 { host.step(); host.frame() }

                let top = max(outer.scroller.origin.y, inner.scroller.origin.y)
                let bottom = min(outer.scroller.origin.y + outer.scroller.laidOutFrame.height,
                                 inner.scroller.origin.y + inner.scroller.laidOutFrame.height)
                let visibleHeight = max(0, bottom - top)
                XCTAssertGreaterThan(visibleHeight, 0)
                var viewport = [Double](repeating: .nan, count: 6)
                XCTAssertEqual(swiftomniui_winui_scroller_viewport(inner.scroller.handle, lazy.handle, &viewport),
                               SwiftOmniUIViewportReady)
                XCTAssertEqual(viewport[1], top - lazy.origin.y, accuracy: 1)
                XCTAssertEqual(viewport[3], visibleHeight, accuracy: 1)

                let span = try XCTUnwrap(lazy.span)
                XCTAssertEqual(span.upperBound - span.lowerBound, visibleHeight, accuracy: 1)
                // Deliver an old, larger EffectiveViewport after the ancestor
                // moved. It is a notification, not another geometry snapshot.
                lazy.viewportReported(Rect(viewport[0], viewport[1], viewport[2], 600))
                XCTAssertEqual(lazy.span?.upperBound, span.upperBound)
                XCTAssertEqual(lazy.span?.lowerBound, span.lowerBound)
                XCTAssertLessThan(lazy.mounted.count, 40,
                                  "the 600-DIP inner viewport must not replace its visible intersection")
                let built = lazy.cells.built
                let measurements = lazy.cells.measurements
                for _ in 0..<8 { host.step(); host.frame() }
                XCTAssertEqual(lazy.cells.built, built)
                XCTAssertEqual(lazy.cells.measurements, measurements,
                               "retelling unchanged geometry must preserve the clipped window")
            }
        }
    }

    func testFullyOffscreenNestedScrollerRetiresItsWindowAndResumesWithoutInnerScrolling() throws {
        try onUIThread {
            let host = WinUIRenderer.running(reducesMotion: true) {
                ScrollView {
                    VStack(spacing: 0) {
                        Text("Before").frame(height: 500)
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(0..<100) { number in Text("Row \(number)").frame(height: 28) }
                            }
                        }.frame(height: 300)
                        Text("After").frame(height: 500)
                    }
                }.frame(width: 260, height: 220)
            }
            for _ in 0..<12 { host.step(); host.frame() }
            let scrolls = host.views(WinUIScrollView.self)
            let outer = try XCTUnwrap(scrolls.first)
            let inner = try XCTUnwrap(scrolls.dropFirst().first)
            let lazy = try XCTUnwrap(host.views(WinUILazyStackView.self).first)
            for target in [500.0, 0, 500] {
                outer.scroller.move(to: Point(0, target))
                host.settle { abs(outer.scroller.standing.offset.y - target) < 1 }
                for _ in 0..<12 { host.step(); host.frame() }
                var viewport = [Double](repeating: .nan, count: 6)
                XCTAssertEqual(swiftomniui_winui_scroller_viewport(inner.scroller.handle, lazy.handle, &viewport),
                               SwiftOmniUIViewportReady)
                XCTAssertFalse(lazy.isWaitingForViewport,
                               "a ready empty intersection must not become an attachment request")
                XCTAssertEqual(inner.scroller.standing.offset.y, 0, accuracy: 1)
                if target == 0 {
                    XCTAssertEqual(viewport[3], 0)
                    XCTAssertNil(lazy.span)
                    XCTAssertTrue(lazy.cells.built.isEmpty)
                } else {
                    XCTAssertGreaterThan(viewport[3], 0)
                    XCTAssertNotNil(lazy.span)
                    XCTAssertFalse(lazy.cells.built.isEmpty)
                }
            }
        }
    }

    func testCompositionClipResizesChangeTheCurrentViewportWithoutScrolling() throws {
        try onUIThread {
            let height = State(wrappedValue: 180.0)
            let host = WinUIRenderer.running(reducesMotion: true) {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(0..<300) { number in Text("Row \(number)").frame(height: 28) }
                            }
                        }.frame(height: 600)
                    }
                    .frame(width: 260, height: height.wrappedValue)
                    .clipsContent(true)
                    .id("clip")
                    Spacer()
                }.frame(width: 300, height: 500)
            }
            let scroll = try XCTUnwrap(host.views(WinUIScrollView.self).first)
            let lazy = try XCTUnwrap(host.views(WinUILazyStackView.self).first)
            let clip = try XCTUnwrap(host.view(id: .manual("clip")))
            for expected in [180.0, 260, 0, 120, 180] {
                height.wrappedValue = expected
                for _ in 0..<12 { host.step(); host.frame() }
                XCTAssertEqual(clip.laidOutFrame.height, expected, accuracy: 1)
                XCTAssertGreaterThan(scroll.scroller.laidOutFrame.height, expected)
                var viewport = [Double](repeating: .nan, count: 6)
                XCTAssertEqual(swiftomniui_winui_scroller_viewport(scroll.scroller.handle, lazy.handle, &viewport),
                               SwiftOmniUIViewportReady)
                XCTAssertEqual(viewport[3], expected, accuracy: 1)
                if expected == 0 {
                    XCTAssertNil(lazy.span)
                    XCTAssertTrue(lazy.cells.built.isEmpty)
                } else {
                    let span = try XCTUnwrap(lazy.span)
                    XCTAssertEqual(span.upperBound - span.lowerBound, expected, accuracy: 1)
                }
                XCTAssertFalse(lazy.isWaitingForViewport)
                XCTAssertLessThan(lazy.mounted.count, 40)
            }
        }
    }

    func testZeroWidthClipMakesAVerticalLazyWindowEmpty() throws {
        try onUIThread {
            let width = State(wrappedValue: 180.0)
            let host = WinUIRenderer.running(reducesMotion: true) {
                VStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(0..<100) { number in Text("Row \(number)").frame(height: 28) }
                        }
                    }.frame(width: 260, height: 220)
                }
                .frame(width: width.wrappedValue, height: 220)
                .clipsContent(true)
            }
            let scroll = try XCTUnwrap(host.views(WinUIScrollView.self).first)
            let lazy = try XCTUnwrap(host.views(WinUILazyStackView.self).first)
            for expected in [180.0, 0, 180] {
                width.wrappedValue = expected
                for _ in 0..<12 { host.step(); host.frame() }
                var viewport = [Double](repeating: .nan, count: 6)
                XCTAssertEqual(swiftomniui_winui_scroller_viewport(scroll.scroller.handle, lazy.handle, &viewport),
                               SwiftOmniUIViewportReady)
                XCTAssertEqual(viewport[2], expected, accuracy: 1)
                XCTAssertFalse(lazy.isWaitingForViewport)
                if expected == 0 {
                    XCTAssertNil(lazy.span, "both axes must intersect, even for a vertical container")
                    XCTAssertTrue(lazy.cells.built.isEmpty)
                } else {
                    XCTAssertNotNil(lazy.span)
                    XCTAssertFalse(lazy.cells.built.isEmpty)
                }
            }
        }
    }
}
