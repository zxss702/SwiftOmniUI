// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
@testable import SwiftOmniUIWebViewWinUI
import XCTest

final class WinUIWebViewSDKTests: XCTestCase {
    func testReplacingHtmlAndRefreshingAtOneAddressUsesTheLatestDocument() {
        onUIThread {
            let window = WinUIWindow()
            let web = WinUIWebView()
            swiftomniui_winui_window_set_content(window.handle, web.element)
            swiftomniui_winui_window_activate(window.handle)
            defer {
                swiftomniui_winui_window_set_content(window.handle, nil)
                window.close()
            }
            let address = "https://sdk-upgrade.swiftomniui.invalid/document"
            var completion: WebNavigationResult?
            web.onNavigated = { result, _, _ in completion = result }
            for revision in 0..<5 {
                completion = nil
                let html = "<html><body>revision \(revision) 中文</body></html>"
                web.show(.html(html, baseUrl: address))
                Self.pump { completion != nil }
                XCTAssertEqual(completion, .success)
                XCTAssertEqual(web.read("document"), html)
                XCTAssertEqual(Self.body(of: web), "revision \(revision) 中文")

                completion = nil
                web.step(.refresh)
                Self.pump { completion != nil }
                XCTAssertEqual(completion, .success)
                XCTAssertEqual(web.read("document"), html, "refresh keeps the replacement document")
                XCTAssertEqual(Self.body(of: web), "revision \(revision) 中文")
            }
        }
    }

    @MainActor private static func body(of web: WinUIWebView) -> String? {
        var answer: String?
        var completed = false
        let task = Task { @MainActor in
            do { answer = try await web.evaluate("document.body.textContent") }
            catch { XCTFail("reading the rendered document failed: \(error)") }
            completed = true
        }
        pump { completed }
        if !completed {
            task.cancel()
            XCTFail("the rendered document did not answer")
        }
        return answer
    }

    @MainActor private static func pump(until done: () -> Bool) {
        for _ in 0..<1_000 {
            if done() { return }
            WinUITestHost.pump(0.01)
            _ = CoreLink().runJobs()
        }
    }
}
