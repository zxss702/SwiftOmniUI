// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest
import WinSDK

/// A page and its counter: a click raises the count, and the caption reads it.
struct CounterPage: View {
    @State private var count = 0

    var body: some View {
        VStack {
            Text("count \(count)")
            Button("Add")
                .onClicked { count += 1 }
        }
    }
}

final class WinUIRendererTests: XCTestCase {
    /// A page's controls are WinUI's, shown in a window: the words it describes are the words WinUI holds.
    func testThePageShowsItsControlsInAWindow() {
        onUIThread {
            let host = WinUIRenderer.running { CounterPage() }

            XCTAssertEqual(host.views(WinUILabelView.self).map(\.text), ["count 0"])
            XCTAssertEqual(host.views(WinUIButtonView.self).map(\.text), ["Add"])
            XCTAssertNotNil(host.window?.content, "the window shows no page")
        }
    }

    /// A test's window stands in the tests' room whatever the screen: Windows gives a window three quarters of it,
    /// and a runner's screen of 1024 x 768 stood the split view's sidebar over its detail.
    func testATestsWindowStandsInItsRoomWhateverTheScreen() throws {
        try onUIThread {
            let host = WinUIRenderer.running { CounterPage() }
            var frame = [Double](repeating: 0, count: 13)
            swiftomniui_winui_window_frame(try XCTUnwrap(host.window).handle, &frame)
            XCTAssertEqual(frame[2], WinUITestHost.room.width, accuracy: 0.5)
            XCTAssertEqual(frame[3], WinUITestHost.room.height, accuracy: 0.5)
        }
    }

    /// The proof of the host's spine: the click reaches the handler, the state it wrote renders, and the patch
    /// reaches WinUI.
    func testAClickRendersWhatItsHandlerChanged() throws {
        try onUIThread {
            let host = WinUIRenderer.running { CounterPage() }
            let button = try XCTUnwrap(host.views(WinUIButtonView.self).first)

            button.invoke()
            button.invoke()

            XCTAssertEqual(host.views(WinUILabelView.self).map(\.text), ["count 2"])
        }
    }

    func testAControlNoRegistrationAnswersShowsItsName() {
        onUIThread {
            let host = WinUIRenderer.running { VStack { PositionIndicator() } }

            XCTAssertEqual(host.views(WinUIUnsupportedView.self).map(\.text), ["WinUI: unsupported PositionIndicator"])
        }
    }

    /// Every callback the relay declares is set: the relay calls them unchecked, and one left empty is a jump to nothing.
    func testEveryCallbackTheRelayMakesIsSet() {
        let fields = Mirror(reflecting: WinUICallbacks.table).children

        XCTAssertEqual(fields.count, 35, "the relay's callbacks changed; this test names how many there are")
        for field in fields {
            let value = Mirror(reflecting: field.value)
            XCTAssertFalse(value.displayStyle == .optional && value.children.isEmpty, "\(field.label ?? "?") is not set")
        }
    }

    /// A window the tree closes tells nothing: WinUI says it closed, and that is the tree's own closing.
    func testAWindowTheTreeClosesTellsNothing() throws {
        try onUIThread {
            let host = WinUIRenderer.running { PhasePage() }
            let window = try XCTUnwrap(host.window)
            let before = host.views(WinUILabelView.self).map(\.text)

            window.close()
            for _ in 0..<10 { host.step() }

            XCTAssertEqual(host.views(WinUILabelView.self).map(\.text), before, "no phase, no going")
        }
    }

    /// A window minimized and restored as the user does it - WinUI telling its activation, its presenter and its
    /// visibility in whatever order it tells them - stops, then stands again.
    func testAMinimizedWindowIsStoppedWhateverOrderWinUITellsIt() throws {
        try onUIThread {
            let host = WinUIRenderer.running { PhasePage() }
            let window = try XCTUnwrap(host.window)
            let said = { host.views(WinUILabelView.self).map(\.text).first ?? "" }

            swiftomniui_winui_window_show_as_user(window.handle, 6)
            host.settle(until: { said().hasSuffix("stopped") })
            XCTAssertEqual(said(), "background stopped")

            swiftomniui_winui_window_show_as_user(window.handle, 9)
            host.settle(until: { !said().hasSuffix("stopped") })
            XCTAssertFalse(said().contains("background"), said())
            XCTAssertFalse(said().hasSuffix("stopped"), said())
        }
    }

    /// Native owner ordering is reserved for a group's explicit floating policy.
    func testAnExplicitlyFloatingToolBelongsToTheMainWindow() throws {
        try onUIThread {
            let host = WinUIRenderer.running(application: { ToolApplication(floating: true) })
            let open = try XCTUnwrap(host.views(WinUIButtonView.self).first)

            swiftomniui_winui_button_invoke(open.handle)
            for _ in 0..<30 where host.windows.count < 2 { host.step() }
            XCTAssertEqual(host.windows.count, 2)
            guard host.windows.count == 2 else { return }
            let (main, tool) = (host.windows[0].window, host.windows[1].window)
            XCTAssertTrue(swiftomniui_winui_window_belongs_to(tool.handle, main.handle))
            XCTAssertFalse(swiftomniui_winui_window_belongs_to(main.handle, tool.handle))
        }
    }

    func testAnOrdinaryGroupedWindowHasNoNativeOwner() throws {
        try onUIThread {
            let host = WinUIRenderer.running(application: { ToolApplication() })
            let open = try XCTUnwrap(host.views(WinUIButtonView.self).first)
            swiftomniui_winui_button_invoke(open.handle)
            host.settle { host.windows.count == 2 }
            XCTAssertEqual(host.windows.count, 2)
            guard host.windows.count == 2 else { return }
            let (main, other) = (host.windows[0].window, host.windows[1].window)
            let mainHandle = try nativeHandle(main, title: "SOUITest-main-\(main.number)")
            let otherHandle = try nativeHandle(other, title: "SOUITest-group-\(other.number)")
            XCTAssertNil(GetWindow(mainHandle, UINT(GW_OWNER)))
            XCTAssertNil(GetWindow(otherHandle, UINT(GW_OWNER)), "a grouped window must be an independent top-level window")
            XCTAssertFalse(swiftomniui_winui_window_belongs_to(other.handle, main.handle))
            XCTAssertFalse(swiftomniui_winui_window_belongs_to(main.handle, other.handle))
            for window in [main, other] {
                var frame = [Double](repeating: 0, count: 13)
                swiftomniui_winui_window_frame(window.handle, &frame)
                XCTAssertEqual(frame[11], 0, "ordinary windows do not request a topmost presenter")
            }

            // Ask WinUI to activate each window and inspect the actual native
            // order. Never force an order with SetWindowPos/BringWindowToTop.
            for (window, front, back) in [(main, mainHandle, otherHandle),
                                           (other, otherHandle, mainHandle),
                                           (main, mainHandle, otherHandle)] {
                swiftomniui_winui_window_activate(window.handle)
                host.settle { GetActiveWindow() == front && Self.isAbove(front, back) }
                XCTAssertEqual(GetActiveWindow(), front)
                XCTAssertTrue(Self.isAbove(front, back), "native activation must raise an ordinary window above its peer")
                host.step()
                XCTAssertTrue(Self.isAbove(front, back), "a presentation update must preserve the system's order")
            }
        }
    }

    @MainActor private func nativeHandle(_ window: WinUIWindow, title: String) throws -> HWND {
        window.setTitle(title)
        let name = Array(title.utf16) + [0]
        return try XCTUnwrap(name.withUnsafeBufferPointer { FindWindowW(nil, $0.baseAddress) })
    }

    private static func isAbove(_ front: HWND, _ back: HWND) -> Bool {
        var next = GetTopWindow(nil)
        while let window = next {
            if window == front { return true }
            if window == back { return false }
            next = GetWindow(window, UINT(GW_HWNDNEXT))
        }
        return false
    }

    /// The page reads the screen its window stands on: its size, and how it is turned - not at all on this machine.
    func testThePageReadsTheScreenItStandsOn() {
        onUIThread {
            let host = WinUIRenderer.running { DisplayPage() }
            host.settle { host.views(WinUILabelView.self).first?.text != "0 unknown" }

            let words = host.views(WinUILabelView.self).first?.text.split(separator: " ") ?? []
            XCTAssertGreaterThan(Double(words.first ?? "") ?? 0, 0, "a width")
            XCTAssertEqual(words.last, "rotation0", "a screen standing as it is made")
        }
    }

    /// The environment is Windows' own: the page reads a desktop running Windows, and the system's color scheme as Windows
    /// has it now.
    func testThePageReadsWindowsAndItsTheme() {
        onUIThread {
            let host = WinUIRenderer.running { EnvironmentPage() }
            var bytes = [CChar](repeating: 0, count: 8)
            _ = swiftomniui_winui_facts(SwiftOmniUIFactsTheme, nil, &bytes, 8)
            let dark = bytes[0] == 0x31

            XCTAssertEqual(host.views(WinUILabelView.self).map(\.text), ["Windows desktop", dark ? "dark" : "light"])
        }
    }
}

/// A page saying the application's phase and its window's.
private struct PhasePage: View {
    @Environment private var application: ApplicationSession
    @Environment private var window: WindowSession

    var body: some View {
        Text("\(application.phase) \(window.phase)")
    }
}

/// An application whose main window opens a tool window of its scene.
private struct ToolApplication: App {
    var floating = false
    var body: some Scene { ToolScene(floating: floating) }
}

private struct ToolScene: Scene {
    var floating: Bool
    var windows: Windows {
        Windows({ WindowGroup(WindowType("renderer.tool")) { ToolWindow() }.floatsOnTop(floating) },
                main: { ToolMainWindow() })
    }
}

private struct ToolMainWindow: WindowScene {
    var page: any Page { ToolOpeningPage() }
}

private struct ToolOpeningPage: View {
    @Environment private var scene: SceneSession

    var body: some View {
        let scene = self.scene
        return Button("Tool").onClicked { try await scene.openWindow(WindowType("renderer.tool")) }
    }
}

private struct ToolWindow: WindowScene {
    var page: any Page { Text("A tool") }
}

/// A page saying the screen's width and turn.
private struct DisplayPage: View {
    @Environment private var display: DeviceDisplay

    var body: some View {
        Text("\(Int(display.width)) \(display.rotation)")
    }
}

/// A page saying what it runs on and the color scheme it runs in.
private struct EnvironmentPage: View {
    @Environment private var device: DeviceInfo
    @Environment private var app: AppInfo

    var body: some View {
        VStack {
            Text("\(device.platform) \(device.formFactor)")
            Text("\(app.colorScheme)")
        }
    }
}
