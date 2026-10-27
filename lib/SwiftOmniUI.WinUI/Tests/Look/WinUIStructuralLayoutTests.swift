// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import SwiftOmniUIConformance
import XCTest

@MainActor private final class IntrinsicProbe: WinUILayoutView {
    var intrinsicWidth = 40.0

    override func contentSize(width: Double?) -> LayoutSize {
        LayoutSize(width: intrinsicWidth, height: 40)
    }
}

final class WinUIStructuralLayoutTests: XCTestCase {
    func testPaddedFixedIconKeepsItsPlaceAndFilenameReclaimsHiddenActionsWidth() throws {
        try onUIThread {
            let hovered = State(wrappedValue: false)
            let host = WinUIRenderer.running(reducesMotion: true) {
                HStack(spacing: 8) {
                    Image(.symbol("\u{E8A5}"))
                        .frame(width: 16, height: 16)
                        .padding(.leading, 16)
                    Text("CSwiftOmniUIWinUI_header_with_a_long_filename")
                        .lineLimit(1)
                        .padding(.vertical, 4)
                        .layoutPriority(1)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    if hovered.wrappedValue {
                        HStack(spacing: 6) {
                            Button {} label: { Image(.symbol("\u{E710}")).frame(width: 18, height: 18) }
                                .buttonStyle(.plain)
                            Button {} label: { Image(.symbol("\u{E7A7}")).frame(width: 18, height: 18) }
                                .buttonStyle(.plain)
                        }
                        .frame(width: 42, height: 18)
                        .id("hover-actions")
                    }
                    Text("M").frame(width: 16).id("status-marker")
                }
                .frame(width: 240, height: 28)
            }
            var originalTextX: Double?
            var originalTextWidth: Double?
            var originalStatusX: Double?
            for hovering in [false, true, false] {
                hovered.wrappedValue = hovering
                for _ in 0..<8 { host.step(); host.frame() }
                let text = try XCTUnwrap(host.views(WinUITextView.self).first {
                    $0.text.hasPrefix("CSwiftOmniUIWinUI_header")
                })
                let icon = try XCTUnwrap(host.views(WinUIImageView.self).first)
                let status = try XCTUnwrap(host.view(id: .manual("status-marker")))
                XCTAssertEqual(icon.laidOutFrame.width, 16, accuracy: 0.5)
                XCTAssertGreaterThanOrEqual(text.origin.x, icon.origin.x + icon.laidOutFrame.width + 7)
                if hovering {
                    let actions = try XCTUnwrap(host.view(id: .manual("hover-actions")))
                    XCTAssertLessThanOrEqual(text.origin.x + text.laidOutFrame.width, actions.origin.x - 7)
                } else {
                    XCTAssertNil(host.view(id: .manual("hover-actions")))
                    XCTAssertLessThanOrEqual(text.origin.x + text.laidOutFrame.width, status.origin.x - 7)
                }
                if let originalTextX, let originalTextWidth, let originalStatusX {
                    XCTAssertEqual(text.origin.x, originalTextX, accuracy: 0.5)
                    XCTAssertEqual(status.origin.x, originalStatusX, accuracy: 0.5)
                    // Hiding the action group returns its 42-point slot and
                    // the additional 8-point inter-child gap to the filename.
                    XCTAssertEqual(text.laidOutFrame.width, originalTextWidth - (hovering ? 50 : 0), accuracy: 0.5)
                } else {
                    originalTextX = text.origin.x
                    originalTextWidth = text.laidOutFrame.width
                    originalStatusX = status.origin.x
                }
            }
        }
    }

    func testSameChildWithNewMeasurementRevisionInvalidatesItsParent() {
        onUIThread {
            let parent = WinUIStackView(axis: .horizontal)
            let child = IntrinsicProbe()
            XCTAssertTrue(parent.setItems([WinUILayoutItem(view: child)]))
            let first = parent.naturalSize(width: 240)
            let revision = parent.measurementRevision

            child.intrinsicWidth = 80
            child.invalidateMeasure()
            XCTAssertTrue(parent.setItems([WinUILayoutItem(view: child)]))
            XCTAssertGreaterThan(parent.measurementRevision, revision)
            XCTAssertGreaterThan(parent.naturalSize(width: 240).width, first.width)
            XCTAssertTrue(parent.items.first?.view === child)
        }
    }

    func testSwitchingButtonGroupsReflowsFlexibleSiblingInBothDirections() throws {
        try onUIThread {
            let stacked = State(wrappedValue: false)
            let host = WinUIRenderer.running(reducesMotion: true) {
                HStack(spacing: 0) {
                    Rectangle().fill(Color.clear).frame(width: 40, height: 40)
                    Rectangle().fill(Color.clear).frame(maxWidth: .infinity).id("editor-space")
                    if stacked.wrappedValue {
                        VStack(spacing: 0) {
                            Button {} label: { Rectangle().fill(Color.red).frame(width: 40, height: 40) }
                                .id("first-button")
                            Button {} label: { Rectangle().fill(Color.blue).frame(width: 40, height: 40) }
                                .id("second-button")
                        }
                    } else {
                        HStack(spacing: 0) {
                            Button {} label: { Rectangle().fill(Color.red).frame(width: 40, height: 40) }
                                .id("first-button")
                            Button {} label: { Rectangle().fill(Color.blue).frame(width: 40, height: 40) }
                                .id("second-button")
                        }
                    }
                }
                .frame(width: 320)
            }
            for _ in 0..<8 { host.step(); host.frame() }
            let editor = try XCTUnwrap(host.view(id: .manual("editor-space")))
            let wideButtons = editor.placedFrame.width

            stacked.wrappedValue = true
            for _ in 0..<8 { host.step(); host.frame() }
            let narrowButtons = editor.placedFrame.width
            XCTAssertGreaterThan(narrowButtons, wideButtons + 30)
            for id in ["first-button", "second-button"] {
                let button = try XCTUnwrap(host.view(id: .manual(id)))
                XCTAssertTrue(button.isAttached)
                XCTAssertGreaterThan(button.laidOutFrame.width, 0)
            }

            stacked.wrappedValue = false
            for _ in 0..<8 { host.step(); host.frame() }
            XCTAssertEqual(editor.placedFrame.width, wideButtons, accuracy: 1)
            for id in ["first-button", "second-button"] {
                let button = try XCTUnwrap(host.view(id: .manual(id)))
                XCTAssertTrue(button.isAttached)
                XCTAssertGreaterThan(button.laidOutFrame.width, 0)
            }
        }
    }

    func testLazyExtentEditsUpdateNativeScrollReachAndKeepVisibleRows() throws {
        try onUIThread {
            let count = State(wrappedValue: 100)
            let rowHeight = State(wrappedValue: 32.0)
            let host = WinUIRenderer.running(reducesMotion: true) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(0..<count.wrappedValue) { index in
                            Text("Row \(index)").frame(height: rowHeight.wrappedValue)
                        }
                    }
                }.frame(width: 320, height: 180)
            }
            for _ in 0..<12 { host.step(); host.frame() }
            let scroll = try XCTUnwrap(host.views(WinUIScrollView.self).first)
            let lazy = try XCTUnwrap(host.views(WinUILazyStackView.self).first)
            let originalReach = scroll.scroller.standing.reach.y

            rowHeight.wrappedValue = 80
            for _ in 0..<12 { host.step(); host.frame() }
            XCTAssertGreaterThan(scroll.scroller.standing.reach.y, originalReach + 100,
                                 "changing mounted row height must refresh the native thumb")
            rowHeight.wrappedValue = 32
            for _ in 0..<12 { host.step(); host.frame() }

            count.wrappedValue = 200
            for _ in 0..<12 { host.step(); host.frame() }
            let expandedReach = scroll.scroller.standing.reach.y
            XCTAssertGreaterThan(expandedReach, originalReach + 1_000)
            scroll.scroller.move(to: Point(x: 0, y: expandedReach))
            for _ in 0..<12 { host.step(); host.frame() }
            XCTAssertFalse(lazy.mounted.isEmpty)

            count.wrappedValue = 100
            for _ in 0..<12 { host.step(); host.frame() }
            XCTAssertLessThan(scroll.scroller.standing.reach.y, expandedReach - 1_000)
            XCTAssertFalse(lazy.mounted.isEmpty)
        }
    }
}
