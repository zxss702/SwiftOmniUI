// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIGTK
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIGTK
import XCTest

final class GTKNavigationTitleTests: XCTestCase {
    /// The application's three-column editor puts its title on the outer split, under a frame modifier.
    func testTextTitlesOnTheOuterSplitReachTheNativeHeadingAndFollowChanges() throws {
        try onUIThread {
            let title = State(wrappedValue: "SwiftOmniUI"), subtitle = State(wrappedValue: "新对话")
            let path = State(wrappedValue: [Int]())
            let host = GTKRenderer.running(reducesMotion: true) {
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
            let navigation = try XCTUnwrap(host.views(GTKNavigationView.self).first)
            let frame = try XCTUnwrap(navigation.frames.first)
            XCTAssertEqual(try heading(frame).title, "SwiftOmniUI")
            XCTAssertEqual(try heading(frame).subtitle, "新对话")
            XCTAssertEqual(host.windowTitle, "SwiftOmniUI")

            title.wrappedValue = "Logorythia"
            subtitle.wrappedValue = "规划会话"
            host.step()
            XCTAssertEqual(try heading(frame).title, "Logorythia")
            XCTAssertEqual(try heading(frame).subtitle, "规划会话")
            XCTAssertEqual(host.windowTitle, "Logorythia")
            XCTAssertTrue(navigation.frames.first === frame)

            path.wrappedValue = [1]
            host.settle { navigation.frames.count == 2 }
            let pushed = try XCTUnwrap(navigation.frames.last)
            XCTAssertEqual(try heading(pushed).title, "File.swift")
            XCTAssertEqual(try heading(pushed).subtitle, "编辑文件")
            XCTAssertEqual(host.windowTitle, "File.swift")
            path.wrappedValue = []
            host.settle { navigation.frames.count == 1 }
            XCTAssertTrue(navigation.frames.first === frame)
            XCTAssertEqual(try heading(frame).title, "Logorythia")
            XCTAssertEqual(try heading(frame).subtitle, "规划会话")

            title.wrappedValue = ""
            subtitle.wrappedValue = ""
            host.step()
            XCTAssertEqual(try heading(frame).title, "")
            XCTAssertEqual(try heading(frame).subtitle, "")
            XCTAssertEqual(host.windowTitle, "")
        }
    }

    func testATitleBoundOnOrdinaryContentRefreshesTheNativeHeading() throws {
        try onUIThread {
            let title = State(wrappedValue: "Before")
            let host = GTKRenderer.running(reducesMotion: true) {
                VStack { Text("Body").navigationTitle(title.projectedValue) }.navigationSubtitle("Subtitle")
            }
            let frame = try XCTUnwrap(host.window?.pageFrame)
            XCTAssertEqual(try heading(frame).title, "Before")
            title.wrappedValue = "After"
            host.step()
            XCTAssertEqual(try heading(frame).title, "After")
            XCTAssertEqual(try heading(frame).subtitle, "Subtitle")
            XCTAssertTrue(host.window?.pageFrame === frame)
        }
    }

    @MainActor private func heading(_ frame: GTKPageFrame) throws -> (title: String, subtitle: String) {
        let widget = try XCTUnwrap(adw_header_bar_get_title_widget(frame.header.opaque))
        XCTAssertNotEqual(g_type_check_instance_is_a(widget.of(GTypeInstance.self), adw_window_title_get_type()), 0)
        return (String(cString: try XCTUnwrap(adw_window_title_get_title(widget.opaque))),
                String(cString: try XCTUnwrap(adw_window_title_get_subtitle(widget.opaque))))
    }
}
