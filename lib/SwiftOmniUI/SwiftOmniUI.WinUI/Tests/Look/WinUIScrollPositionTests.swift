// SPDX-FileCopyrightText: 2026 Pawe? Krzywdzi?ski and Contributors
// SPDX-License-Identifier: Apache-2.0

import Foundation
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import SwiftOmniUIConformance
import XCTest

final class WinUIScrollPositionTests: XCTestCase {
    func testScrollPositionModifierScopesToTheScrollViewWithTheModifier() {
        onUIThread {
            let position = State(wrappedValue: ScrollPosition(edge: .bottom))
            let host = WinUIRenderer.running(reducesMotion: true) {
                ScrollView { Text("content").frame(height: 1000) }
                    .scrollPosition(position.projectedValue)
                    .frame(width: 240, height: 200)
            }
            XCTAssertEqual(host.views(WinUIScrollView.self).count, 1)
            XCTAssertFalse(position.wrappedValue.isPositionedByUser)
        }
    }

    func testOnScrollGeometryChangeReportsContainerSizeAndContentUpdates() {
        onUIThread {
            let clock = TestClock()
            var reportedWidths: [(CGFloat, CGFloat)] = []
            var reportedOffsets: [(CGFloat, CGFloat)] = []
            let width = State(wrappedValue: 240.0)
            let position = State(wrappedValue: ScrollPosition())
            let host = WinUIRenderer.running(clock: clock, reducesMotion: true) {
                VStack {
                    Button("Wider").onClicked { width.wrappedValue = 320 }
                    Button("Scroll").onClicked { position.wrappedValue.scrollTo(x: 120) }
                    ScrollView(.horizontal) {
                        Text("wide content").frame(width: 800, height: 40)
                    }
                    .scrollPosition(position.projectedValue)
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        geometry.containerSize.width
                    } action: { old, new in
                        reportedWidths.append((old, new))
                    }
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        geometry.contentOffset.x
                    } action: { old, new in
                        reportedOffsets.append((old, new))
                    }
                    .frame(width: width.wrappedValue, height: 80)
                }
            }

            clock.now += 16
            host.frame()
            XCTAssertEqual(reportedWidths.count, 1)
            XCTAssertEqual(reportedWidths.first?.0 ?? -1, 0, accuracy: 0.5)
            XCTAssertEqual(reportedWidths.first?.1 ?? -1, 240, accuracy: 0.5)

            let buttons = host.views(WinUIButtonView.self)
            buttons[0].invoke()
            clock.now += 16
            host.frame()
            XCTAssertEqual(reportedWidths.count, 2)
            XCTAssertEqual(reportedWidths.last?.0 ?? -1, 240, accuracy: 0.5)
            XCTAssertEqual(reportedWidths.last?.1 ?? -1, 320, accuracy: 0.5)

            buttons[1].invoke()
            for _ in 0..<20 {
                WinUITestHost.pump(0.01)
                clock.now += 16
                host.frame()
                if (reportedOffsets.last?.1 ?? 0) >= 119 { break }
            }
            XCTAssertEqual(reportedOffsets.last?.0 ?? -1, 0, accuracy: 0.5)
            XCTAssertEqual(reportedOffsets.last?.1 ?? -1, 120, accuracy: 0.5)
        }
    }

    func testScrollPositionEdgeBottomWorksInsideViewModifierAndFollowsGrowth() {
        onUIThread {
            struct BottomPinnedModifier: ViewModifier {
                @State private var position = ScrollPosition(edge: .bottom)
                let onGeometry: (ScrollGeometry) -> Void
                func body(content: Content) -> some View {
                    content
                        .scrollPosition($position, anchor: .bottom)
                        .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height } action: { _, _ in }
                        .onScrollGeometryChange(for: CGFloat.self) { $0.visibleRect.maxY } action: { _, _ in }
                }
            }
            let clock = TestClock()
            let height = State(wrappedValue: 800.0)
            let host = WinUIRenderer.running(clock: clock, reducesMotion: true) {
                ScrollView {
                    Text("messages").frame(height: height.wrappedValue)
                }
                .modifier(BottomPinnedModifier { _ in })
                .frame(width: 240, height: 200)
            }
            for _ in 0..<20 {
                WinUITestHost.pump(0.01)
                clock.now += 16
                host.frame()
                if let scroll = host.views(WinUIScrollView.self).first,
                   scroll.scroller.standing.offset.y >= 590 { break }
            }
            let scroll = host.views(WinUIScrollView.self).first
            XCTAssertNotNil(scroll)
            XCTAssertGreaterThanOrEqual(scroll?.scroller.standing.offset.y ?? 0, 590,
                "first screen with ScrollPosition(edge: .bottom) in a ViewModifier must anchor at the bottom")

            height.wrappedValue = 1200.0
            for _ in 0..<20 {
                WinUITestHost.pump(0.01)
                clock.now += 16
                host.frame()
                if let scroll = host.views(WinUIScrollView.self).first,
                   scroll.scroller.standing.offset.y >= 990 { break }
            }
            XCTAssertGreaterThanOrEqual(scroll?.scroller.standing.offset.y ?? 0, 990,
                "growing content while pinned to .bottom must keep following the bottom edge")
        }
    }

    func testReplacingABottomPinnedConversationShowsItsFirstContentAtTheBottom() throws {
        try onUIThread {
            struct Conversation: View {
                let selection: Int
                @State private var position = ScrollPosition(edge: .bottom)

                var body: some View {
                    ScrollView {
                        LazyVStack {
                            ForEach(0..<(selection == 2 ? 1 : 40)) { row in
                                Text("Conversation \(selection), message \(row)")
                                    .frame(height: 28)
                                    .transition(.offset(y: 80))
                            }
                        }
                    }
                    .scrollPosition($position, anchor: .bottom)
                    .task { position.scrollTo(edge: .bottom) }
                }
            }

            let selection = State(wrappedValue: 0)
            let host = WinUIRenderer.running {
                VStack {
                    Conversation(selection: selection.wrappedValue)
                        .id(selection.wrappedValue)
                }
                .overlay(alignment: .top) {
                    Text("Selected \(selection.wrappedValue)")
                        .offset(x: Double(selection.wrappedValue) * 12)
                        .animation(.snappy, value: selection.wrappedValue)
                }
            }
            for value in [1, 2] {
                let previous = try XCTUnwrap(host.views(WinUIScrollView.self).first)
                selection.wrappedValue = value
                var visible = false
                for _ in 0..<40 {
                    host.step()
                    host.frame()
                    guard let scroll = host.views(WinUIScrollView.self).first,
                          scroll !== previous, scroll.scroller.laidOutFrame.height > 0,
                          scroll.scroller.drawnOpacity > 0 else { continue }
                    let standing = scroll.scroller.standing
                    if value == 1 { XCTAssertGreaterThan(standing.reach.y, 0) }
                    XCTAssertEqual(standing.offset.y, standing.reach.y, accuracy: 1)
                    visible = true
                    break
                }
                XCTAssertTrue(visible, "the new conversation must become visible, including when it fits")
            }
        }
    }
}
