// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import SwiftOmniUIConformance
import XCTest

@MainActor private final class NativePageOwner: WinUILayoutView {
    var arrangementRequests = 0
    override func invalidateArrange() {
        arrangementRequests += 1
        super.invalidateArrange()
    }
}

final class WinUISafeBarColumnTests: XCTestCase {
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
                XCTAssertTrue(swiftomniui_winui_window_material_covers(window.handle, window.titleBar.handle),
                              "column masks must cover the complete toolbar after each detail toggle")
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
            XCTAssertTrue(swiftomniui_winui_window_material_redirects(window.handle, oldBar.presentationHandle))
            let start = clock.now
            withAnimation(.eased(240, .linear)) { history.wrappedValue = true }
            host.step()
            host.layOut() // Mount the new branch once, then sample drawing only.
            for elapsed in [16.0, 64, 128, 200] {
                clock.now = start + elapsed
                host.runtime.displayCycle.frame(now: clock.now)
                XCTAssertEqual(swiftomniui_winui_opacity(oldBar.presentationHandle), 1, accuracy: 0.001,
                               "the opacity transition belongs to the ancestor, not the bar itself")
                XCTAssertFalse(swiftomniui_winui_window_material_redirects(window.handle, oldBar.presentationHandle),
                               "the shared overlay must not revive a departing ancestor's fixed controls")
                XCTAssertEqual(oldBar.laidOutFrame.height, height, accuracy: 1,
                               "leaving content keeps its layout allocation while its presentation fades")
            }
            clock.now = start + 600
            host.frame()
            let current = try XCTUnwrap(host.view(id: .manual("history-material-bar")))
            XCTAssertTrue(oldBar.isDetached)
            XCTAssertFalse(swiftomniui_winui_window_material_redirects(window.handle, oldBar.presentationHandle))
            XCTAssertTrue(swiftomniui_winui_window_material_redirects(window.handle, current.presentationHandle),
                          "the new resting branch rejoins the same shared material")
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
                        } else {
                            ScrollView { Text("Files").frame(height: 1800) }
                        }
                    }
                    .safeAreaInset(edge: .top, spacing: 0) {
                        Text("Sidebar tabs").frame(height: 48).id("material-sidebar-tabs")
                    }
                    .navigationSplitViewColumnWidth(220)
                } content: {
                    NavigationStack {
                        ScrollView { Text("Conversation").frame(height: 1800) }
                    }
                } detail: {
                    ScrollView { Text("Expert actions").frame(height: 1800) }
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
                let tabs = try XCTUnwrap(host.view(id: .manual("material-sidebar-tabs")))
                XCTAssertTrue(swiftomniui_winui_window_material_covers(window.handle, tabs.presentationHandle),
                              "initial mount and sidebar replacement must commit the complete material region")
                XCTAssertFalse(swiftomniui_winui_window_acrylic_samples(window.handle, tabs.presentationHandle),
                               "fixed sidebar controls must never feed the content blur")
                if detail {
                    let experts = try XCTUnwrap(host.view(id: .manual("material-experts")))
                    XCTAssertTrue(swiftomniui_winui_window_material_covers(window.handle, experts.presentationHandle),
                                  "the auxiliary detail's local selector joins the same region")
                    XCTAssertFalse(swiftomniui_winui_window_acrylic_samples(window.handle, experts.presentationHandle),
                                   "expert controls must remain outside the material input")
                }
                if detail {
                    for scroll in host.views(WinUIScrollView.self) {
                        XCTAssertTrue(swiftomniui_winui_window_acrylic_captures_viewport(window.handle, scroll.scroller.presentationHandle),
                                      "the committed source must contain live outer viewports on first display")
                    }
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
                            HStack(alignment: .bottom) {
                                Button("Attach") {}.frame(width: 40, height: 40).id("attach")
                                TextEditor(text: text.projectedValue)
                                    .scrollContentBackground(.hidden)
                                    .frame(height: text.wrappedValue.isEmpty && history.wrappedValue ? 40 : 128)
                                    .background {
                                        RoundedRectangle(cornerRadius: 20).fill(Color.white).id("editor-fill")
                                    }.id("editor")
                                if text.wrappedValue.isEmpty {
                                    HStack {
                                        Button("Send") {}.frame(width: 40, height: 40).id("send-horizontal")
                                    }
                                } else {
                                    VStack {
                                        Button("Send") {}.frame(width: 40, height: 40).id("send-vertical")
                                    }
                                }
                            }.padding(16)
                        }
                }
            }
            let editor = try XCTUnwrap(host.view(id: .manual("editor")))
            for step in 0..<4 {
                withAnimation(.eased(200, .linear)) {
                    history.wrappedValue = step != 3
                    text.wrappedValue = step == 1 ? "输入内容" : ""
                }
                for _ in 0..<12 { host.step(); host.frame() }
                clock.now += 400
                for _ in 0..<12 { host.frame(); host.step() }
                let fill = try XCTUnwrap(host.view(id: .manual("editor-fill")))
                let expected = step == 1 || step == 3 ? 128.0 : 40.0
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
