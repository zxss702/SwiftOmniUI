// SPDX-License-Identifier: Apache-2.0
@_spi(Host) @testable import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import CSwiftOmniUIWinUI
import WinSDK
import XCTest

/// Watches the compositor while the UI thread is busy. Sampling after host.step() alone misses
/// blanks that disappear before a blocked UI callback returns.
private final class BlackboardPaintProbe: @unchecked Sendable {
    let lock = NSLock()
    let dpiContext = GetThreadDpiAwarenessContext()
    let window: HWND
    let point: POINT
    let width: Int
    let height: Int
    let scale: Double
    var stopped = false
    var gaps: [Double] = []
    var phase = 0.0
    var phaseGaps: [Double: [Double]] = [:]
    var obscured = 0
    var inklessSamples = 0
    init(window: HWND, point: POINT, width: Int = 1, height: Int, scale: Double) {
        self.window = window; self.point = point; self.height = height; self.scale = scale
        self.width = width
    }
    nonisolated static let entry: @convention(c) (UnsafeMutableRawPointer?) -> DWORD = { raw in
        guard let raw else { return 1 }
        let probe = Unmanaged<BlackboardPaintProbe>.fromOpaque(raw).takeRetainedValue()
        let dpi = SetThreadDpiAwarenessContext(probe.dpiContext)
        defer { _ = SetThreadDpiAwarenessContext(dpi) }
        guard let desktop = GetDC(nil), let copy = CreateCompatibleDC(desktop) else { return 1 }
        defer { _ = DeleteDC(copy); _ = ReleaseDC(nil, desktop) }
        var info = BITMAPINFO()
        info.bmiHeader.biSize = DWORD(MemoryLayout<BITMAPINFOHEADER>.size)
        info.bmiHeader.biWidth = LONG(probe.width)
        info.bmiHeader.biHeight = -LONG(probe.height)
        info.bmiHeader.biPlanes = 1
        info.bmiHeader.biBitCount = 32
        var storage: UnsafeMutableRawPointer?
        guard let bitmap = CreateDIBSection(desktop, &info, UINT(DIB_RGB_COLORS), &storage, nil, 0),
              let bytes = storage?.assumingMemoryBound(to: UInt32.self) else { return 1 }
        let previous = SelectObject(copy, bitmap)
        defer { _ = SelectObject(copy, previous); _ = DeleteObject(bitmap) }
        while true {
            probe.lock.lock()
            let stopped = probe.stopped
            probe.lock.unlock()
            if stopped { return 0 }
            if GetAncestor(WindowFromPoint(probe.point), UINT(GA_ROOTOWNER)) != probe.window {
                probe.lock.lock(); probe.obscured += 1; probe.lock.unlock()
            } else if BitBlt(copy, 0, 0, Int32(probe.width), Int32(probe.height), desktop, probe.point.x, probe.point.y, DWORD(SRCCOPY)) {
                _ = GdiFlush()
                var longest = 0, run = 0
                for y in 0..<probe.height {
                    let pixel = bytes[y * probe.width + probe.width - 1]
                    let blue = pixel & 255, red = (pixel >> 16) & 255
                    let painted = blue > 235 && red >= 210 && red <= 230
                    run = painted ? 0 : run + 1
                    longest = max(longest, run)
                }
                var ink = 0
                if probe.width > 1 {
                    for y in stride(from: 0, to: probe.height, by: 3) {
                        for x in stride(from: 0, to: probe.width, by: 3) {
                            let pixel = bytes[y * probe.width + x]
                            if pixel & 255 < 120 && (pixel >> 8) & 255 < 120 && (pixel >> 16) & 255 < 120 { ink += 1 }
                        }
                    }
                }
                probe.lock.lock()
                if probe.width > 1 && ink < 10 { probe.inklessSamples += 1 }
                let gap = Double(longest) / probe.scale
                probe.gaps.append(gap)
                probe.phaseGaps[probe.phase, default: []].append(gap)
                probe.lock.unlock()
            }
            Sleep(8)
        }
    }
}

private struct ParagraphAnchor: Equatable {
    let bounds: Anchor<Rect>
    let texts: [Text.Layout]
}

private struct ParagraphAnchors: PreferenceKey {
    static var defaultValue: [ParagraphAnchor] { [] }
    static func reduce(value: inout [ParagraphAnchor], nextValue: () -> [ParagraphAnchor]) {
        value += nextValue()
    }
}

private struct SelectionInput: Equatable {
    let anchors: [ParagraphAnchor]
    let frames: [Rect]
    let size: Size
}

@MainActor private final class BlackboardReports {
    var changes = 0
    var lines = 0
    var textReports = 0
    var selectionText = ""
    var selectionSlices: [Rect] = []
}

/// Measures the work inside native callbacks, excluding the message pump's intentional wait.
/// These samples are diagnostics, not a frame-time claim: WinUI also performs native work outside them.
@MainActor enum WinUIScrollWork {
    static var samples: [String: [Double]] = [:]
    private static var tracesLayout = false
    private static var callbackChildren: [Double] = []
    private static func callback(_ kind: String, view: Int64, _ body: () -> Void) {
        let start = WinUIFrameClock.monotonic()
        if tracesLayout { callbackChildren.append(0) }
        body()
        let elapsed = WinUIFrameClock.monotonic() - start
        samples[kind, default: []].append(elapsed)
        if tracesLayout {
            let children = callbackChildren.removeLast()
            if !callbackChildren.isEmpty { callbackChildren[callbackChildren.count - 1] += elapsed }
            let name = WinUIView.find(view)?.sourceElement?.type.name ?? "native"
            samples["self-\(kind)-\(name)", default: []].append(max(0, elapsed - children))
        }
    }
    static func record(_ kind: String, since start: Double) {
        samples[kind, default: []].append(WinUIFrameClock.monotonic() - start)
    }
    static func install() {
        var callbacks = WinUICallbacks.table
        callbacks.turn = {
            let start = WinUIFrameClock.monotonic()
            MainActor.assumeIsolated {
                let pending = WinUIFrameClock.monotonic()
                WinUIDoorbell.commitPending()
                WinUIScrollWork.record("pending", since: pending)
                let pump = WinUIFrameClock.monotonic()
                WinUIRenderer.shared?.runtime.pump.turn()
                WinUIScrollWork.record("pump", since: pump)
                WinUIScrollWork.record("turn", since: start)
            }
        }
        callbacks.frame = { time in
            let start = WinUIFrameClock.monotonic()
            WinUICallbacks.table.frame?(time)
            MainActor.assumeIsolated { WinUIScrollWork.record("frame", since: start) }
        }
        callbacks.measure = { view, width, height, size in
            MainActor.assumeIsolated {
                WinUIScrollWork.callback("measure", view: view) {
                    WinUICallbacks.table.measure?(view, width, height, size)
                }
            }
        }
        callbacks.arrange = { view, width, height in
            MainActor.assumeIsolated {
                WinUIScrollWork.callback("arrange", view: view) {
                    WinUICallbacks.table.arrange?(view, width, height)
                }
            }
        }
        XCTAssertEqual(swiftomniui_winui_embed(&callbacks), 0)
        WinUIDoorbell.workObserver = { name, time in samples["job-" + name, default: []].append(time) }
        WinUITextView.textWorkObserver = { name, time in samples[name, default: []].append(time) }
        tracesLayout = ProcessInfo.processInfo.environment["SOUI_MOUNT_TRACE"] == "1"
        callbackChildren = []
        if tracesLayout {
            WinUIElement.workObserver = { phase, type, time in
                samples["mount-\(phase)-\(type.name)", default: []].append(time)
            }
        }
        samples = [:]
    }
    static func finish(phase: String = "scroll") {
        WinUIDoorbell.workObserver = nil
        WinUITextView.textWorkObserver = nil
        WinUIElement.workObserver = nil
        var callbacks = WinUICallbacks.table
        _ = swiftomniui_winui_embed(&callbacks)
        for kind in samples.keys.sorted() {
            let values = samples[kind, default: []].sorted()
            guard !values.isEmpty else { continue }
            print("BLACKBOARD phase=\(phase) work=\(kind) count=\(values.count) totalms=\(values.reduce(0, +)) p95ms=\(values[Int(Double(values.count - 1) * 0.95)]) maxms=\(values.last!) over8ms=\(values.filter { $0 > 8 }.count)")
            if phase == "scroll", kind == "frame" || kind == "turn",
               let value = ProcessInfo.processInfo.environment["SOUI_SCROLL_BUDGET_MS"], let budget = Double(value) {
                XCTAssertLessThanOrEqual(values.last!, budget, "\(kind) work exceeded the requested scroll budget")
            }
        }
        samples = [:]
    }
}

@MainActor private final class BlackboardPresenter: FramePresenter {
    let host: WinUIRenderer
    init(_ host: WinUIRenderer) { self.host = host }
    var wantsFrames: Bool { host.wantsFrames }
    func commitUserReports(now: Double) {
        let start = WinUIFrameClock.monotonic()
        host.runtime.frames.commit(now: now)
        WinUIScrollWork.record("geometry", since: start)
        let pending = WinUIFrameClock.monotonic()
        WinUIDoorbell.commitPending()
        WinUIScrollWork.record("pending", since: pending)
    }
    func present(states: [Int32: HostStateValue], properties: [UInt64: Set<Prop>]) {
        host.present(states: states, properties: properties)
    }
    func renderIfNeeded() {
        let start = WinUIFrameClock.monotonic()
        host.renderIfNeeded()
        WinUIScrollWork.record("render", since: start)
    }
}

private struct BlackboardFixture: View {
    let reports: BlackboardReports
    var tables = false
    @State private var showing = false

    var body: some View {
        Button("黑板") { showing = true }
            .frame(width: 100, height: 32)
            .popover(isPresented: $showing, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("黑板").bold().font(.headline).padding(12)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(0..<60) { number in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("决策 \(number)").font(.system(size: 24, weight: .bold))
                                    HStack(alignment: .top, spacing: 6) {
                                        Image(systemName: "\u{E8A5}").frame(width: 16, height: 16)
                                        (Text("基准视觉规格：").bold() + Text(String(repeating:
                                            "蓝色主色，标题与正文。不同长度的内容自动换行；family specifications and details。",
                                            count: 2 + number % 8)))
                                    }
                                    Text("• 布局 10×36；项目 \(number)\n• 第二项，包含换行和符号。")
                                    if tables && number % 3 == 1 {
                                        BlackboardTable(number: number)
                                    }
                                }
                                .background(Color(red: 220, green: 235 - number % 8 * 8, blue: 250))
                                .backgroundPreferenceValue(Text.LayoutKey.self) { texts in
                                    Color.clear.anchorPreference(key: ParagraphAnchors.self, value: .bounds) {
                                        [ParagraphAnchor(bounds: $0, texts: texts)]
                                    }
                                }
                            }
                        }
                        .font(.system(size: 14))
                        .lineSpacing(10)
                        .backgroundPreferenceValue(ParagraphAnchors.self) { anchors in
                            GeometryReader { geometry in
                                Color.clear.onChange(of: SelectionInput(
                                    anchors: anchors, frames: anchors.map { geometry[$0.bounds] }, size: geometry.size
                                ), initial: true) { _, _ in
                                    reports.changes += 1
                                    reports.lines = anchors.reduce(0) { result, anchor in
                                        result + anchor.texts.reduce(0) { $0 + $1.count }
                                    }
                                    var strings: [String] = []
                                    var slices: [Rect] = []
                                    for anchor in anchors {
                                        for text in anchor.texts {
                                            let origin = geometry[text.origin]
                                            for line in text {
                                                for run in line {
                                                    for slice in run {
                                                        if let string = slice.text { strings.append(string) }
                                                        let rect = slice.typographicBounds.rect
                                                        slices.append(Rect(origin.x + rect.x, origin.y + rect.y,
                                                                           rect.width, rect.height))
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    reports.selectionText = strings.joined()
                                    reports.selectionSlices = slices
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                    }
                }.frame(width: 480, height: 640)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// The same native composition as a Markdown table: all Grid cells inside a
/// horizontal ScrollView, itself a row in the outer vertical lazy document.
private struct BlackboardTable: View {
    let number: Int
    var body: some View {
        ScrollView(.horizontal) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(0..<24) { row in
                    GridRow {
                        ForEach(0..<4) { column in
                            if column > 0 {
                                Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 0.5)
                            }
                            (Text("\(number).\(row).\(column) ").bold()
                             + Text(String(repeating: "表格内容，mixed text\n", count: 1 + (row + column) % 3)))
                                .backgroundPreferenceValue(Text.LayoutKey.self) { texts in
                                    Color.clear.anchorPreference(key: ParagraphAnchors.self, value: .bounds) {
                                        [ParagraphAnchor(bounds: $0, texts: texts)]
                                    }
                                }
                                .padding(8)
                                .frame(maxHeight: .infinity, alignment: .leading)
                                .gridColumnAlignment(.leading)
                        }
                    }
                    if row < 23 { Divider() }
                }
            }
        }.scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }
}

final class WinUIMarkdownScrollTests: XCTestCase {
    func testDocumentAnchorCoordinatesPreserveDrawingTransforms() throws {
        try onUIThread {
            let head = State(wrappedValue: 20.0)
            let host = WinUIRenderer.running {
                ScrollView {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: head.wrappedValue)
                        Text("document anchor")
                    }.frame(height: 1_000)
                }
            }
            for _ in 0..<12 { host.step() }
            let label = try XCTUnwrap(host.views(WinUILabelView.self).first)
            let report = label.frameReport(safeArea: Rect(0, 0, 500, 500))
            XCTAssertEqual(report.count, 13)
            let cache = WinUIFrameReportCache()
            let cached = label.frameReport(safeArea: Rect(0, 0, 500, 500), cache: cache, generation: 1)
            XCTAssertEqual(cached, report)
            label.setTransform(HostDrawingTransform(translationX: 17))
            let translated = label.frameReport(safeArea: Rect(0, 0, 500, 500), cache: cache, generation: 2)
            XCTAssertEqual(translated.count, 10)
            XCTAssertEqual(translated[4], report[4] + 17, accuracy: 0.001)
            label.setTransform(.identity)
            let parent = try XCTUnwrap(label.placingLayout)
            parent.setTransform(HostDrawingTransform(translationY: 23))
            let ancestorTranslated = label.frameReport(safeArea: Rect(0, 0, 500, 500), cache: cache, generation: 3)
            XCTAssertEqual(ancestorTranslated.count, 10)
            XCTAssertEqual(ancestorTranslated[5], report[5] + 23, accuracy: 0.001)
            parent.setTransform(.identity)
            head.wrappedValue = 45
            for _ in 0..<12 { host.step() }
            let resized = label.frameReport(safeArea: Rect(0, 0, 500, 500), cache: cache, generation: 4)
            XCTAssertEqual(resized.count, 13)
            XCTAssertEqual(resized, label.frameReport(safeArea: Rect(0, 0, 500, 500)),
                           "a later layout must replace all cached ancestor positions")
            XCTAssertNotEqual(resized[12], report[12])
        }
    }

    /// Read the pixels Windows is presenting, including the popup. A logical offset or an offscreen
    /// RenderTargetBitmap cannot tell us whether the user can actually see the scrolling document.
    @MainActor private static func assertPresented(_ scroll: WinUIScrollView, in window: HWND,
                                           file: StaticString = #filePath, line: UInt = #line) {
        let frame = scroll.scroller.laidOutFrame
        let origin = scroll.scroller.origin
        let scale = Double(GetDpiForWindow(window)) / 96
        guard frame.width > 64, frame.height > 64 else {
            return XCTFail("the visible scroll viewport collapsed: \(frame)", file: file, line: line)
        }
        guard let dc = GetDC(nil) else { return XCTFail("desktop pixels unavailable", file: file, line: line) }
        defer { _ = ReleaseDC(nil, dc) }
        var screenOrigin = POINT(x: LONG(origin.x * scale), y: LONG(origin.y * scale))
        guard ClientToScreen(window, &screenOrigin), let copy = CreateCompatibleDC(dc) else {
            return XCTFail("cannot read the displayed viewport", file: file, line: line)
        }
        defer { _ = DeleteDC(copy) }
        let width = Int((frame.width * scale).rounded(.up))
        let height = Int((frame.height * scale).rounded(.up))
        for (x, y) in [(32.0, 24.0), (frame.width - 32, 24),
                       (32, frame.height - 24), (frame.width - 32, frame.height - 24),
                       (frame.width / 2, frame.height / 2)] {
            let point = POINT(x: screenOrigin.x + LONG(x * scale), y: screenOrigin.y + LONG(y * scale))
            guard GetAncestor(WindowFromPoint(point), UINT(GA_ROOTOWNER)) == window else {
                return XCTFail("scroll content is outside or obscured by another window", file: file, line: line)
            }
        }
        var info = BITMAPINFO()
        info.bmiHeader.biSize = DWORD(MemoryLayout<BITMAPINFOHEADER>.size)
        info.bmiHeader.biWidth = LONG(width)
        info.bmiHeader.biHeight = -LONG(height)
        info.bmiHeader.biPlanes = 1
        info.bmiHeader.biBitCount = 32
        info.bmiHeader.biCompression = DWORD(BI_RGB)
        var storage: UnsafeMutableRawPointer?
        guard let bitmap = CreateDIBSection(dc, &info, UINT(DIB_RGB_COLORS), &storage, nil, 0),
              let bytes = storage?.assumingMemoryBound(to: UInt32.self) else {
            return XCTFail("cannot allocate a viewport pixel sample", file: file, line: line)
        }
        let previous = SelectObject(copy, bitmap)
        defer { _ = SelectObject(copy, previous); _ = DeleteObject(bitmap) }
        // Copy once: thousands of individual GetPixel calls would stall the very UI thread being tested.
        guard BitBlt(copy, 0, 0, Int32(width), Int32(height), dc, screenOrigin.x, screenOrigin.y, DWORD(SRCCOPY)) else {
            return XCTFail("cannot sample the displayed viewport", file: file, line: line)
        }
        _ = GdiFlush()
        var painted = 0
        var ink = 0
        var samples = 0
        for y in stride(from: 24.0, to: frame.height - 24, by: 12) {
            for x in stride(from: 32.0, to: frame.width - 32, by: 12) {
                let pixel = bytes[Int(y * scale) * width + Int(x * scale)]
                let b = Int(pixel & 255), g = Int((pixel >> 8) & 255), r = Int((pixel >> 16) & 255)
                if b > 235, r >= 210, r <= 230, g >= 170, g <= 240 { painted += 1 }
                if max(r, g, b) < 120 { ink += 1 }
                samples += 1
            }
        }
        XCTAssertGreaterThan(samples, 500, file: file, line: line)
        XCTAssertGreaterThan(painted, samples / 2, "most of the visible viewport must contain painted paragraph bodies", file: file, line: line)
        XCTAssertGreaterThan(ink, 10, "visible paragraphs must contain painted text", file: file, line: line)
        print("BLACKBOARD presented samples=\(samples) paragraphPixels=\(painted) textPixels=\(ink)")
    }

    func testBlackboardPopoverScrollSettlesWithSelectionGeometry() throws {
        try checkBlackboardScroll(tables: false)
    }

    func testBlackboardTablesScrollSettlesWithSelectionGeometry() throws {
        try checkBlackboardScroll(tables: true)
    }

    private func checkBlackboardScroll(tables: Bool) throws {
        try onUIThread {
            let reports = BlackboardReports()
            let host = WinUIRenderer.running(reducesMotion: true, room: LayoutSize(width: 700, height: 760)) {
                BlackboardFixture(reports: reports, tables: tables)
            }
            let window = try XCTUnwrap(host.window)
            let title = "SOUI Blackboard visible scroll regression"
            window.setTitle(title)
            window.request(WindowFrame(x: 0, y: 0))
            let name = Array(title.utf16) + [0]
            let hwnd = try XCTUnwrap(name.withUnsafeBufferPointer { FindWindowW(nil, $0.baseAddress) })
            _ = SetForegroundWindow(hwnd)
            XCTAssertTrue(SetWindowPos(hwnd, HWND(bitPattern: -1), 0, 0, 0, 0, UINT(SWP_NOMOVE | SWP_NOSIZE)))
            defer { _ = SetWindowPos(hwnd, HWND(bitPattern: -2), 0, 0, 0, 0, UINT(SWP_NOMOVE | SWP_NOSIZE)) }
            for _ in 0..<12 { host.step() }
            WinUIScrollWork.install()
            defer { WinUIScrollWork.finish() }
            let opened = WinUIFrameClock.monotonic()
            try XCTUnwrap(host.views(WinUIButtonView.self).first).clicked()
            WinUIScrollWork.record("open", since: opened)
            for _ in 0..<20 { host.step() }
            let scroll = try XCTUnwrap(host.views(WinUIScrollView.self).first)
            let lazy = try XCTUnwrap(host.views(WinUILazyView.self).first)
            let popover = try XCTUnwrap(host.views(WinUIPopoverView.self).first)
            for _ in 0..<20 { host.step() }
            let root = try XCTUnwrap(host.window?.content)
            let viewport = scroll.scroller.laidOutFrame
            let corner = scroll.scroller.origin
            print("BLACKBOARD visible origin=\(corner) viewport=\(viewport) window=\(root.laidOutFrame)")
            XCTAssertGreaterThan(viewport.height, 500)
            XCTAssertGreaterThanOrEqual(corner.y, 0)
            XCTAssertLessThanOrEqual(corner.y + viewport.height, root.origin.y + root.laidOutFrame.height + 1,
                                     "the whole scroll viewport must be visible inside the test window")
            Self.assertPresented(scroll, in: hwnd)
            XCTAssertGreaterThan(reports.lines, 0)
            XCTAssertGreaterThan(reports.selectionSlices.count, 500,
                                 "selection must consume the laid-out glyphs, not only line counts")
            XCTAssertTrue(reports.selectionText.contains("中文") || reports.selectionText.contains("蓝色"))
            XCTAssertGreaterThan(lazy.cells.extents.estimate, 150,
                                 "tall Markdown must not keep a 44-DIP document estimate")
            XCTAssertGreaterThan(scroll.scroller.standing.reach.y, 8_000,
                                 "the native scroll range must include estimated unseen paragraphs")
            for label in host.views(WinUILabelView.self) {
                if let publish = label.onTextLayout {
                    label.onTextLayout = { report in reports.textReports += 1; publish(report) }
                }
            }
            print("BLACKBOARD opened rows=\(lazy.mounted.count) extent=\(lazy.cells.total) reach=\(scroll.scroller.standing.reach.y)")
            WinUIScrollWork.finish(phase: "opening")
            WinUIScrollWork.install()
            let inspecting = ProcessInfo.processInfo.environment["SOUI_BLACKBOARD_INSPECT"] == "1"
            if inspecting { Inspection.start() }
            defer {
                if inspecting {
                    Inspection.stop()
                    for pass in Inspection.passes.sorted(by: { $0.describe > $1.describe }).prefix(4) {
                        print("BLACKBOARD inspect describe=\(pass.describe / 1_000) apply=\((pass.host?.apply ?? 0) / 1_000) made=\(pass.host?.made ?? 0) causes=\(pass.causes)")
                        for entry in pass.entries.sorted(by: { $0.own > $1.own }).prefix(6) {
                            print("BLACKBOARD ownms=\(entry.own / 1_000) type=\(entry.view) outcome=\(entry.outcome)")
                        }
                    }
                }
            }
            let presenter = BlackboardPresenter(host)
            host.runtime.displayCycle.presenter = presenter
            defer { host.runtime.displayCycle.presenter = host; withExtendedLifetime(presenter) {} }
            let scale = Double(GetDpiForWindow(hwnd)) / 96
            var probePoint = POINT(x: LONG((corner.x + (tables ? 20 : viewport.width - 20)) * scale),
                                   y: LONG((corner.y + 24) * scale))
            XCTAssertTrue(ClientToScreen(hwnd, &probePoint))
            let probe = BlackboardPaintProbe(window: hwnd, point: probePoint,
                                            width: tables ? Int((viewport.width - 40) * scale) : 1,
                                            height: Int((viewport.height - 48) * scale), scale: scale)
            let rawProbe = Unmanaged.passRetained(probe).toOpaque()
            let created = CreateThread(nil, 0, BlackboardPaintProbe.entry, rawProbe, 0, nil)
            if created == nil { Unmanaged<BlackboardPaintProbe>.fromOpaque(rawProbe).release() }
            let thread = try XCTUnwrap(created)
            defer {
                probe.lock.lock(); probe.stopped = true; probe.lock.unlock()
                XCTAssertEqual(WaitForSingleObject(thread, 2_000), 0)
                _ = CloseHandle(thread)
                print("BLACKBOARD compositor samples=\(probe.gaps.count) longestGap=\(probe.gaps.max() ?? 0) gapsOver14=\(probe.gaps.filter { $0 > 14 }.count) inkless=\(probe.inklessSamples) obscured=\(probe.obscured)")
                for target in probe.phaseGaps.keys.sorted() {
                    let gaps = probe.phaseGaps[target, default: []]
                    print("BLACKBOARD compositor target=\(target) samples=\(gaps.count) maxGap=\(gaps.max() ?? 0) over14=\(gaps.filter { $0 > 14 }.count)")
                }
                XCTAssertGreaterThan(probe.gaps.count, 30)
                XCTAssertEqual(probe.obscured, 0, "obscured samples cannot verify white gaps")
                XCTAssertEqual(probe.inklessSamples, 0, "a painted table background without cell text is still blank")
                // Twelve-DIP paragraph spacing plus pixel-rounding tolerance.
                XCTAssertLessThanOrEqual(probe.gaps.max() ?? 0, 14,
                                         "the compositor must not expose blanks beyond paragraph spacing")
            }
            let targets: [Double] = tables ? [80, 160, 320, 640, 1_200, 2_400, 4_800, 9_600, 0]
                : [80, 160, 320, 640, 1_200, 2_400, 0]
            for target in targets {
                guard popover.showsCard else {
                    XCTFail("the popover was dismissed; offsets after dismissal cannot validate scrolling")
                    return
                }
                let previousReports = reports.changes
                probe.lock.lock(); probe.phase = target; probe.lock.unlock()
                swiftomniui_winui_scroller_move(scroll.scroller.handle, 0, target, true)
                for _ in 0..<32 { host.step() }
                host.settle { !scroll.held && !host.runtime.lazyPrefetch.isPending && !WinUIDoorbell.hasPendingWork }
                print("BLACKBOARD target=\(target) offset=\(scroll.scroller.standing.offset.y) rows=\(lazy.mounted.count) extent=\(lazy.cells.total) requests=\(lazy.cells.requests) reports=\(reports.changes) textReports=\(reports.textReports) open=\(popover.showsCard) viewport=\(scroll.scroller.laidOutFrame)")
                XCTAssertEqual(scroll.scroller.standing.offset.y, target, accuracy: 1,
                               "a requested move is not evidence that scrolling actually happened")
                XCTAssertFalse(scroll.held)
                Self.assertPresented(scroll, in: hwnd)
                if target == 80 || target == 160 {
                    XCTAssertEqual(reports.changes, previousReports,
                                   "scrolling unchanged paragraphs must not rebuild selection geometry")
                }
            }
            let requests = lazy.cells.requests
            let changes = reports.changes
            for _ in 0..<20 { host.step() }
            XCTAssertEqual(lazy.cells.requests, requests)
            XCTAssertEqual(reports.changes, changes, "selection geometry must settle without a feedback loop")
            XCTAssertLessThan(lazy.mounted.count, 30)
        }
    }
}
