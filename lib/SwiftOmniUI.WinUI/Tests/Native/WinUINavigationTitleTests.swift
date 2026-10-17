// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

final class WinUINavigationTitleTests: XCTestCase {
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
