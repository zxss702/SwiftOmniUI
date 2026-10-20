// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

final class WinUINavigationTitleTests: XCTestCase {
    func testFirstVisitsWithDifferentToolbarsKeepTheWindowSizeAndCaptionRow() throws {
        try onUIThread {
            for split in [false, true] {
                let path = State(wrappedValue: [Int]())
                let query = State(wrappedValue: "")
                let sidebar = State(wrappedValue: true)
                let minimumHeight = split ? 320.0 : 480.0
                let room = split ? LayoutSize(width: 1100, height: 700) : LayoutSize(width: 800, height: 512)
                let host = WinUIRenderer.running(reducesMotion: true, room: room) {
                    let stack = NavigationStack(path.projectedValue) {
                        Text("Home").navigationTitle("Home")
                    } destination: { number in
                        Text("Page \(number)")
                            .navigationTitle("Page \(number)")
                            .toolbar {
                                ToolbarItem("Save", systemImage: "square.and.arrow.down") {}
                                ToolbarItem {
                                    Button(icon: .symbol("pencil")) {}.id("edit-command-\(number)")
                                }
                                ToolbarItem {
                                    Button("Options") {}.id("label-command-\(number)")
                                }
                                if number.isMultiple(of: 2) {
                                    ToolbarItem { SearchField(query.projectedValue).frame(width: 180) }
                                }
                            }
                    }
                    if split {
                        return NavigationSplitView(sidebar.projectedValue) {
                            Text("Files")
                        } detail: {
                            stack
                        }.frame(minWidth: 640, minHeight: minimumHeight)
                    }
                    return stack.frame(minWidth: 640, minHeight: minimumHeight)
                }
                let window = try XCTUnwrap(host.window)
                let content = try XCTUnwrap(window.content)
                var initial = [Double](repeating: 0, count: 13)
                swiftomniui_winui_window_frame(window.handle, &initial)

                // Every destination is new. Check the first completed native
                // pass as well as idle, rather than revisiting cached pages.
                for number in 1...5 {
                    path.wrappedValue.append(number)
                    host.runtime.pump.turn()
                    host.layOut()
                    for idle in [false, true] {
                        if idle { host.step() }
                        var frame = [Double](repeating: 0, count: 13)
                        swiftomniui_winui_window_frame(window.handle, &frame)
                        for axis in 0..<4 {
                            XCTAssertEqual(frame[axis], initial[axis], accuracy: 0.01,
                                           "first visit \(number), split=\(split), idle=\(idle), axis=\(axis)")
                        }
                        let caption = swiftomniui_winui_window_title_bar_height(window.handle)
                        XCTAssertEqual(window.chromeHeight, caption, accuracy: 0.01)
                        XCTAssertEqual(window.titleBar.laidOutFrame.height, caption, accuracy: 1)
                        XCTAssertEqual(content.origin.y, caption, accuracy: 1,
                                       "no extra strip below the native caption buttons")
                        for name in ["edit-command-\(number)", "label-command-\(number)"] {
                            let command = try XCTUnwrap(host.view(id: .manual(name)))
                            let height = command.laidOutFrame.height
                            XCTAssertGreaterThan(height, 0)
                            XCTAssertLessThan(height, caption, "commands leave room above and below")
                            XCTAssertEqual(command.origin.y + height / 2, caption / 2, accuracy: 1,
                                           "commands and native caption buttons share their vertical centre")
                        }
                    }
                }
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
