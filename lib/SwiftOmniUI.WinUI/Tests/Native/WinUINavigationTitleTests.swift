// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

final class WinUINavigationTitleTests: XCTestCase {
    func testFirstNavigationDoesNotCorrectAnUndersizedInitialWindow() throws {
        try onUIThread {
            let path = State(wrappedValue: [Int]())
            let host = WinUIRenderer.running(reducesMotion: true) {
                NavigationStack(path.projectedValue) {
                    Text("Home").navigationTitle("Home")
                } destination: { number in
                    Text("Page \(number)")
                        .navigationTitle("Page \(number)")
                        .toolbar { ToolbarItem("Save", systemImage: "square.and.arrow.down") {} }
                }
                .frame(width: 720, height: 400)
            }
            let window = try XCTUnwrap(host.window)
            let content = try XCTUnwrap(window.content)
            XCTAssertEqual(content.laidOutFrame.height, 400, accuracy: 1,
                           "check the first completed layout before any navigation")
            let chrome = window.chromeHeight
            var initial = [Double](repeating: 0, count: 13)
            swiftomniui_winui_window_frame(window.handle, &initial)

            // First visit, back, revisit and a different destination. The
            // original failure grows only at the first of these boundaries.
            for route in [[1], [], [1], [2]] {
                path.wrappedValue = route
                host.runtime.pump.turn()
                host.layOut()
                var frame = [Double](repeating: 0, count: 13)
                swiftomniui_winui_window_frame(window.handle, &frame)
                XCTAssertEqual(Array(frame[0..<4]), Array(initial[0..<4]))
                XCTAssertEqual(window.chromeHeight, chrome, accuracy: 0.01)
                XCTAssertEqual(content.laidOutFrame.height, 400, accuracy: 1)
            }
        }
    }

    func testTextTitlesOnTheOuterSplitReachTheNativeTitleBarAndFollowChanges() throws {
        try onUIThread {
            let title = State(wrappedValue: "SwiftOmniUI"), subtitle = State(wrappedValue: "新对话")
            let path = State(wrappedValue: [Int]())
            let host = WinUIRenderer.running(reducesMotion: true) {
                NavigationSplitView(columnVisibility: State(wrappedValue: NavigationSplitViewVisibility.all).projectedValue) {
                    Text("Files")
                } content: {
                    NavigationStack(path.projectedValue) {
                        Text("Conversation")
                    } destination: { _ in
                        Text("File").navigationTitle(Text("File.swift")).navigationSubtitle(Text("编辑文件"))
                    }
                } detail: {
                    Text("Auxiliary").navigationSplitViewColumnWidth(0)
                }
                .overlay(alignment: .topTrailing) { Text("Overlay") }
                .navigationTitle(Text(title.wrappedValue))
                .navigationSubtitle(Text(subtitle.wrappedValue))
                .frame(minWidth: 640, minHeight: 320)
            }
            let bar = try XCTUnwrap(host.window).titleBar
            XCTAssertEqual(Self.read("title", of: bar), "SwiftOmniUI")
            XCTAssertEqual(Self.read("subtitle", of: bar), "新对话")

            title.wrappedValue = "Logorythia"
            subtitle.wrappedValue = "规划会话"
            host.step()
            XCTAssertEqual(Self.read("title", of: bar), "Logorythia")
            XCTAssertEqual(Self.read("subtitle", of: bar), "规划会话")
            XCTAssertTrue(host.window?.titleBar === bar)

            path.wrappedValue = [1]
            host.settle { Self.read("title", of: bar) == "File.swift" }
            XCTAssertEqual(Self.read("title", of: bar), "File.swift")
            XCTAssertEqual(Self.read("subtitle", of: bar), "编辑文件")
            path.wrappedValue = []
            host.settle { Self.read("title", of: bar) == "Logorythia" }
            XCTAssertEqual(Self.read("title", of: bar), "Logorythia")
            XCTAssertEqual(Self.read("subtitle", of: bar), "规划会话")

            title.wrappedValue = ""
            subtitle.wrappedValue = ""
            host.step()
            XCTAssertEqual(Self.read("title", of: bar), "")
            XCTAssertEqual(Self.read("subtitle", of: bar), "")
        }
    }

    func testATitleBoundOnOrdinaryContentRefreshesTheNativeTitleBar() throws {
        try onUIThread {
            let title = State(wrappedValue: "Before")
            let host = WinUIRenderer.running(reducesMotion: true) {
                VStack { Text("Body").navigationTitle(title.projectedValue) }.navigationSubtitle("Subtitle")
            }
            let bar = try XCTUnwrap(host.window).titleBar
            XCTAssertEqual(Self.read("title", of: bar), "Before")
            title.wrappedValue = "After"
            host.step()
            XCTAssertEqual(Self.read("title", of: bar), "After")
            XCTAssertEqual(Self.read("subtitle", of: bar), "Subtitle")
            XCTAssertTrue(host.window?.titleBar === bar)
        }
    }

    /// Read the TitleBar's actual WinRT properties, rather than Swift's last composed chrome.
    @MainActor private static func read(_ property: String, of bar: WinUITitleBarView) -> String {
        var bytes = [CChar](repeating: 0, count: 512)
        let length = swiftomniui_winui_read(bar.handle, property, &bytes, Int32(bytes.count))
        XCTAssertGreaterThanOrEqual(length, 0)
        return String(decoding: bytes.prefix(Int(max(0, length))).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
