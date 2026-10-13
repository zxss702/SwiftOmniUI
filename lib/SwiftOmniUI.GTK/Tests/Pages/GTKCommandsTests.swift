// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIGTK
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIGTK
import SwiftOmniUIConformance
import XCTest

private struct CommandsApplication: App {
    var content: @Sendable @MainActor () -> any Page = { Text("Home") }
    var settingsTitle: @Sendable @MainActor () -> String = { "设置" }
    var settingsID: @Sendable @MainActor () -> String = { "settings" }
    var helpTitle: @Sendable @MainActor () -> String = { "帮助" }
    var showsCommands: @Sendable @MainActor () -> Bool = { true }
    var chosen = Received<String>()

    var body: some Scene {
        OneWindow(content: content)
            .commands {
                if showsCommands() {
                    CommandGroup(replacing: .appInfo) {
                        let id = settingsID()
                        Button { chosen.values.append(id) } label: {
                            Label(settingsTitle(), systemImage: "preferences-system-symbolic")
                        }
                        .id(id)
                        .keyboardShortcut(",", modifiers: .command)
                        Divider()
                        Button("开始页") { chosen.values.append("start") }
                    }
                    CommandMenu("工具") {
                        Button(helpTitle()) { chosen.values.append("help") }
                    }
                }
            }
    }
}

/// A composed view introduces a page wrapper around the arrangement, as an application's editor view does.
private struct CommandsSplitPage: View {
    let visible: Binding<Bool>

    var body: some View {
        NavigationSplitView(visible) {
            TitledPage(title: "Sidebar")
        } detail: {
            NavigationStack(State(wrappedValue: [Int]()).projectedValue) {
                TitledPage(title: "Editor")
            } destination: { number in
                TitledPage(title: "File \(number)")
            }
        }
        .navigationTitle("Wrapped editor")
    }
}

final class GTKCommandsTests: XCTestCase {
    /// Read the native popup, including its sections and submenu action states.
    @MainActor private func menu(_ frame: GTKPageFrame) throws -> String {
        let button = try XCTUnwrap(frame.appMenuButton)
        let model = try XCTUnwrap(gtk_menu_button_get_menu_model(button.widget.opaque))
        let menu = try XCTUnwrap(button.menu)
        XCTAssertNotEqual(gtk_widget_get_visible(button.widget), 0)
        XCTAssertNotEqual(gtk_widget_get_visible(frame.header), 0)
        XCTAssertNotEqual(gtk_widget_get_mapped(button.widget), 0, "the command button is on the displayed native header")
        XCTAssertNotEqual(gtk_widget_is_ancestor(button.widget, frame.header), 0)
        return GTKDriver.said(model, actions: menu.actions)
    }

    /// Commands reach GTK's model, and GTK's native action reaches the original button handler.
    func testAppInfoReplacementShowsLabelledButtonsAndRunsTheirActions() throws {
        try onUIThread {
            let chosen = Received<String>()
            let host = GTKRenderer.running(application: CommandsApplication(chosen: chosen))
            let frame = try XCTUnwrap(host.window?.pageFrame)
            XCTAssertEqual(try menu(frame), "设置;-;开始页;工具[帮助]")

            let button = try XCTUnwrap(frame.appMenuButton)
            XCTAssertNotEqual(gtk_widget_activate_action_variant(button.widget, GTKMenu.actionGroup + ".e0", nil), 0)
            XCTAssertEqual(chosen.values, ["settings"])
            XCTAssertNotEqual(gtk_widget_activate_action_variant(button.widget, GTKMenu.actionGroup + ".e1", nil), 0)
            XCTAssertEqual(chosen.values, ["settings", "start"])

            let model = gtk_menu_button_get_menu_model(button.widget.opaque)
            host.refreshChrome()
            XCTAssertTrue(frame.appMenuButton === button)
            XCTAssertEqual(gtk_menu_button_get_menu_model(button.widget.opaque), model, "unchanged commands keep their popup")
        }
    }

    /// The page wrapper is not the native header owner. The sidebar owns the commands while shown; hiding it
    /// moves them to the detail's navigation frame, exactly once.
    func testWrappedSplitMovesCommandsBetweenTheVisibleNativeHeaders() throws {
        try onUIThread {
            let visible = State(wrappedValue: true)
            let host = GTKRenderer.running(application: CommandsApplication(content: {
                CommandsSplitPage(visible: visible.projectedValue)
            }))
            let split = try XCTUnwrap(host.views(GTKSplitView.self).first)
            let navigation = try XCTUnwrap(host.views(GTKNavigationView.self).first)
            let sidebar = try XCTUnwrap(split.sidebarFrame)
            let detail = try XCTUnwrap(navigation.frames.last)
            XCTAssertEqual(try menu(sidebar), "设置;-;开始页;工具[帮助]")
            XCTAssertNil(detail.appMenuButton)
            XCTAssertNil(host.window?.pageFrame)

            let toggle = try XCTUnwrap(detail.sidebarToggle)
            toggle.click()
            XCTAssertFalse(split.isPresented)
            XCTAssertNil(sidebar.appMenuButton)
            XCTAssertEqual(try menu(detail), "设置;-;开始页;工具[帮助]")

            toggle.click()
            XCTAssertTrue(split.isPresented)
            XCTAssertEqual(try menu(sidebar), "设置;-;开始页;工具[帮助]")
            XCTAssertNil(detail.appMenuButton)
        }
    }

    func testThreeColumnCommandsFollowAllDoubleColumnAndDetailOnlyVisibility() throws {
        try onUIThread {
            let visibility = State(wrappedValue: NavigationSplitViewVisibility.all)
            let host = GTKRenderer.running(application: CommandsApplication(content: {
                NavigationSplitView(columnVisibility: visibility.projectedValue) {
                    TitledPage(title: "Sidebar")
                } content: {
                    TitledPage(title: "Content")
                } detail: {
                    TitledPage(title: "Detail")
                }
            }))
            let split = try XCTUnwrap(host.views(GTKSplitView.self).first)
            let sidebar = try XCTUnwrap(split.sidebarFrame)
            let content = try XCTUnwrap(split.contentFrame)
            let detail = try XCTUnwrap(split.detailFrame)
            XCTAssertEqual(try menu(sidebar), "设置;-;开始页;工具[帮助]")
            XCTAssertNil(content.appMenuButton)
            XCTAssertNil(detail.appMenuButton)

            visibility.wrappedValue = .doubleColumn
            host.runtime.pump.turn()
            XCTAssertNil(sidebar.appMenuButton)
            XCTAssertEqual(try menu(content), "设置;-;开始页;工具[帮助]")
            XCTAssertNil(detail.appMenuButton)

            visibility.wrappedValue = .detailOnly
            host.runtime.pump.turn()
            XCTAssertNil(sidebar.appMenuButton)
            XCTAssertNil(content.appMenuButton)
            XCTAssertEqual(try menu(detail), "设置;-;开始页;工具[帮助]")
        }
    }

    func testPushingAndPoppingKeepsCommandsOnlyOnTheTopNavigationFrame() throws {
        try onUIThread {
            let path = State(wrappedValue: [Int]())
            let host = GTKRenderer.running(application: CommandsApplication(content: {
                NavigationStack(path.projectedValue) {
                    TitledPage(title: "Root")
                } destination: { number in
                    TitledPage(title: "Page \(number)")
                }
            }))
            let navigation = try XCTUnwrap(host.views(GTKNavigationView.self).first)
            let root = try XCTUnwrap(navigation.frames.first)
            XCTAssertEqual(try menu(root), "设置;-;开始页;工具[帮助]")

            path.wrappedValue = [1]
            host.runtime.pump.turn()
            XCTAssertNil(root.appMenuButton)
            XCTAssertEqual(try menu(XCTUnwrap(navigation.frames.last)), "设置;-;开始页;工具[帮助]")

            XCTAssertTrue(host.goBack())
            XCTAssertTrue(navigation.frames.first === root)
            XCTAssertEqual(try menu(root), "设置;-;开始页;工具[帮助]")
        }
    }

    /// A tab's inner stack has different page identities from the tab frame supplying the native header.
    func testTabbedWindowKeepsCommandsOnItsOwnFrameAcrossSelectionChanges() throws {
        try onUIThread {
            let host = GTKRenderer.running(application: CommandsApplication(content: {
                TabView(["one", "two"]) { name in
                    NavigationStack(State(wrappedValue: [Int]()).projectedValue) {
                        TitledPage(title: name)
                    } destination: { number in TitledPage(title: "Page \(number)") }
                }
            }))
            let tabs = try XCTUnwrap(host.views(GTKTabbedView.self).first)
            let frame = try XCTUnwrap(host.window?.pageFrame)
            let button = try XCTUnwrap(frame.appMenuButton)
            XCTAssertEqual(try menu(frame), "设置;-;开始页;工具[帮助]")
            for index in [1, 0, 1, 0] {
                tabs.selectByUser(index)
                host.runtime.pump.turn()
                XCTAssertTrue(frame.appMenuButton === button)
                XCTAssertEqual(try menu(frame), "设置;-;开始页;工具[帮助]")
                XCTAssertTrue(host.views(GTKNavigationView.self).flatMap(\.frames).allSatisfy { $0.appMenuButton == nil })
            }
        }
    }

    /// Equal entry counts and captions cannot stand for equal actions or equal submenu contents.
    func testChangedCommandIdentityAndNestedCaptionsRefreshTheNativeMenu() throws {
        try onUIThread {
            let identity = State(wrappedValue: "first")
            let help = State(wrappedValue: "帮助")
            let chosen = Received<String>()
            let host = GTKRenderer.running(application: CommandsApplication(
                settingsID: { identity.wrappedValue }, helpTitle: { help.wrappedValue }, chosen: chosen))
            let frame = try XCTUnwrap(host.window?.pageFrame)
            let button = try XCTUnwrap(frame.appMenuButton)
            _ = gtk_widget_activate_action_variant(button.widget, GTKMenu.actionGroup + ".e0", nil)
            XCTAssertEqual(chosen.values, ["first"])

            identity.wrappedValue = "second"
            help.wrappedValue = "新帮助"
            host.runtime.pump.turn()
            XCTAssertEqual(try menu(frame), "设置;-;开始页;工具[新帮助]")
            _ = gtk_widget_activate_action_variant(button.widget, GTKMenu.actionGroup + ".e0", nil)
            XCTAssertEqual(chosen.values, ["first", "second"])
        }
    }

    func testRemovingCommandsRemovesTheNativeAppMenuButton() throws {
        try onUIThread {
            let visible = State(wrappedValue: true)
            let host = GTKRenderer.running(application: CommandsApplication(showsCommands: { visible.wrappedValue }))
            let frame = try XCTUnwrap(host.window?.pageFrame)
            XCTAssertEqual(try menu(frame), "设置;-;开始页;工具[帮助]")

            visible.wrappedValue = false
            host.runtime.pump.turn()
            XCTAssertNil(frame.appMenuButton)

            visible.wrappedValue = true
            host.runtime.pump.turn()
            XCTAssertEqual(try menu(frame), "设置;-;开始页;工具[帮助]")
        }
    }
}
