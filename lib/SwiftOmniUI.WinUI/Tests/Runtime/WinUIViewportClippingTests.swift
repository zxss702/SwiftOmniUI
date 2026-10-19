// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

final class WinUIViewportClippingTests: XCTestCase {
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
