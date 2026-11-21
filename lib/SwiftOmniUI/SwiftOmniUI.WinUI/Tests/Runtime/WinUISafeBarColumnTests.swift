// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import SwiftOmniUIConformance
import WinSDK
import XCTest

@MainActor private final class NativePageOwner: WinUILayoutView {
    var arrangementRequests = 0
    override func invalidateArrange() {
        arrangementRequests += 1
        super.invalidateArrange()
    }
}

private struct TitleBarBackgroundScrollPane: View {
    var body: some View {
        ScrollView { Color.clear.frame(height: 1800) }
            .id("title-background-detail-scroll")
            .safeAreaInset(edge: .top, spacing: 0) {
                Text("Header").frame(height: 44)
            }
            .frame(width: 220)
    }
}

final class WinUISafeBarColumnTests: XCTestCase {
    func testClearTitleBarContinuesEachScrollBackgroundAtTheTop() throws {
        try onUIThread {
            let host = WinUIRenderer.running(reducesMotion: true, room: WinUITestHost.wideRoom) {
                NavigationSplitView(Binding(get: { true }, set: { _ in })) {
                    Color.clear.navigationSplitViewColumnWidth(220)
                } detail: {
                    NavigationStack {
                        GeometryReader { _ in
                            HStack(spacing: 0) {
                                ScrollView { Color.clear.frame(height: 1800) }
                                    .background(Color("#FF0000"))
                                    .id("title-background-main-scroll")
                                TitleBarBackgroundScrollPane()
                                    .overlay(alignment: .leading) { Color.clear.frame(width: 1) }
                                    .background(Color("#0000FF"))
                            }
                        }
                    }
                }
            }
            let window = try XCTUnwrap(host.window)
            let title = "SOUI clear title bar regression"
            window.setTitle(title)
            let nativeTitle = Array(title.utf16) + [0]
            let hwnd = try XCTUnwrap(nativeTitle.withUnsafeBufferPointer { FindWindowW(nil, $0.baseAddress) })
            let flags = UINT(SWP_NOACTIVATE | SWP_NOSIZE)
            XCTAssertTrue(SetWindowPos(hwnd, HWND(bitPattern: -1), 32, 32, 0, 0, flags))
            defer { _ = SetWindowPos(hwnd, HWND(bitPattern: -2), 32, 32, 0, 0, flags) }
            let main = try XCTUnwrap(host.view(id: .manual("title-background-main-scroll")) as? WinUIScrollView)
            let detail = try XCTUnwrap(host.view(id: .manual("title-background-detail-scroll")) as? WinUIScrollView)
            let expected: [UInt32] = [0xFFFF_0000, 0xFF00_00FF]
            let points: [(Double, Double)] = [(450, 15), (825, 15)]
            host.settle { window.titleBar.presentedPixels(at: points, in: window) == expected }
            XCTAssertEqual(main.scroller.standing.offset.y, 0, accuracy: 0.01)
            XCTAssertEqual(detail.scroller.standing.offset.y, 0, accuracy: 0.01)
            XCTAssertEqual(window.titleBar.presentedPixels(at: points, in: window), expected)
            XCTAssertEqual(window.titleBar.presentedPixels(at: points.map { ($0.0, $0.1 + 110) }, in: window), expected)
            XCTAssertFalse(swiftomniui_winui_window_material_covers(window.handle, window.titleBar.handle))
        }
    }

    func testTitleBarBackgroundVisibilityControlsNativeMaterial() throws {
        try onUIThread {
            let visibility = State(wrappedValue: SwiftOmniUICore.Visibility.automatic)
            let host = WinUIRenderer.running(reducesMotion: true) {
                NavigationStack {
                    Text("No scrolling content")
                        .toolbarBackground(visibility.wrappedValue, for: .windowToolbar)
                }
            }
            let window = try XCTUnwrap(host.window)
            for value in [SwiftOmniUICore.Visibility.automatic, .visible, .hidden, .automatic] {
                visibility.wrappedValue = value
                for _ in 0..<8 { host.step(); host.frame() }
                XCTAssertEqual(window.titleBar.chrome.backgroundVisibility, value)
                XCTAssertEqual(swiftomniui_winui_window_material_covers(window.handle, window.titleBar.handle),
                               value == .visible)
            }
        }
    }

    func testPopoverSafeBarSharesTheCardBackground() throws {
        try onUIThread {
            let open = State(wrappedValue: false)
            let host = WinUIRenderer.running(reducesMotion: true) {
                Button("Open") { open.wrappedValue = true }
                    .popover(isPresented: open.projectedValue, arrowEdge: .bottom) {
                        ScrollView { Color.clear.frame(height: 360) }
                            .frame(width: 220, height: 160)
                            .safeAreaInset(edge: .top, spacing: 0) {
                                Color.clear.frame(height: 40)
                            }
                    }
            }
            let window = try XCTUnwrap(host.window)
            window.setBackground(.color(red: 255, green: 0, blue: 255, alpha: 255))
            let title = "SOUI popover backdrop regression"
            window.setTitle(title)
            let nativeTitle = Array(title.utf16) + [0]
            let hwnd = try XCTUnwrap(nativeTitle.withUnsafeBufferPointer { FindWindowW(nil, $0.baseAddress) })
            let flags = UINT(SWP_NOACTIVATE | SWP_NOSIZE)
            XCTAssertTrue(SetWindowPos(hwnd, HWND(bitPattern: -1), 32, 32, 0, 0, flags))
            defer { _ = SetWindowPos(hwnd, HWND(bitPattern: -2), 32, 32, 0, 0, flags) }

            open.wrappedValue = true
            host.settle { host.views(WinUIPopoverView.self).first?.isAttached == true }
            let card = try XCTUnwrap(host.views(WinUIPopoverView.self).first)
            guard card.isAttached && card.showsCard else {
                return XCTFail("the popover must be visible before checking its backdrop")
            }
            let points: [(Double, Double)] = [(100, 30), (100, 50)]
            @MainActor func shareBackground(_ pixels: [UInt32]) -> Bool {
                guard pixels.count == 2 else { return false }
                // The acrylic texture itself can vary slightly across pixels.
                return [0, 8, 16].allSatisfy { shift in
                    abs(Int((pixels[0] >> shift) & 0xff) - Int((pixels[1] >> shift) & 0xff)) <= 16
                }
            }
            host.settle { shareBackground(card.presentedPixels(at: points, in: window)) }
            let pixels = card.presentedPixels(at: points, in: window)
            XCTAssertTrue(shareBackground(pixels), "bar and body should show the same popover backdrop: \(pixels)")
        }
    }

    func testNavigationColumnsCropBeforeFilteringAndMergeOnlyTheirOwnBars() throws {
        try onUIThread {
            let detailShown = State(wrappedValue: true)
            let host = WinUIRenderer.running(reducesMotion: true, room: WinUITestHost.wideRoom) {
                NavigationSplitView {
                    ScrollView { Color.red.frame(height: 1800) }.id("partition-sidebar")
                        .safeAreaInset(edge: .top, spacing: 0) {
                            Text("Inner").frame(height: 32).id("partition-inner-bar")
                        }
                        .safeAreaInset(edge: .top, spacing: 0) {
                            Text("Outer").frame(height: 44).id("partition-outer-bar")
                        }
                        .navigationSplitViewColumnWidth(220)
                } content: {
                    NavigationStack {
                        ScrollView { Color.green.frame(height: 1800) }.id("partition-content")
                    }
                } detail: {
                    ScrollView { Color.blue.frame(height: 1800) }.id("partition-detail")
                        .navigationSplitViewColumnWidth(detailShown.wrappedValue ? 280 : 0)
                }
            }
            for shown in [true, false, true] {
                detailShown.wrappedValue = shown
                for _ in 0..<8 { host.step(); host.frame() }
                let window = try XCTUnwrap(host.window)
                @MainActor func followsColumn(_ id: String) -> Bool {
                    guard let view = host.view(id: .manual(id)) else { return false }
                    return swiftomniui_winui_window_material_follows_column(window.handle, view.handle)
                }
                host.settle {
                    followsColumn("partition-sidebar") && followsColumn("partition-content")
                        && followsColumn("partition-detail") == shown
                }
                @MainActor func crop(_ id: String) throws -> [Double] {
                    let view = try XCTUnwrap(host.view(id: .manual(id)))
                    var rect = [Double](repeating: 0, count: 4)
                    XCTAssertTrue(swiftomniui_winui_window_material_sampling_bounds(window.handle, view.handle, &rect))
                    XCTAssertEqual(rect[1], 0, accuracy: 0.01, "each column includes its slice of toolbar")
                    XCTAssertGreaterThan(rect[2], 0)
                    XCTAssertTrue(swiftomniui_winui_window_material_follows_column(window.handle, view.handle),
                                  "toolbar pixels must inherit the page's native slot animation and lifetime")
                    return rect
                }
                let sidebar = try crop("partition-sidebar")
                XCTAssertEqual(try crop("partition-inner-bar"), sidebar)
                XCTAssertEqual(try crop("partition-outer-bar"), sidebar)
                let content = try crop("partition-content")
                XCTAssertLessThanOrEqual(sidebar[0] + sidebar[2], content[0] + 1,
                                         "the sidebar must be cropped out of the main column's filter input")
                if shown {
                    let detail = try crop("partition-detail")
                    XCTAssertLessThanOrEqual(content[0] + content[2], detail[0] + 1,
                                             "trailing detail cannot enter the main column's Gaussian kernel")
                } else {
                    let detail = try XCTUnwrap(host.view(id: .manual("partition-detail")))
                    var retired = [Double](repeating: 0, count: 4)
                    XCTAssertFalse(swiftomniui_winui_window_material_sampling_bounds(window.handle, detail.handle, &retired),
                                   "closing detail must retire its retained toolbar filter")
                    XCTAssertFalse(swiftomniui_winui_window_material_follows_column(window.handle, detail.handle))
                    let fullWidth = try XCTUnwrap(window.content).laidOutFrame.width
                    XCTAssertEqual(content[0] + content[2], fullWidth, accuracy: 1,
                                   "main content must replace the closed detail's toolbar slice")
                }
            }
        }
    }

    func testSidebarToolbarMaterialIsOwnedByTheNativeAnimatedPane() throws {
        try onUIThread {
            let shown = State(wrappedValue: true)
            // Keep real native transitions enabled. Ownership must be correct
            // during opening/closing, not repaired after an animation timeout.
            let host = WinUIRenderer.running(room: WinUITestHost.wideRoom) {
                NavigationSplitView(shown.projectedValue) {
                    ScrollView { Text("Files").frame(height: 1800) }.id("animated-pane-source")
                        .safeAreaInset(edge: .top, spacing: 0) {
                            Text("Tabs").frame(height: 48)
                        }
                        .navigationSplitViewColumnWidth(220)
                } detail: {
                    ScrollView { Text("Conversation").frame(height: 1800) }.id("animated-main-source")
                }
            }
            let window = try XCTUnwrap(host.window)
            let pane = try XCTUnwrap(host.view(id: .manual("animated-pane-source")))
            let main = try XCTUnwrap(host.view(id: .manual("animated-main-source")))
            for open in [true, false, true, false, true] {
                shown.wrappedValue = open
                host.step(); host.layOut(); host.frame()
                XCTAssertTrue(swiftomniui_winui_window_material_follows_column(window.handle, pane.handle),
                              "pane and toolbar material must share the native PaneRoot's moving clip and visibility")
                XCTAssertTrue(swiftomniui_winui_window_material_follows_column(window.handle, main.handle),
                              "main toolbar slice must follow ContentRoot rather than a stationary window overlay")
            }
        }
    }

    func testSlidingSafeBarBlursThePresentedContent() throws {
        try onUIThread {
            let clock = TestClock()
            let shown = State(wrappedValue: false)
            let blue = State(wrappedValue: false)
            let position = State(wrappedValue: ScrollPosition(edge: .bottom))
            let host = WinUIRenderer.running(clock: clock, room: WinUITestHost.wideRoom) {
                NavigationSplitView(Binding(get: { true }, set: { _ in })) {
                    Text("Files").navigationSplitViewColumnWidth(220)
                } detail: {
                    NavigationStack {
                        GeometryReader { _ in
                            HStack(spacing: 0) {
                                ScrollView { Color.red.frame(height: 1800) }
                                if shown.wrappedValue {
                                    VStack {
                                        ScrollView {
                                            LazyVStack(spacing: 0) {
                                                ForEach(0..<80, id: \.self) { _ in
                                                    HStack(spacing: 0) {
                                                        Color(blue.wrappedValue ? "#0000FF" : "#FF0000").frame(width: 16)
                                                        Color.black
                                                    }.frame(height: 28)
                                                }
                                            }
                                        }
                                        .scrollPosition(position.projectedValue, anchor: .bottom)
                                        .onAppear { position.wrappedValue.scrollTo(edge: .bottom) }
                                        .id("sliding-group-scroll")
                                    }
                                        .safeAreaInset(edge: .top, spacing: 0) {
                                            ScrollView(.horizontal) {
                                                HStack(spacing: 0) {
                                                    Color.clear.frame(width: 64)
                                                    Text("Group chat")
                                                }.frame(height: 40)
                                            }
                                            .id("sliding-group-bar")
                                        }
                                        .frame(width: 240)
                                        .transition(.offset(x: 240))
                                        .id("sliding-group")
                                }
                            }
                        }
                    }
                }
            }
            let window = try XCTUnwrap(host.window)
            host.frame()
            let start = clock.now
            withAnimation(.linear(duration: 0.2)) { shown.wrappedValue = true }
            host.runtime.pump.turn()
            host.frame()
            func edgeIsBlurred(_ pixels: [UInt32], blue: Bool = false) -> Bool {
                guard pixels.count == 2 else { return false }
                let shift = blue ? 0 : 16
                let channel = pixels.map { Int(($0 >> shift) & 255) }
                let neutralShift = blue ? 16 : 0
                return channel[0] < 248 && channel[1] > 8 && channel[0] > channel[1]
                    && pixels.allSatisfy {
                        let neutral = Int(($0 >> neutralShift) & 255)
                        return (0...68).contains(neutral) && abs(neutral - Int(($0 >> 8) & 255)) <= 1
                    }
            }
            var movingSamples = 0
            var didSeePane = false
            for elapsed in [32.0, 64, 96, 128, 160, 192, 224, 256, 320] {
                clock.now = start + elapsed
                host.frame()
                let panel = try XCTUnwrap(host.view(id: .manual("sliding-group")))
                let bar = try XCTUnwrap(host.view(id: .manual("sliding-group-bar")))
                let scroll = try XCTUnwrap(host.view(id: .manual("sliding-group-scroll")) as? WinUIScrollView)
                let room = try XCTUnwrap(window.content).laidOutFrame.width
                if room - scroll.scroller.origin.x <= 1 { continue }
                if !didSeePane {
                    didSeePane = true
                    host.settle {
                        let standing = scroll.scroller.standing
                        return standing.reach.y > 0 && abs(standing.reach.y - standing.offset.y) < 1
                    }
                }
                let standing = scroll.scroller.standing
                XCTAssertGreaterThan(standing.reach.y, 0)
                XCTAssertEqual(standing.offset.y, standing.reach.y, accuracy: 1)
                let visible = room - scroll.scroller.origin.x
                let sample = "\(elapsed) ms, visible width \(visible), panel \(panel.origin), viewport \(scroll.scroller.origin), offset \(standing.offset.y)"
                if visible > 36 {
                    if panel.drawing.translationX > 1 { movingSamples += 1 }
                    let points = [(14.0, 20.0), (18.0, 20.0)]
                    WinUITestHost.pump(0.035) // Present this sample while the test animation clock is held.
                    XCTAssertTrue(edgeIsBlurred(bar.presentedPixels(at: points, in: window)), sample)
                    // Stay clear of the window caption buttons when sampling the toolbar.
                    if visible > 180 {
                        let edgeX = scroll.scroller.origin.x - window.titleBar.origin.x
                        let titlePoints = [(edgeX + 14, 20.0), (edgeX + 18, 20.0)]
                        XCTAssertTrue(edgeIsBlurred(window.titleBar.presentedPixels(at: titlePoints, in: window)), sample)
                    }
                    XCTAssertEqual(scroll.scroller.presentedPixels(at: [(14, 140), (18, 140)], in: window),
                                   [0xffff0000, 0xff000000], sample)
                }
            }
            XCTAssertGreaterThan(movingSamples, 1, "Exercise the material while the pane is visible and still sliding.")
            let bar = try XCTUnwrap(host.view(id: .manual("sliding-group-bar")))
            XCTAssertTrue(swiftomniui_winui_window_material_covers(window.handle, bar.presentationHandle))
            let scroll = try XCTUnwrap(host.view(id: .manual("sliding-group-scroll")) as? WinUIScrollView)
            blue.wrappedValue = true // Change just the pixels beneath the stationary bar.
            let points = [(14.0, 20.0), (18.0, 20.0)]
            host.settle { edgeIsBlurred(bar.presentedPixels(at: points, in: window), blue: true) }
            XCTAssertTrue(edgeIsBlurred(bar.presentedPixels(at: points, in: window), blue: true))
            position.wrappedValue.scrollTo(edge: .top)
            host.settle {
                abs(scroll.scroller.standing.offset.y) < 0.5
                    && swiftomniui_winui_window_material_covers(window.handle, bar.presentationHandle)
            }
            XCTAssertEqual(scroll.scroller.standing.offset.y, 0, accuracy: 0.5)
            XCTAssertTrue(swiftomniui_winui_window_material_covers(window.handle, bar.presentationHandle))
        }
    }

    func testNestedBarsKeepTheSameTranslucentSourceAcrossScrollCycles() throws {
        try onUIThread {
            let host = WinUIRenderer.running(reducesMotion: true, room: WinUITestHost.wideRoom) {
                NavigationStack {
                    ScrollView {
                        HStack(spacing: 0) {
                            Color("#FF0000").opacity(0.5).frame(width: 120)
                            Color("#0000FF").opacity(0.5).frame(width: 120)
                        }.frame(height: 1800)
                    }
                    .id("translucent-scroll")
                    .safeAreaInset(edge: .top, spacing: 0) {
                        Color.clear.frame(height: 36).id("history-search-bar")
                    }
                    .safeAreaInset(edge: .top, spacing: 0) {
                        Color.clear.frame(height: 36).id("history-tabs-bar")
                    }
                    .frame(width: 240)
                }
            }
            let window = try XCTUnwrap(host.window)
            let scroll = try XCTUnwrap(host.view(id: .manual("translucent-scroll")) as? WinUIScrollView)
            let search = try XCTUnwrap(host.view(id: .manual("history-search-bar")))
            let tabs = try XCTUnwrap(host.view(id: .manual("history-tabs-bar")))
            func blueMinusRed(_ pixel: UInt32) -> Int {
                Int(pixel & 255) - Int((pixel >> 16) & 255)
            }
            // Both probes straddle the same hard edge. The flat patches also
            // expose a second source-over pass on the half-transparent column.
            let xs = [94.0, 118.0, 122.0, 146.0]
            for offset in [180.0, 0, 220, 0, 180] {
                scroll.scroller.move(to: Point(0, offset))
                host.settle {
                    abs(scroll.scroller.standing.offset.y - offset) < 1
                        && [search, tabs].allSatisfy {
                            swiftomniui_winui_window_material_covers(window.handle, $0.presentationHandle)
                        }
                }
                XCTAssertEqual(scroll.scroller.standing.offset.y, offset, accuracy: 1)
                for bar in [search, tabs] {
                    XCTAssertTrue(swiftomniui_winui_window_material_covers(window.handle, bar.presentationHandle))
                }
                // At rest the safe inset can put the first row below both bars.
                guard offset > 0 else { continue }
                // Sample the settled tint after the native opacity transition.
                WinUITestHost.pump(0.30)
                let base = scroll.scroller.presentedPixels(at: xs.map { ($0, 160) }, in: window).map(blueMinusRed)
                XCTAssertEqual(base.count, 4)
                guard base.count == 4 else { return }
                XCTAssertGreaterThan(base[2] - base[1], 32)
                for bar in [search, tabs] {
                    let dx = scroll.scroller.origin.x - bar.origin.x
                    let pixels = bar.presentedPixels(at: xs.map { ($0 + dx, 18) }, in: window).map(blueMinusRed)
                    XCTAssertEqual(pixels.count, 4)
                    guard pixels.count == 4 else { return }
                    // Subtract the local background to tolerate a gradient in the native Mica.
                    let relativeContrast = Double(pixels[3] - pixels[0]) / Double(base[3] - base[0])
                    XCTAssertTrue((0.71...0.79).contains(relativeContrast) || (0.90...0.97).contains(relativeContrast),
                                  "Joined bars should apply one translucent white tint")
                    XCTAssertLessThan(pixels[2] - pixels[1], base[2] - base[1] - 4)
                }
            }
        }
    }

    func testSidebarSafeBarFollowsAncestorDepartureWithoutLayoutSamples() throws {
        try onUIThread {
            let clock = TestClock()
            let history = State(wrappedValue: false)
            let host = WinUIRenderer.running(clock: clock, room: WinUITestHost.wideRoom) {
                NavigationSplitView(Binding(get: { true }, set: { _ in })) {
                    ZStack {
                        if history.wrappedValue {
                            VStack(spacing: 0) {
                                ScrollView { Text("History rows").frame(height: 1600) }
                            }
                            .safeAreaInset(edge: .top, spacing: 0) {
                                Text("Search history").frame(height: 48).id("history-material-bar")
                            }
                            .transition(.opacity)
                            .id("history-material-pane")
                        } else {
                            VStack(spacing: 0) {
                                ScrollView { Text("Changed files").frame(height: 1600) }
                            }
                            .safeAreaInset(edge: .bottom, spacing: 0) {
                                Color.red.frame(height: 150).id("git-material-bar")
                            }
                            .transition(.opacity)
                            .id("git-material-pane")
                        }
                    }.navigationSplitViewColumnWidth(260)
                } detail: {
                    Text("Conversation")
                }
            }
            for _ in 0..<4 { host.step(); host.frame() }
            let window = try XCTUnwrap(host.window)
            let oldBar = try XCTUnwrap(host.view(id: .manual("git-material-bar")))
            let height = oldBar.laidOutFrame.height
            XCTAssertGreaterThan(height, 0)
            XCTAssertTrue(swiftomniui_winui_window_material_covers(window.handle, oldBar.presentationHandle))
            let start = clock.now
            withAnimation(.eased(240, .linear)) { history.wrappedValue = true }
            host.step()
            host.layOut() // Mount the new branch once, then sample drawing only.
            for elapsed in [16.0, 64, 128, 200] {
                clock.now = start + elapsed
                host.runtime.displayCycle.frame(now: clock.now)
                XCTAssertEqual(swiftomniui_winui_opacity(oldBar.presentationHandle), 1, accuracy: 0.001,
                               "the opacity transition belongs to the ancestor, not the bar itself")
                XCTAssertTrue(oldBar.isAttached, "the original bar stays in the fading subtree")
                XCTAssertEqual(oldBar.laidOutFrame.height, height, accuracy: 1,
                               "leaving content keeps its layout allocation while its presentation fades")
            }
            clock.now = start + 600
            host.frame()
            let current = try XCTUnwrap(host.view(id: .manual("history-material-bar")))
            let historyScroll = try XCTUnwrap(host.views(WinUIScrollView.self).first)
            historyScroll.scroller.move(to: Point(0, 160))
            host.settle { swiftomniui_winui_window_material_covers(window.handle, current.presentationHandle) }
            XCTAssertTrue(oldBar.isDetached)
            XCTAssertFalse(swiftomniui_winui_window_material_covers(window.handle, oldBar.presentationHandle))
            XCTAssertTrue(swiftomniui_winui_window_material_covers(window.handle, current.presentationHandle),
                          "the new bar shows its backdrop over scrolled content")
        }
    }

    func testCommittedMaterialCoversSidebarAndExpertBarWithoutResize() throws {
        try onUIThread {
            let sidebarPage = State(wrappedValue: false)
            let showsDetail = State(wrappedValue: true)
            let host = WinUIRenderer.running(reducesMotion: true, room: WinUITestHost.wideRoom) {
                NavigationSplitView {
                    Group {
                        if sidebarPage.wrappedValue {
                            ScrollView { Text("History").frame(height: 1800) }
                                .frame(maxHeight: 620, alignment: .top)
                        } else {
                            ScrollView { Text("Files").frame(height: 1800) }
                                .frame(maxHeight: 620, alignment: .top)
                        }
                    }
                    .safeAreaInset(edge: .top, spacing: 0) {
                        Text("Sidebar tabs").frame(height: 48).id("material-sidebar-tabs")
                    }
                    .navigationSplitViewColumnWidth(220)
                } content: {
                    NavigationStack {
                        ScrollView { Text("Conversation").frame(height: 1800) }
                            .frame(maxHeight: 620, alignment: .top)
                    }
                } detail: {
                    ScrollView { Text("Expert actions").frame(height: 1800) }
                        .frame(maxHeight: 620, alignment: .top)
                        .safeAreaInset(edge: .top, spacing: 0) {
                            Button("Expert") {}.frame(height: 48).id("material-experts")
                        }
                        .navigationSplitViewColumnWidth(showsDetail.wrappedValue ? 280 : 0)
                }
            }
            for (page, detail) in [(false, true), (true, true), (false, false), (false, true)] {
                sidebarPage.wrappedValue = page
                showsDetail.wrappedValue = detail
                // Present native layout; deliberately never resize the window
                // or invoke a diagnostic which creates/refreshes a material.
                for _ in 0..<12 { host.step(); host.frame() }
                let window = try XCTUnwrap(host.window)
                for scroll in host.views(WinUIScrollView.self) where scroll.isAttached {
                    scroll.scroller.move(to: Point(0, 200))
                }
                let tabs = try XCTUnwrap(host.view(id: .manual("material-sidebar-tabs")))
                host.settle { swiftomniui_winui_window_material_covers(window.handle, tabs.presentationHandle) }
                XCTAssertTrue(swiftomniui_winui_window_material_covers(window.handle, tabs.presentationHandle),
                              "initial mount and sidebar replacement must commit the complete material region")
                if detail {
                    let experts = try XCTUnwrap(host.view(id: .manual("material-experts")))
                    host.settle { swiftomniui_winui_window_material_covers(window.handle, experts.presentationHandle) }
                    XCTAssertTrue(swiftomniui_winui_window_material_covers(window.handle, experts.presentationHandle),
                                  "the auxiliary detail's local selector joins the same region")
                }
            }
        }
    }

    func testHiddenLocalMaterialRemovesItsRegionWithoutChangingSafeInset() throws {
        try onUIThread {
            let hidden = State(wrappedValue: false)
            let host = WinUIRenderer.running(reducesMotion: true, room: WinUITestHost.wideRoom) {
                NavigationSplitView(Binding(get: { true }, set: { _ in })) {
                    Text("Sidebar").navigationSplitViewColumnWidth(220)
                } detail: {
                    VStack(spacing: 0) {
                        ScrollView { Text("Document").frame(height: 1800) }
                            .safeAreaInset(edge: .top, spacing: 0) {
                                Text("Local header").frame(height: 48).id("hidden-material-header")
                            }
                            .hiddenSafeBarBackground(hidden.wrappedValue)
                    }
                }
            }
            var initialY: Double?
            for hides in [false, true, false] {
                hidden.wrappedValue = hides
                for _ in 0..<12 { host.step(); host.frame() }
                let window = try XCTUnwrap(host.window)
                let header = try XCTUnwrap(host.view(id: .manual("hidden-material-header")))
                let scroll = try XCTUnwrap(host.views(WinUIScrollView.self).first)
                scroll.scroller.move(to: Point(0, 160))
                host.settle {
                    swiftomniui_winui_window_material_covers(window.handle, header.presentationHandle) == !hides
                }
                XCTAssertEqual(swiftomniui_winui_window_material_covers(window.handle, header.presentationHandle), !hides)
                if let initialY { XCTAssertEqual(header.origin.y, initialY, accuracy: 1) }
                else { initialY = header.origin.y }
            }
        }
    }

    func testConversationViewportAndMaterialSurviveAuxiliaryDetailToggle() throws {
        try onUIThread {
            let detail = State(wrappedValue: false)
            let host = WinUIRenderer.running(reducesMotion: true, room: WinUITestHost.wideRoom) {
                NavigationSplitView {
                    Text("Sidebar").navigationSplitViewColumnWidth(220)
                } content: {
                    NavigationStack {
                        GeometryReader { _ in
                            VStack(spacing: 0) {
                                ScrollView {
                                    VStack(spacing: 0) {
                                        Text("First message").frame(height: 32).id("conversation-first")
                                        Text("Long conversation").frame(height: 1800)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.white)
                            .safeAreaInset(edge: .bottom, spacing: 0) {
                                Text("Composer").frame(height: 72)
                            }
                        }
                    }
                } detail: {
                    Text("Agent actions").navigationSplitViewColumnWidth(detail.wrappedValue ? 280 : 0)
                }
            }
            for shown in [false, true, false, true, false] {
                detail.wrappedValue = shown
                for _ in 0..<12 { host.step(); host.frame() }
                let window = try XCTUnwrap(host.window)
                let scroll = try XCTUnwrap(host.views(WinUIScrollView.self).first)
                let first = try XCTUnwrap(host.view(id: .manual("conversation-first")))
                XCTAssertEqual(scroll.scroller.origin.y, window.titleBar.origin.y, accuracy: 1,
                               "GeometryReader must preserve the toolbar viewport in both native parent slots")
                XCTAssertGreaterThanOrEqual(first.origin.y, window.chromeHeight - 1,
                                           "initial messages still start below the safe top edge")

                let initial = first.origin.y
                for offset in [144.0, 0.0] {
                    scroll.scroller.move(to: Point(0, offset))
                    host.settle { abs(first.origin.y - (initial - offset)) < 1 }
                    XCTAssertEqual(first.origin.y, initial - offset, accuracy: 1)
                }
            }
        }
    }

    func testMaterialDoesNotRepaintTheOrdinarySidebarContent() throws {
        try onUIThread {
            let host = WinUIRenderer.running(reducesMotion: true, room: WinUITestHost.wideRoom) {
                NavigationSplitView(Binding(get: { true }, set: { _ in })) {
                    ScrollView {
                        Color.red.frame(height: 1600).id("sidebar-ink")
                    }
                    .safeAreaInset(edge: .top, spacing: 0) {
                        Text("Sidebar controls").frame(height: 48)
                    }
                    .navigationSplitViewColumnWidth(220)
                } detail: {
                    Text("Detail")
                }
            }
            for _ in 0..<12 { host.step(); host.frame() }
            let scroll = try XCTUnwrap(host.views(WinUIScrollView.self).first)
            let ink = try XCTUnwrap(host.view(id: .manual("sidebar-ink")))
            let y = ink.origin.y - scroll.origin.y + 12
            XCTAssertEqual(scroll.pixels(at: [(32, y)]), [0xFFFF_0000],
                           "a shared capture must leave the source content's original pixels intact")
        }
    }

    func testSplitAndMultiChildNavigationPageExposeTheViewportBeneathChrome() throws {
        try onUIThread {
            let host = WinUIRenderer.running(reducesMotion: true, room: WinUITestHost.wideRoom) {
                NavigationSplitView(Binding(get: { true }, set: { _ in })) {
                    Text("Sidebar").navigationSplitViewColumnWidth(220)
                } detail: {
                    NavigationStack {
                        VStack(spacing: 0) {
                            ScrollView {
                                VStack(spacing: 0) {
                                    Text("First").frame(height: 32).id("nested-first")
                                    Text("Document").frame(height: 1600)
                                }
                            }
                            Text("Footer").frame(height: 40)
                        }
                        .safeAreaInset(edge: .top, spacing: 0) {
                            Text("Header").frame(height: 44).id("nested-header")
                        }
                    }
                }
            }
            for _ in 0..<12 { host.step(); host.frame() }
            let window = try XCTUnwrap(host.window)
            let scroll = try XCTUnwrap(host.views(WinUIScrollView.self).first)
            let header = try XCTUnwrap(host.view(id: .manual("nested-header")))
            let first = try XCTUnwrap(host.view(id: .manual("nested-first")))
            XCTAssertGreaterThan(scroll.scroller.origin.x, 0, "the extended viewport stays in its detail column")
            XCTAssertEqual(scroll.scroller.origin.y, window.titleBar.origin.y, accuracy: 1)
            XCTAssertEqual(header.origin.y, window.chromeHeight, accuracy: 1,
                           "the promoted bar remains below the toolbar after its native page is extended")
            XCTAssertGreaterThanOrEqual(first.origin.y, header.origin.y + header.frame.height - 1)
            let initialY = first.origin.y
            for offset in [160.0, 0.0, 160.0, 0.0] {
                scroll.scroller.move(to: Point(0, offset))
                host.settle { abs(first.origin.y - (initialY - offset)) < 1 }
                XCTAssertEqual(first.origin.y, initialY - offset, accuracy: 1)
                XCTAssertEqual(header.origin.y, window.chromeHeight, accuracy: 1)
            }
        }
    }

    func testSideBySideScrollViewsControlTheirOwnSafeBarRegions() throws {
        try onUIThread {
            let host = WinUIRenderer.running(reducesMotion: true, room: WinUITestHost.wideRoom) {
                NavigationStack {
                    HStack(spacing: 20) {
                        ScrollView { Color.red.frame(height: 1800) }
                            .id("left-scroll")
                        ScrollView { Color.blue.frame(height: 1800) }
                            .id("right-scroll")
                    }
                    .safeAreaInset(edge: .top, spacing: 0) {
                        HStack(spacing: 20) {
                            Text("L").frame(width: 20).id("left-top").frame(maxWidth: .infinity)
                            Text("R").frame(width: 20).id("right-top").frame(maxWidth: .infinity)
                        }.frame(height: 48)
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        HStack(spacing: 20) {
                            Text("L").frame(width: 20).id("left-bottom").frame(maxWidth: .infinity)
                            Text("R").frame(width: 20).id("right-bottom").frame(maxWidth: .infinity)
                        }.frame(height: 48)
                    }
                }
            }
            for _ in 0..<12 { host.step(); host.frame() }
            let window = try XCTUnwrap(host.window)
            let left = try XCTUnwrap(host.view(id: .manual("left-scroll")) as? WinUIScrollView)
            let right = try XCTUnwrap(host.view(id: .manual("right-scroll")) as? WinUIScrollView)
            let probes = try ["left-top", "right-top", "left-bottom", "right-bottom"].map {
                try XCTUnwrap(host.view(id: .manual($0)))
            }
            @MainActor func expect(_ expected: [Bool]) {
                let read = {
                    probes.map { swiftomniui_winui_window_material_covers(window.handle, $0.presentationHandle) }
                }
                host.settle { read() == expected }
                XCTAssertEqual(read(), expected)
            }
            expect([false, false, true, true])
            left.scroller.move(to: Point(0, 200))
            expect([true, false, true, true])
            right.scroller.move(to: Point(0, 1800))
            expect([true, true, true, false])
            left.scroller.move(to: .zero)
            expect([false, true, true, false])
        }
    }

    func testToolbarMaterialSamplesPushedPageBackgroundAndReturnsToRoot() throws {
        try onUIThread {
            let path = State(wrappedValue: [Int]())
            let sidebar = State(wrappedValue: true)
            let host = WinUIRenderer.running(reducesMotion: true, room: WinUITestHost.wideRoom) {
                NavigationSplitView(sidebar.projectedValue) {
                    Text("Sidebar").navigationSplitViewColumnWidth(220)
                } detail: {
                    NavigationStack(path: path.projectedValue) {
                        ScrollView { Color("#FF0000").frame(height: 1600) }
                            .id("material-root-scroll")
                            .toolbarBackground(.visible, for: .windowToolbar)
                            .navigationDestination(for: Int.self) { _ in
                                Text("Preview")
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(Color("#00FF00"))
                                    .toolbarBackground(.visible, for: .windowToolbar)
                                    .id("material-preview")
                            }
                    }
                }
            }
            let window = try XCTUnwrap(host.window)
            let scroll = try XCTUnwrap(host.view(id: .manual("material-root-scroll")) as? WinUIScrollView)
            scroll.scroller.move(to: Point(0, 180))
            @MainActor func pixels() -> [UInt32] { window.titleBar.presentedPixels(at: [(520, 18)], in: window) }
            host.settle { pixels() == [0xffff0000] }
            XCTAssertEqual(pixels(), [0xffff0000])

            path.wrappedValue = [1]
            host.settle { pixels() == [0xff00ff00] }
            XCTAssertEqual(pixels(), [0xff00ff00])
            let preview = try XCTUnwrap(host.view(id: .manual("material-preview")) as? WinUILayoutView)
            let background = try XCTUnwrap(preview.boxView)
            XCTAssertEqual(background.origin.y, window.titleBar.origin.y, accuracy: 1)

            path.wrappedValue = []
            host.settle { pixels() == [0xffff0000] }
            XCTAssertEqual(pixels(), [0xffff0000])
        }
    }

    func testNavigationSlideKeepsSafeBarWithItsPage() throws {
        try onUIThread {
            guard swiftomniui_winui_animations_enabled() else { throw XCTSkip("System animations are off") }
            let path = State(wrappedValue: [Int]())
            let sourcePosition = State(wrappedValue: ScrollPosition(edge: .bottom))
            let host = WinUIRenderer.running(room: WinUITestHost.wideRoom) {
                NavigationSplitView(Binding(get: { true }, set: { _ in })) {
                    Text("Files").navigationSplitViewColumnWidth(220)
                } detail: {
                    NavigationStack(path: path.projectedValue) {
                        ScrollView { Color.red.frame(height: 1800) }
                            .scrollPosition(sourcePosition.projectedValue)
                            .frame(maxHeight: 620, alignment: .top)
                            .safeAreaInset(edge: .top, spacing: 0) {
                                Text("Source").frame(height: 40).frame(maxWidth: .infinity).id("slide-source-bar")
                            }
                            .navigationDestination(for: Int.self) { _ in
                                ScrollView { Color.blue.frame(height: 1800) }
                                    .frame(maxHeight: 620, alignment: .top)
                                    .safeAreaInset(edge: .top, spacing: 0) {
                                        Text("Destination").frame(height: 40).frame(maxWidth: .infinity).id("slide-destination-bar")
                                    }
                            }
                    }
                }
            }
            let window = try XCTUnwrap(host.window)
            let old = try XCTUnwrap(host.views(WinUIScrollView.self).first)
            let oldBar = try XCTUnwrap(host.view(id: .manual("slide-source-bar")))
            let landing = old.scroller.origin.x
            host.settle { swiftomniui_winui_window_material_covers(window.handle, oldBar.presentationHandle) }
            XCTAssertTrue(swiftomniui_winui_window_material_covers(window.handle, oldBar.presentationHandle),
                          "Source offset: \(old.scroller.standing.offset), bar: \(oldBar.origin) \(oldBar.frame)")

            path.wrappedValue = [1]
            host.runtime.pump.turn()
            let next = try XCTUnwrap(host.views(WinUIScrollView.self).first { $0 !== old })
            let nextBar = try XCTUnwrap(host.view(id: .manual("slide-destination-bar")))
            host.settle {
                next.scroller.origin.x - landing > 30
                    && next.scroller.isAttached
            }
            XCTAssertGreaterThan(next.scroller.origin.x - landing, 30, "Sample the page before it lands.")
            XCTAssertTrue(next.scroller.isAttached)
            XCTAssertTrue(old.scroller.isAttached)
            XCTAssertEqual(nextBar.origin.x, next.scroller.origin.x, accuracy: 1)

            host.settle { !old.scroller.isAttached }
            XCTAssertEqual(next.scroller.origin.x, landing, accuracy: 1)
            XCTAssertTrue(swiftomniui_winui_window_material_covers(window.handle, nextBar.presentationHandle))
            XCTAssertFalse(old.scroller.isAttached)
        }
    }

    func testScrolledNavigationDestinationDrawsItsPathBarWithItsBody() throws {
        try onUIThread {
            guard swiftomniui_winui_animations_enabled() else { throw XCTSkip("System animations are off") }
            let path = State(wrappedValue: [Int]())
            let position = State(wrappedValue: ScrollPosition(edge: .bottom))
            let host = WinUIRenderer.running(room: WinUITestHost.wideRoom) {
                NavigationSplitView(Binding(get: { true }, set: { _ in })) {
                    Text("Files").navigationSplitViewColumnWidth(220)
                } detail: {
                    NavigationStack(path: path.projectedValue) {
                        Color("#FF0000")
                            .navigationDestination(for: Int.self) { _ in
                                ScrollView {
                                    LazyVStack(spacing: 0) {
                                        ForEach(0..<200, id: \.self) { _ in Color("#0000FF").frame(height: 24) }
                                    }
                                }
                                .scrollPosition(position.projectedValue, anchor: .bottom)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .safeAreaInset(edge: .top, spacing: 0) {
                                    ScrollView(.horizontal) {
                                        Color("#00FF00").frame(width: 900, height: 32)
                                    }
                                    .frame(height: 32)
                                }
                            }
                    }
                }
            }
            let window = try XCTUnwrap(host.window)
            let navigation = try XCTUnwrap(host.views(WinUINavigationView.self).first)
            let title = Array("SOUI scrolling path bar".utf16) + [0]
            window.setTitle("SOUI scrolling path bar")
            let hwnd = try XCTUnwrap(title.withUnsafeBufferPointer { FindWindowW(nil, $0.baseAddress) })
            let flags = UINT(SWP_NOACTIVATE | SWP_NOSIZE)
            XCTAssertTrue(SetWindowPos(hwnd, HWND(bitPattern: -1), 32, 32, 0, 0, flags))
            defer { _ = SetWindowPos(hwnd, HWND(bitPattern: -2), 32, 32, 0, 0, flags) }
            path.wrappedValue = [1]
            host.runtime.pump.turn()
            let scrollers = host.views(WinUIScrollView.self)
            let bar = try XCTUnwrap(scrollers.first { $0.orientation == .horizontal })
            let body = try XCTUnwrap(scrollers.first { $0.orientation == .vertical })
            XCTAssertNil(bar.nativeSafeBarOwner)
            var sampledSlide = false
            let xs: [Double] = [20, 75, 130, 185, 240, 295]
            for _ in 0..<40 {
                host.step()
                guard bar.scroller.isAttached, bar.scroller.frame.height > 0 else { continue }
                let y = bar.scroller.origin.y - navigation.origin.y + bar.scroller.frame.height / 2
                let pixels = navigation.presentedPixels(at: xs.flatMap { [($0, y), ($0, y + 80)] }, in: window)
                guard pixels.count == 2 * xs.count else { continue }
                let bodyEdge = xs.indices.first { pixels[2 * $0 + 1] == 0xff0000ff }
                guard let bodyEdge, bodyEdge > 0 else { continue }
                let barEdge = try XCTUnwrap(xs.indices.first { pixels[2 * $0] == 0xff00ff00 },
                    "The scrolling page's path bar should be visible in the same transition sample.")
                XCTAssertLessThanOrEqual(abs(bodyEdge - barEdge), 1)
                sampledSlide = true
                break
            }
            XCTAssertTrue(sampledSlide, "The test sampled a native navigation slide before it landed.")
            host.settle { body.scroller.standing.offset.y > 0 }
            XCTAssertGreaterThan(body.scroller.standing.offset.y, 0)
        }
    }

    func testIntrinsicInvalidationReachesBothNativeOwnershipBoundaries() {
        onUIThread {
            let owner = NativePageOwner()
            let page = WinUISingleChildView()
            page.nativeLayoutOwner = owner
            let content = WinUIStackView(axis: .vertical)
            page.setItems([WinUILayoutItem(view: content)])
            let before = owner.arrangementRequests
            content.invalidateMeasurements()
            XCTAssertGreaterThan(owner.arrangementRequests, before,
                                 "unchanged child identities can still change page geometry")

            let bar = WinUIStackView(axis: .vertical)
            let promoted = WinUISafeAreaBarHost(bar: bar)
            defer { promoted.releaseBar() }
            let revision = promoted.measurementRevision
            bar.invalidateMeasurements()
            XCTAssertGreaterThan(promoted.measurementRevision, revision)
            let after = promoted.measurementRevision
            bar.setOpacity(0.5)
            XCTAssertEqual(promoted.measurementRevision, after, "paint does not change a bar's contribution")
        }
    }

    func testPromotedBarFollowsAncestorDrawingUntilReleased() throws {
        try onUIThread {
            let host = WinUIRenderer.running(reducesMotion: true) {
                ScrollView { Text("Content") }
                    .safeAreaInset(edge: .top, spacing: 0) {
                        Text("Bar").frame(height: 40).id("promoted")
                    }.id("ancestor")
            }
            let ancestor = try XCTUnwrap(host.view(id: .manual("ancestor")))
            let bar = try XCTUnwrap(host.view(id: .manual("promoted")))
            let promoted = try XCTUnwrap(bar.nativeSafeBarOwner as? WinUISafeAreaBarHost)
            ancestor.setOpacity(0.4)
            XCTAssertEqual(bar.drawnOpacity, 0.4, accuracy: 0.01)
            promoted.releaseBar()
            ancestor.setOpacity(0.2)
            XCTAssertEqual(bar.drawnOpacity, 1, accuracy: 0.01,
                           "a released bar must no longer receive its old native promotion's drawing")
        }
    }

    func testBottomEditorDecorationAndControlsFollowHeightAndPageChanges() throws {
        try onUIThread {
            let text = State(wrappedValue: "")
            let history = State(wrappedValue: false)
            let sidebar = State(wrappedValue: true)
            let clock = TestClock()
            let host = WinUIRenderer.running(clock: clock, room: WinUITestHost.wideRoom) {
                NavigationSplitView(sidebar.projectedValue) {
                    Text("Sidebar")
                } detail: {
                    ScrollView { Text(history.wrappedValue ? "History" : "Start") }
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            let height = text.wrappedValue.isEmpty && history.wrappedValue ? 40.0 : 128.0
                            VStack {
                                HStack(alignment: .bottom) {
                                    Button("Attach") {}.frame(width: 40, height: 40).id("attach")
                                    ZStack(alignment: .bottom) {
                                        TextEditor(text: text.projectedValue.transaction(.init(animation: .eased(200, .linear))))
                                            .scrollContentBackground(.hidden)
                                            .background(alignment: .topLeading) {
                                                if text.wrappedValue.isEmpty { Text("Write something") }
                                            }
                                            .animation(nil, value: text.wrappedValue.isEmpty)
                                            .safeAreaPadding(.vertical, 12)
                                            .frame(height: height)
                                            .background {
                                                RoundedRectangle(cornerRadius: 20).fill(Color.white).id("editor-fill")
                                            }.id("editor")
                                        Rectangle().fill(.clear)
                                            .frame(height: 16)
                                            .offset(y: -height + 8)
                                    }.frame(height: height)
                                    if text.wrappedValue.isEmpty {
                                        HStack {
                                            Button("Send") {}.frame(width: 40, height: 40).id("send-horizontal")
                                        }
                                    } else {
                                        VStack {
                                            Button("Send") {}.frame(width: 40, height: 40).id("send-vertical")
                                        }
                                    }
                                }
                            }.padding(16)
                        }
                        .hiddenSafeBarBackground()
                }
            }
            let editor = try XCTUnwrap(host.view(id: .manual("editor")))
            let editorInput = try XCTUnwrap(host.views(WinUITextEditorView.self).first)
            let fill = try XCTUnwrap(host.view(id: .manual("editor-fill")))
            let attach = try XCTUnwrap(host.view(id: .manual("attach")))
            for _ in 0..<12 { host.step(); host.frame() }
            let editorBottom = editor.origin.y + editor.laidOutFrame.height
            let attachY = attach.origin.y
            for step in 0..<4 {
                let started = clock.now
                let before = editor.laidOutFrame.height
                let expected = step == 1 || step == 3 ? 128.0 : 40.0
                if step == 1 || step == 2 {
                    editorInput.type(step == 1 ? "输入内容" : "")
                } else {
                    withAnimation(.eased(200, .linear)) { history.wrappedValue = step == 0 }
                }
                var previous = before
                for sample in [0.0, 25, 50, 100, 150] {
                    clock.now = started + sample
                    host.step()
                    host.frame()
                    let height = editor.laidOutFrame.height
                    let moment = "step \(step) at \(sample) ms"
                    XCTAssertEqual(editor.origin.y + height, editorBottom, accuracy: 1, moment)
                    XCTAssertEqual(fill.origin.y + fill.laidOutFrame.height, editorBottom, accuracy: 1, moment)
                    XCTAssertEqual(fill.laidOutFrame.height, height, accuracy: 1, moment)
                    XCTAssertEqual(attach.origin.y, attachY, accuracy: 1, moment)
                    if sample == 0 { XCTAssertEqual(height, before, accuracy: 1, moment) }
                    if expected > before { XCTAssertGreaterThanOrEqual(height, previous - 1, moment) }
                    if expected < before { XCTAssertLessThanOrEqual(height, previous + 1, moment) }
                    previous = height
                    if sample == 100 {
                        XCTAssertGreaterThan(height, min(before, expected) + 1, moment)
                        XCTAssertLessThan(height, max(before, expected) - 1, moment)
                    }
                }
                clock.now = started + 400
                for _ in 0..<12 { host.frame(); host.step() }
                XCTAssertEqual(editor.laidOutFrame.height, expected, accuracy: 1)
                XCTAssertEqual(fill.laidOutFrame.height, expected, accuracy: 1)
                XCTAssertTrue(host.view(id: .manual("editor")) === editor)
                for id in ["attach", step == 1 ? "send-vertical" : "send-horizontal"] {
                    let control = try XCTUnwrap(host.view(id: .manual(id)))
                    XCTAssertTrue(control.isAttached)
                    XCTAssertGreaterThan(control.laidOutFrame.width, 0)
                    XCTAssertEqual(control.drawnOpacity, 1, accuracy: 0.01)
                }
            }
        }
    }

    func testWideSidebarIsOpenBeforeTheWindowFirstActivates() {
        onUIThread {
            let window = WinUIWindow()
            defer { window.close() }
            let split = WinUISplitView()
            let sidebar = WinUISingleChildView()
            let detail = WinUISingleChildView()
            split.setItems([WinUILayoutItem(view: sidebar), WinUILayoutItem(view: detail)])

            let pending = sidebar.rootSafeAreaContext?(Rect(0, 0, 256, 600))
            XCTAssertEqual(pending?.safe.width, 256, "an unattached pane has no native origin yet")

            window.show(split, present: false)
            window.request(WindowFrame(width: WinUISidebarView.expandsAt + 8, height: 700))
            window.prepareFirstPresentation(split: split)
            XCTAssertTrue(split.isPresented)
            XCTAssertEqual(WinUIStrings.read {
                swiftomniui_winui_read(split.sidebar.handle, "paneOpen", $0, $1)
            }, "1", "the pane must already be open before the first native frame")

            window.presentContent()
            WinUITestHost.pump()
            XCTAssertTrue(sidebar.isAttached, "the first frame must include the sidebar page")
        }
    }

    func testNarrowFirstRoomDoesNotConsumeTheFirstWideRoom() {
        onUIThread {
            let window = WinUIWindow()
            defer { window.close() }
            let split = WinUISplitView()
            split.setItems([WinUILayoutItem(view: WinUISingleChildView()),
                            WinUILayoutItem(view: WinUISingleChildView())])
            window.show(split, present: false)
            window.request(WindowFrame(width: 560, height: 440))
            window.prepareFirstPresentation(split: split)
            XCTAssertFalse(split.isPresented)
            window.request(WindowFrame(width: WinUISidebarView.expandsAt + 8, height: 700))
            window.prepareFirstPresentation(split: split)
            XCTAssertTrue(split.isPresented)
        }
    }

    func testTheFileBarStaysInItsDetailColumnAndIdleLayoutConverges() throws {
        try onUIThread {
            let visible = State(wrappedValue: true)
            let host = WinUIRenderer.running(reducesMotion: true, room: WinUITestHost.wideRoom) {
                NavigationSplitView(visible.projectedValue) {
                    Text("Sidebar").navigationSplitViewColumnWidth(160)
                } detail: {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(0..<500, id: \.self) { number in Text("Row \(number)").frame(height: 30) }
                        }
                    }.safeAreaInset(edge: .top, spacing: 0) {
                        HStack {
                            Menu { MenuItem("Item") } label: { Text("Breadcrumb") }.buttonStyle(.plain)
                        }.frame(maxWidth: .infinity).frame(height: 32).id("bar")
                    }
                }
            }
            let window = try XCTUnwrap(host.window)
            let bar = try XCTUnwrap(host.view(id: .manual("bar")))
            let scroll = try XCTUnwrap(host.views(WinUIScrollView.self).first)
            host.settle { bar.origin.x > 0 && abs(bar.origin.x - scroll.origin.x) < 1 }
            XCTAssertGreaterThan(bar.origin.x, 0, "the breadcrumb must not cover the sidebar")
            XCTAssertEqual(bar.origin.x, scroll.origin.x, accuracy: 1)
            XCTAssertEqual(bar.frame.width, scroll.frame.width, accuracy: 1)
            XCTAssertGreaterThanOrEqual(bar.origin.y, window.chromeHeight - 1)
            visible.wrappedValue = false
            host.settle { abs(bar.origin.x - scroll.origin.x) < 1 && bar.frame.width == scroll.frame.width }
            XCTAssertTrue(host.view(id: .manual("bar")) === bar)
            XCTAssertEqual(bar.origin.x, scroll.origin.x, accuracy: 1)
            XCTAssertEqual(bar.frame.width, scroll.frame.width, accuracy: 1)
            for _ in 0..<10 { host.step(); host.layOut() }
            let lazy = try XCTUnwrap(host.views(WinUILazyView.self).first)
            let requests = lazy.cells.requests, sizings = WinUILayoutView.sizings
            XCTAssertLessThan(lazy.cells.built.count, 100)
            for _ in 0..<8 { host.step(); host.layOut() }
            XCTAssertEqual(lazy.cells.requests, requests)
            XCTAssertEqual(WinUILayoutView.sizings, sizings, "stable proposals must not keep invalidating their ancestors")
        }
    }

    func testSidebarPageSwitchReappliesTopAndBottomSafeInsetsWithoutResize() throws {
        try onUIThread {
            let visible = State(wrappedValue: true)
            let page = State(wrappedValue: 0)
            let host = WinUIRenderer.running(reducesMotion: true, room: WinUITestHost.wideRoom) {
                NavigationSplitView(visible.projectedValue) {
                    VStack {
                        if page.wrappedValue == 0 {
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(0..<100, id: \.self) { row in
                                        Text("File \(row)").frame(height: 30).id("file-\(row)")
                                    }
                                }
                            }
                            .id("files-scroll")
                            .safeAreaInset(edge: .bottom, spacing: 0) {
                                Text("Search").frame(height: 40).id("search")
                            }
                            .transition(.opacity)
                        } else {
                            ScrollView { Text("Other page") }
                                .transition(.opacity)
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        Text("Tabs").frame(maxWidth: .infinity).frame(height: 44).id("tabs")
                    }
                    .navigationSplitViewColumnWidth(220)
                } detail: {
                    Text("Detail")
                }
            }
            let tabs = try XCTUnwrap(host.view(id: .manual("tabs")))
            @MainActor func checkInsets() throws {
                let first = try XCTUnwrap(host.view(id: .manual("file-0")))
                let search = try XCTUnwrap(host.view(id: .manual("search")))
                let scroll = try XCTUnwrap(host.views(WinUIScrollView.self).first)
                XCTAssertGreaterThanOrEqual(first.origin.y, tabs.origin.y + tabs.frame.height - 1)
                scroll.scroller.move(to: Point(0, scroll.scroller.standing.reach.y))
                host.settle { host.view(id: .manual("file-99")) != nil }
                let last = try XCTUnwrap(host.view(id: .manual("file-99")))
                XCTAssertLessThanOrEqual(last.origin.y + last.frame.height, search.origin.y + 1)
                scroll.scroller.move(to: .zero)
                host.settle { host.view(id: .manual("file-0")) != nil }
            }
            host.settle { host.view(id: .manual("file-0")) != nil }
            try checkInsets()
            page.wrappedValue = 1
            host.settle { host.view(id: .manual("file-0")) == nil }
            page.wrappedValue = 0
            host.settle { host.view(id: .manual("file-0")) != nil }
            try checkInsets()
        }
    }

    func testNativeSplitRearrangesNestedSafeBarsWhenSidebarContentChangesAtTheSameSize() throws {
        try onUIThread {
            let shown = State(wrappedValue: true)
            let page = State(wrappedValue: 0)
            let host = WinUIRenderer.running(reducesMotion: true, room: WinUITestHost.wideRoom) {
                NavigationSplitView(shown.projectedValue) {
                    VStack {
                        if page.wrappedValue == 0 {
                            ScrollView { Text("Files") }
                                .id("files")
                                .safeAreaInset(edge: .bottom, spacing: 0) {
                                    Text("Search").frame(height: 40).id("search-bar")
                                }
                        } else {
                            ScrollView { Text("Git") }
                                .id("git")
                                .safeAreaInset(edge: .bottom, spacing: 0) {
                                    Text("Graph").frame(height: 96).id("graph-bar")
                                }
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        Text("Tabs").frame(height: 44).id("sidebar-tabs")
                    }
                    .navigationSplitViewColumnWidth(220)
                } detail: { Text("Detail") }
            }
            let tabs = try XCTUnwrap(host.view(id: .manual("sidebar-tabs")))
            let split = try XCTUnwrap(host.views(WinUISplitView.self).first)
            let originalSize = split.laidOutFrame
            let nativePages = host.views(WinUISingleChildView.self).filter { $0.nativeLayoutOwner === split }
            XCTAssertEqual(nativePages.count, 2)
            XCTAssertTrue(nativePages.allSatisfy { $0.rootSafeAreaContext != nil },
                          "native SplitView pages must inherit the window's safe-area proposal")
            let sidebarPage = try XCTUnwrap(nativePages.first { $0.origin.x < split.origin.x + 1 })
            XCTAssertGreaterThan(sidebarPage.layoutSafeArea(in: sidebarPage.allocatedBounds).insets.top, 0,
                                 "the sidebar page must inherit the title-bar's unsafe strip")
            for index in [1, 0, 1, 0] {
                page.wrappedValue = index
                let contentID = index == 0 ? "files" : "git"
                let bottomID = index == 0 ? "search-bar" : "graph-bar"
                host.settle {
                    guard let content = host.view(id: .manual(contentID)),
                          let bottom = host.view(id: .manual(bottomID)) else { return false }
                    return content.origin.y >= tabs.origin.y + tabs.frame.height - 1
                        && content.origin.y + content.frame.height <= bottom.origin.y + 1
                }
                host.layOut()
                let content = try XCTUnwrap(host.view(id: .manual(contentID)))
                let bottom = try XCTUnwrap(host.view(id: .manual(bottomID)))
                XCTAssertEqual(split.laidOutFrame.width, originalSize.width, accuracy: 1)
                XCTAssertEqual(split.laidOutFrame.height, originalSize.height, accuracy: 1)
                XCTAssertGreaterThan(sidebarPage.layoutSafeArea(in: sidebarPage.allocatedBounds).insets.top, 0)
                XCTAssertGreaterThanOrEqual(content.origin.y, tabs.origin.y + tabs.frame.height - 1)
                XCTAssertLessThanOrEqual(content.origin.y + content.frame.height,
                                         bottom.origin.y + 1)
            }
        }
    }
}
