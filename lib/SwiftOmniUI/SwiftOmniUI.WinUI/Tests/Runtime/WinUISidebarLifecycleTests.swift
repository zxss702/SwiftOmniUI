// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) @testable import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import SwiftOmniUIConformance
import WinSDK
import XCTest

final class WinUISidebarLifecycleTests: XCTestCase {
    func testNativeTextAndPicturesRenderAfterRepeatedPageChanges() throws {
        try onUIThread {
            let clock = TestClock()
            let files = State(wrappedValue: true)
            let document = State(wrappedValue: 0)
            let host = WinUIRenderer.running(clock: clock, room: WinUITestHost.wideRoom) {
                NavigationSplitView(Binding(get: { true }, set: { _ in })) {
                    VStack {
                        Group {
                            if files.wrappedValue {
                                ScrollView {
                                    LazyVStack(alignment: .leading, spacing: 0) {
                                        ForEach(0..<80) { index in
                                            HStack {
                                                Image("test_halves.svg").resizable().scaledToFit()
                                                    .frame(width: 24, height: 24).id("picture-\(index)")
                                                Text("Package \(index)").foregroundStyle(.black)
                                                    .id("filename-\(index)")
                                            }
                                            .frame(height: 32)
                                        }
                                    }
                                }
                            } else {
                                Text("Conversation history")
                            }
                        }
                        .transition(.blur.combined(with: .scale(scale: 1.01, anchor: .top)).animation(.snappy))
                    }
                    .background(Color.white)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        Image(systemName: "\u{E721}").foregroundStyle(.black)
                            .frame(width: 24, height: 40).id("search-symbol")
                    }
                } detail: {
                    TextEditor(text: Binding(
                        get: { "Document \(document.wrappedValue)\nVisible source text" },
                        set: { _ in }
                    ))
                        .foregroundStyle(.black).background(Color.white)
                        .id("editor-\(document.wrappedValue)")
                }
            }
            @MainActor func advance(frames: Int) {
                for _ in 0..<frames {
                    clock.now += 16
                    host.step()
                    host.frame()
                }
            }

            @MainActor func sample(_ view: WinUIView, inset: Int = 0) -> [UInt32] {
                let across = min(128, Int(view.laidOutFrame.width) - inset)
                let down = min(50, Int(view.laidOutFrame.height) - inset)
                let points = stride(from: inset, to: down, by: 2).flatMap { y in
                    stride(from: inset, to: across, by: 2).map { x in (Double(x) + 0.5, Double(y) + 0.5) }
                }
                guard !points.isEmpty else { return [] }
                return view.pixels(at: points)
            }

            func hasDarkInk(_ pixels: [UInt32]) -> Bool {
                pixels.contains { pixel in
                    pixel >> 24 >= 0xf0 && [0, 8, 16].allSatisfy { (pixel >> $0) & 0xff < 0x50 }
                }
            }

            advance(frames: 36)
            for turn in 0..<8 {
                if turn > 0 {
                    withAnimation(.snappy) {
                        files.wrappedValue = false
                        document.wrappedValue = turn
                    }
                    advance(frames: turn <= 3 ? 36 : 4)
                    withAnimation(.snappy) { files.wrappedValue = true }
                    advance(frames: 36)
                }
                // Rows can scroll beneath the safe-area material. Sample below it.
                let label = try XCTUnwrap(host.view(id: .manual("filename-3")) as? WinUILabelView)
                let picture = try XCTUnwrap(host.view(id: .manual("picture-3")))
                let symbolFrame = try XCTUnwrap(host.view(id: .manual("search-symbol")))
                let symbol = try XCTUnwrap(symbolFrame.sourceElement?.first(type: .image)?.winUI.view as? WinUIImageView)
                let editor = try XCTUnwrap(host.view(id: .manual("editor-\(turn)")) as? WinUITextEditorView)
                XCTAssertEqual(label.text, "Package 3")
                XCTAssertEqual(editor.text, "Document \(turn)\nVisible source text")
                XCTAssertTrue(sample(picture).contains(0xffff_0000), "picture, turn \(turn)")
                XCTAssertTrue(hasDarkInk(sample(label)), "file label, turn \(turn)")
                XCTAssertTrue(sample(symbol).contains { $0 >> 24 != 0 }, "Fluent glyph, turn \(turn)")
                XCTAssertTrue(hasDarkInk(sample(editor, inset: 8)), "editor, turn \(turn)")
            }
        }
    }

    func testNativePagesKeepALiveSafeAreaProvider() {
        onUIThread {
            let navigation = WinUINavigationView()
            let page = WinUISingleChildView()
            navigation.setItems([WinUILayoutItem(view: page)])
            let bounds = Rect(0, 0, 300, 200)
            navigation.setLayoutContext(SafeAreaContext(bounds: bounds, layout: bounds,
                                                       container: Rect(0, 12, 300, 188)))
            XCTAssertNil(page.safeAreaContext)
            XCTAssertEqual(page.layoutSafeArea(in: bounds).safe.y, 12)
            navigation.setLayoutContext(SafeAreaContext(bounds: bounds, layout: bounds,
                                                       container: Rect(0, 32, 300, 168)))
            XCTAssertEqual(page.layoutSafeArea(in: bounds).safe.y, 32,
                           "native chrome changes reach the existing page")
        }
    }

    func testExplicitlyClosedBindingOwnsTheFirstWidePresentation() throws {
        try onUIThread {
            let shown = State(wrappedValue: false)
            let host = WinUIRenderer.running(room: WinUITestHost.wideRoom) {
                NavigationSplitView(shown.projectedValue) { Text("Files") } detail: { Text("Detail") }
            }
            let split = try XCTUnwrap(host.views(WinUISplitView.self).first)
            XCTAssertFalse(shown.wrappedValue)
            XCTAssertFalse(split.isPresented)
            XCTAssertFalse(split.automaticallyOpensSidebar)
            XCTAssertEqual(Self.read("paneOpen", from: split.sidebar), "0")
            XCTAssertEqual(Self.read("paneDisplayMode", from: split.sidebar), "inline")
            shown.wrappedValue = true
            host.step()
            XCTAssertTrue(split.isPresented, "manual expansion remains available")
        }
    }

    func testExplicitThreeColumnVisibilityIsNotReplacedWithAll() throws {
        try onUIThread {
            let columns = State(wrappedValue: NavigationSplitViewVisibility.doubleColumn)
            let host = WinUIRenderer.running(room: WinUITestHost.wideRoom) {
                NavigationSplitView(columnVisibility: columns.projectedValue) {
                    Text("Files")
                } content: {
                    Text("Conversation")
                } detail: {
                    Text("Auxiliary")
                }
            }
            let split = try XCTUnwrap(host.views(WinUISplitView.self).first)
            XCTAssertEqual(columns.wrappedValue, .doubleColumn)
            XCTAssertFalse(split.isPresented)
            XCTAssertFalse(split.automaticallyOpensSidebar)
            XCTAssertEqual(Self.read("paneOpen", from: split.sidebar), "0")
        }
    }

    func testPreparedInlineModeSurvivesConfigurationBeforeNativeAllocation() {
        onUIThread {
            let split = WinUISplitView()
            split.automaticallyOpensSidebar = false
            split.setItems([WinUILayoutItem(view: WinUISingleChildView()),
                            WinUILayoutItem(view: WinUISingleChildView())])
            split.prepareFirstPresentation(width: 1280)
            XCTAssertEqual(Self.read("paneDisplayMode", from: split.sidebar), "inline")
            split.sidebarPaneLength = [200, 256, 400]
            XCTAssertEqual(split.sidebar.laidOutFrame.width, 0)
            XCTAssertEqual(Self.read("paneDisplayMode", from: split.sidebar), "inline")
            XCTAssertEqual(Self.read("paneOpen", from: split.sidebar), "0")
        }
    }

    func testInlinePaneKeepsItsRowsThroughoutNativeTransitions() throws {
        try onUIThread {
            let shown = State(wrappedValue: true)
            let host = WinUIRenderer.running(room: WinUITestHost.wideRoom) {
                NavigationSplitView(shown.projectedValue) {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(0..<100) { Text("Row \($0)").frame(height: 28) }
                        }
                    }
                } detail: { Text("Detail") }
            }
            let split = try XCTUnwrap(host.views(WinUISplitView.self).first)
            let scroll = try XCTUnwrap(host.views(WinUIScrollView.self).first)
            let lazy = try XCTUnwrap(host.views(WinUILazyView.self).first)
            for open in [false, true, false, true] {
                shown.wrappedValue = open
                host.step()
                XCTAssertEqual(Self.read("paneOpen", from: split.sidebar), open ? "1" : "0")
                if !open { WinUITestHost.pump(0.35) }
                if open {
                    // Reopening the same native pane keeps its existing rows.
                    // No scroll or transition completion repair supplies them.
                    XCTAssertFalse(lazy.mounted.isEmpty)
                    let identities = lazy.mounted.mapValues { $0.view.number }
                    for _ in 0..<8 {
                        host.layOut()
                        host.frame()
                        XCTAssertFalse(lazy.mounted.isEmpty)
                        XCTAssertEqual(lazy.mounted.mapValues { $0.view.number }, identities)
                    }
                    XCTAssertEqual(scroll.scroller.standing.offset.y, 0, accuracy: 1)
                }
            }
        }
    }

    func testClosingSidebarRestoresDetailAndComposerToTheActualNativeWidth() throws {
        try onUIThread {
            let shown = State(wrappedValue: true)
            let host = WinUIRenderer.running(reducesMotion: true, room: WinUITestHost.wideRoom) {
                NavigationSplitView(shown.projectedValue) {
                    Text("Sidebar").navigationSplitViewColumnWidth(256)
                } detail: {
                    ScrollView { Text("Detail").frame(maxWidth: .infinity) }
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            HStack {
                                Button("Attach") {}.frame(width: 40, height: 40)
                                TextEditor().frame(height: 128).id("composer")
                                Button("Send") {}.frame(width: 40, height: 40)
                            }.id("composer-row")
                        }.id("detail")
                }
            }
            let detail = try XCTUnwrap(host.view(id: .manual("detail")))
            let composer = try XCTUnwrap(host.view(id: .manual("composer")))
            let row = try XCTUnwrap(host.view(id: .manual("composer-row")))
            let fullWidth = try XCTUnwrap(host.window?.content).laidOutFrame.width
            for open in [false, true, false] {
                shown.wrappedValue = open
                host.step()
                host.layOut()
                let width = fullWidth - (open ? 256 : 0)
                XCTAssertEqual(detail.laidOutFrame.width, width, accuracy: 1)
                XCTAssertEqual(row.laidOutFrame.width, width, accuracy: 1)
                XCTAssertGreaterThan(composer.laidOutFrame.width, width - 120)
                XCTAssertTrue(host.view(id: .manual("composer")) === composer)
            }
        }
    }

    func testInlineSidebarKeepsTheDetailTrailingEdgeFixedThroughoutOpenAndClose() throws {
        try onUIThread {
            try XCTSkipUnless(swiftomniui_winui_animations_enabled())
            let shown = State(wrappedValue: false)
            let host = WinUIRenderer.running(room: WinUITestHost.wideRoom) {
                NavigationSplitView(shown.projectedValue) {
                    Color.red.id("pane").navigationSplitViewColumnWidth(256)
                } detail: {
                    Color.blue.id("detail")
                }
            }
            let pane = try XCTUnwrap(host.view(id: .manual("pane")))
            let detail = try XCTUnwrap(host.view(id: .manual("detail")))
            let split = try XCTUnwrap(host.views(WinUISplitView.self).first).sidebar
            let left = split.origin.x
            let right = left + split.laidOutFrame.width
            XCTAssertGreaterThan(right, left + 256)
            for open in [true, false] {
                shown.wrappedValue = open
                var previous = open ? 0.0 : 256.0
                var passedThroughIntermediateWidth = false
                for _ in 0..<36 {
                    host.step()
                    host.layOut()
                    let leading = detail.origin.x - left
                    XCTAssertEqual(detail.origin.x + detail.laidOutFrame.width, right, accuracy: 1)
                    if leading > 1 {
                        XCTAssertEqual(pane.laidOutFrame.width, 256, accuracy: 1)
                        XCTAssertEqual(pane.origin.x + pane.laidOutFrame.width, detail.origin.x, accuracy: 1)
                    }
                    if open {
                        XCTAssertGreaterThanOrEqual(leading, previous - 1)
                    } else {
                        XCTAssertLessThanOrEqual(leading, previous + 1)
                    }
                    passedThroughIntermediateWidth = passedThroughIntermediateWidth || (leading > 1 && leading < 255)
                    previous = leading
                }
                XCTAssertTrue(passedThroughIntermediateWidth)
                XCTAssertEqual(previous, open ? 256 : 0, accuracy: 1)
                XCTAssertTrue(host.view(id: .manual("detail")) === detail)
            }
        }
    }

    func testPageSafeAreaUsesLayoutOffsetsThroughNativePresentationTransforms() throws {
        try onUIThread {
            let window = WinUIWindow()
            defer { window.close() }
            let split = WinUISplitView()
            split.automaticallyOpensSidebar = false
            let page = WinUISingleChildView()
            split.setItems([WinUILayoutItem(view: WinUISingleChildView()), WinUILayoutItem(view: page)])
            window.request(WindowFrame(width: 1280, height: 700))
            window.show(split)
            WinUITestHost.pump()
            XCTAssertGreaterThan(page.laidOutFrame.width, 0)
            let bounds = Rect(0, 0, page.laidOutFrame.width, page.laidOutFrame.height)
            let before = page.layoutSafeArea(in: bounds)
            for translation in [256.0, -256, 0] {
                swiftomniui_winui_set_transform(page.handle, translation, 0, 0, 1, 1, 0, 0)
                XCTAssertEqual(page.layoutSafeArea(in: bounds), before,
                               "presentation translation cannot consume the page's safe width")
            }
        }
    }

    @MainActor private static func read(_ property: String, from view: WinUIView) -> String {
        WinUIStrings.read { swiftomniui_winui_read(view.handle, property, $0, $1) }
    }

    func testSidebarTabSwitchTransitionAndPill() throws {
        try onUIThread {
            let clock = TestClock()
            let tab = State(wrappedValue: 0)
            let columns = State(wrappedValue: NavigationSplitViewVisibility.all)
            let ns = Namespace().wrappedValue
            let host = WinUIRenderer.running(clock: clock, room: WinUITestHost.wideRoom) {
                NavigationSplitView(columnVisibility: columns.projectedValue) {
                    VStack {
                        Group {
                            switch tab.wrappedValue {
                            case 0:
                                ScrollView {
                                    LazyVStack(spacing: 0) {
                                        ForEach(0..<40) { i in
                                            Text("File \(i)").frame(height: 28)
                                        }
                                    }
                                }
                                .id("tab-0")
                            case 1:
                                List(0..<20, id: \.self) { i in
                                    Text("Search \(i)")
                                }
                                .id("tab-1")
                            default:
                                ScrollView {
                                    VStack {
                                        Text("Git")
                                    }
                                }
                                .id("tab-2")
                            }
                        }
                        .transition(.blur.combined(with: .scale(scale: 1.01, anchor: .top)).animation(.snappy))
                    }
                    .frame(maxHeight: .infinity)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        HStack(spacing: 4) {
                            ForEach(0..<3, id: \.self) { idx in
                                Button {
                                    withAnimation(.bouncy) { tab.wrappedValue = idx }
                                } label: {
                                    Text("T\(idx)")
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .background {
                                            if tab.wrappedValue == idx {
                                                Color.clear
                                                    .frame(height: 32)
                                                    .background(Color("#FF00FF"), in: Capsule(style: .continuous))
                                                    .matchedGeometryEffect(id: "sideBarButton", in: ns)
                                                    .id("pill-\(idx)")
                                            }
                                        }
                                }
                                .id("tab-button-\(idx)")
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(height: 32)
                        .padding(8)
                    }
                } detail: {
                    Text("Detail")
                }
            }
            for _ in 0..<12 { host.step(); host.frame() }
            let t0Before = try XCTUnwrap(host.view(id: .manual("tab-0")))
            let pill0Before = try XCTUnwrap(host.view(id: .manual("pill-0")))
            let vstackBefore = try XCTUnwrap(t0Before.sourceElement?.parent?.winUI.view)
            let window = try XCTUnwrap(host.window)
            let root = try XCTUnwrap(window.content)
            let title = "SOUI sidebar pill paint regression"
            window.setTitle(title)
            let nativeTitle = Array(title.utf16) + [0]
            let hwnd = try XCTUnwrap(nativeTitle.withUnsafeBufferPointer { FindWindowW(nil, $0.baseAddress) })
            let positionFlags = UINT(SWP_NOACTIVATE | SWP_NOSIZE)
            XCTAssertTrue(SetWindowPos(hwnd, HWND(bitPattern: -1), 32, 32, 0, 0, positionFlags))
            defer { _ = SetWindowPos(hwnd, HWND(bitPattern: -2), 32, 32, 0, 0, positionFlags) }
            let beforeOriginX = pill0Before.origin.x
            let nextButton = try XCTUnwrap(host.view(id: .manual("tab-button-1")))
            let gapX = (beforeOriginX + pill0Before.laidOutFrame.width + nextButton.origin.x) / 2
            let gapPoint = (gapX - root.origin.x, pill0Before.origin.y - root.origin.y + 16)
            let pillColor: UInt32 = 0xFFFF_00FF
            @MainActor func gapShowsPill() -> Bool {
                root.presentedPixels(at: [gapPoint], in: window) == [pillColor]
            }
            XCTAssertFalse(gapShowsPill())
            XCTAssertEqual(t0Before.frame.y, 0, accuracy: 0.5)
            XCTAssertEqual(vstackBefore.frame.height, 700, accuracy: 0.5)

            withAnimation(.bouncy) { tab.wrappedValue = 1 }
            host.runtime.pump.turn()
            let t1AfterTurn = try XCTUnwrap(host.view(id: .manual("tab-1")))
            XCTAssertNotNil(t1AfterTurn.sourceElement?.transition)

            var originsX: [Double] = []
            var t1Opacities: [Double] = []
            var sampledGap = false
            for _ in 0..<8 {
                clock.now += 16
                host.step()
                host.frame()
                let t0 = host.view(id: .manual("tab-0"))
                let t1 = try XCTUnwrap(host.view(id: .manual("tab-1")))
                let p1 = try XCTUnwrap(host.view(id: .manual("pill-1")))
                if let t0 {
                    XCTAssertEqual(t0.frame.y, 0, accuracy: 0.5, "departing scroll tab must remain aligned under safeAreaInset")
                    XCTAssertEqual(t0.frame.height, 700, accuracy: 0.5)
                }
                XCTAssertEqual(t1.frame.y, 0, accuracy: 0.5)
                XCTAssertEqual(t1.frame.height, 700, accuracy: 0.5)
                XCTAssertEqual(vstackBefore.frame.height, 700, accuracy: 0.5)
                t1Opacities.append(t1.opacity)
                originsX.append(p1.origin.x)
                if !sampledGap, gapX > p1.origin.x + 4, gapX < p1.origin.x + p1.laidOutFrame.width - 4 {
                    // Neither button owns this gap. The moving pill must still paint through it.
                    host.settle { gapShowsPill() }
                    XCTAssertTrue(gapShowsPill(), "the moving pill must paint outside its new button")
                    sampledGap = true
                }
            }

            XCTAssertTrue(sampledGap, "the animation must carry the pill across the gap")
            XCTAssertLessThan(t1Opacities[0], 0.2, "entering List must start its transition from low opacity")
            XCTAssertGreaterThan(t1Opacities.last ?? 0, t1Opacities[0] + 0.15, "entering List must fade in across frames")
            XCTAssertEqual(originsX[0], beforeOriginX, accuracy: 2.0, "matchedGeometry pill must launch from the previous pill's origin")
            XCTAssertGreaterThan(originsX.last ?? 0, originsX[0] + 10, "matchedGeometry pill must travel smoothly toward target button")

            for _ in 0..<45 {
                clock.now += 16
                host.step()
                host.frame()
            }
            let settledT1 = try XCTUnwrap(host.view(id: .manual("tab-1")))
            let settledPill = try XCTUnwrap(host.view(id: .manual("pill-1")))
            XCTAssertEqual(settledT1.opacity, 1.0, accuracy: 0.02)
            XCTAssertEqual(settledT1.blur, 0.0, accuracy: 0.05)
            XCTAssertGreaterThan(settledPill.origin.x, beforeOriginX + 60)
            XCTAssertEqual(settledPill.placedFrame.x, 0, accuracy: 0.5)
        }
    }
}
