// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import WinSDK
import XCTest

final class WinUIActivationTests: XCTestCase {
    func testReactivationReopensWelcomeAndRetainsTheEditor() throws {
        try onUIThread {
            let host = WinUIRenderer.running(application: { WinUIActivationApplication() })
            let welcome = try XCTUnwrap(host.windows.first?.window)
            try XCTUnwrap(host.views(WinUIButtonView.self).first { $0.text == "Open editor" }).invoke()
            host.settle { host.windows.count == 2 }
            let editor = try XCTUnwrap(host.windows.last?.window)
            XCTAssertFalse(editor === welcome)
            let label = try XCTUnwrap(host.views(WinUILabelView.self).first { $0.text == "Editor: 0" })
            try XCTUnwrap(host.views(WinUIButtonView.self).first { $0.text == "Change" }).invoke()
            XCTAssertEqual(label.text, "Editor: 1")

            let welcomeHandle = try nativeHandle(welcome)
            _ = SendMessageW(welcomeHandle, UINT(WM_CLOSE), 0, 0)
            host.settle { host.windows.count == 1 }
            XCTAssertTrue(host.windows.first?.window === editor)
            WinUICallbacks.table.activated?()
            host.settle { host.windows.count == 2 }
            let reopened = try XCTUnwrap(host.windows.first?.window)
            let reopenedHandle = try nativeHandle(reopened)
            let editorHandle = try nativeHandle(editor)
            host.settle { GetForegroundWindow() == reopenedHandle && Self.isAbove(reopenedHandle, editorHandle) }
            XCTAssertEqual(GetForegroundWindow(), reopenedHandle, "the reopened first window must be findable in front")
            XCTAssertTrue(Self.isAbove(reopenedHandle, editorHandle))
            XCTAssertFalse(reopened === welcome)
            XCTAssertTrue(host.windows.last?.window === editor)
            XCTAssertTrue(host.views(WinUILabelView.self).contains { $0 === label })
            XCTAssertEqual(label.text, "Editor: 1")

            swiftomniui_winui_window_activate(editor.handle)
            host.settle { GetForegroundWindow() == editorHandle }
            XCTAssertEqual(GetForegroundWindow(), editorHandle)
            for _ in 0..<5 { WinUICallbacks.table.activated?(); host.step() }
            host.settle { GetForegroundWindow() == reopenedHandle && Self.isAbove(reopenedHandle, editorHandle) }
            XCTAssertEqual(GetActiveWindow(), reopenedHandle)
            XCTAssertEqual(GetForegroundWindow(), reopenedHandle, "reusing a window must bring it to the desktop foreground")
            XCTAssertTrue(Self.isAbove(reopenedHandle, editorHandle))
            XCTAssertEqual(GetWindowLongPtrW(reopenedHandle, Int32(GWL_EXSTYLE)) & LONG_PTR(WS_EX_TOPMOST), 0,
                           "foreground activation must not make the window permanently topmost")
            XCTAssertEqual(host.windows.count, 2)
            XCTAssertTrue(host.windows.first?.window === reopened)
            XCTAssertTrue(host.windows.last?.window === editor)

            _ = SendMessageW(reopenedHandle, UINT(WM_CLOSE), 0, 0)
            _ = SendMessageW(editorHandle, UINT(WM_CLOSE), 0, 0)
            host.settle { host.windows.isEmpty }
            XCTAssertTrue(host.windows.isEmpty)
            XCTAssertTrue(host.runtime.tree.root?.windows.isEmpty == true)
        }
    }

    func testReactivationRestoresTheMinimizedWelcomeWithoutDuplicatingIt() throws {
        try onUIThread {
            let host = WinUIRenderer.running(application: { WinUIActivationApplication() })
            let welcome = try XCTUnwrap(host.windows.first?.window)
            let handle = try nativeHandle(welcome)
            swiftomniui_winui_window_show_as_user(welcome.handle, 6)
            host.settle { IsIconic(handle) != 0 }
            XCTAssertNotEqual(IsIconic(handle), 0)

            for _ in 0..<5 { WinUICallbacks.table.activated?(); host.step() }
            host.settle { IsIconic(handle) == 0 && GetForegroundWindow() == handle }
            XCTAssertEqual(IsIconic(handle), 0)
            XCTAssertEqual(GetActiveWindow(), handle)
            XCTAssertEqual(GetForegroundWindow(), handle)
            XCTAssertEqual(host.windows.count, 1)
            XCTAssertTrue(host.windows.first?.window === welcome)
        }
    }

    func testReactivationShowsAHiddenWelcomeInFrontWithoutDuplicatingIt() throws {
        try onUIThread {
            let host = WinUIRenderer.running(application: { WinUIActivationApplication() })
            let welcome = try XCTUnwrap(host.windows.first?.window)
            try XCTUnwrap(host.views(WinUIButtonView.self).first { $0.text == "Open editor" }).invoke()
            host.settle { host.windows.count == 2 }
            let editor = try XCTUnwrap(host.windows.last?.window)
            let welcomeHandle = try nativeHandle(welcome), editorHandle = try nativeHandle(editor)
            swiftomniui_winui_window_set_shown(welcome.handle, false)
            swiftomniui_winui_window_activate(editor.handle)
            host.settle { IsWindowVisible(welcomeHandle) == 0 && GetForegroundWindow() == editorHandle }
            XCTAssertEqual(IsWindowVisible(welcomeHandle), 0)

            WinUICallbacks.table.activated?()
            host.settle { IsWindowVisible(welcomeHandle) != 0 && GetForegroundWindow() == welcomeHandle }
            XCTAssertNotEqual(IsWindowVisible(welcomeHandle), 0)
            XCTAssertEqual(GetForegroundWindow(), welcomeHandle)
            XCTAssertTrue(Self.isAbove(welcomeHandle, editorHandle))
            XCTAssertEqual(host.windows.count, 2)
            XCTAssertTrue(host.windows.first?.window === welcome)
            host.step()
            XCTAssertEqual(GetForegroundWindow(), welcomeHandle, "a later render must preserve the user's activation")
        }
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

    @MainActor private func nativeHandle(_ window: WinUIWindow) throws -> HWND {
        let title = "SOUITest-activation-\(window.number)"
        window.setTitle(title)
        let name = Array(title.utf16) + [0]
        return try XCTUnwrap(name.withUnsafeBufferPointer { FindWindowW(nil, $0.baseAddress) })
    }
}

private struct WinUIActivationApplication: App {
    var body: some Scene {
        Window("Welcome", id: "winui.activation.welcome") { WinUIActivationWelcome() }
        WindowGroup(WindowType("winui.activation.editor")) { Window { WinUIActivationEditor() } }
    }
}

private struct WinUIActivationWelcome: View {
    @Environment private var scene: SceneSession

    var body: some View {
        let scene = self.scene
        return Button("Open editor").onClicked { try await scene.openWindow(WindowType("winui.activation.editor")) }
    }
}

private struct WinUIActivationEditor: View {
    @State private var count = 0

    var body: some View {
        VStack {
            Text("Editor: \(count)")
            Button("Change").onClicked { count += 1 }
        }
    }
}
