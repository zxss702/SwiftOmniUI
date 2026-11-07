// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIGTK
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIGTK
import SwiftOmniUIConformance
import XCTest

final class GTKPagesTests: XCTestCase {
    /// Each page of a stack stands in a frame with its own header bar, named as the page says; the top page names
    /// the window; the user's back takes the top page off the path.
    func testAStacksPagesCarryTheirHeaderBarsAndTheWayBack() throws {
        try onUIThread {
            let path = State(wrappedValue: [Int]())
            let host = GTKRenderer.running {
                NavigationStack(path.projectedValue) {
                    TitledPage(title: "Root")
                } destination: { number in
                    TitledPage(title: "Detail \(number)")
                }
            }
            let navigation = try XCTUnwrap(host.views(GTKNavigationView.self).first)
            XCTAssertEqual(navigation.frames.map(\.chrome.title), ["Root"])
            XCTAssertEqual(host.windowTitle, "Root")
            XCTAssertFalse(host.goBack(), "no way back from the root")

            path.wrappedValue.append(7)
            host.runtime.pump.turn()
            XCTAssertEqual(navigation.frames.map(\.chrome.title), ["Root", "Detail 7"])
            XCTAssertEqual(navigation.visiblePageTitle, "Detail 7", "GTK shows the pushed page")
            XCTAssertEqual(host.windowTitle, "Detail 7")

            XCTAssertTrue(host.goBack())
            XCTAssertEqual(path.wrappedValue, [], "the user's back pops the page")
            XCTAssertEqual(navigation.frames.map(\.chrome.title), ["Root"])
            XCTAssertEqual(host.windowTitle, "Root")
        }
    }

    /// A push: the root navigates from and disappears, then the pushed page appears and is navigated to; a pop the
    /// other way - every phase rendered before the next is heard.
    func testAPushAndAPopAreHeardByThePagesInOrder() {
        onUIThread {
            let path = State(wrappedValue: [Int]())
            let log = Received<String>()
            let host = GTKRenderer.running {
                NavigationStack(path.projectedValue) {
                    TitledPage(title: "Root", log: log)
                } destination: { _ in
                    TitledPage(title: "Pushed", log: log)
                }
            }
            XCTAssertEqual(log.values, ["Root appearing", "Root navigatedTo"])

            log.values = []
            path.wrappedValue.append(1)
            host.runtime.pump.turn()
            XCTAssertEqual(log.values, [
                "Root navigatingFrom", "Root disappearing", "Root navigatedFrom",
                "Pushed appearing", "Pushed navigatedTo",
            ])

            // The popped page has left the tree, and a page that left hears nothing more.
            log.values = []
            XCTAssertTrue(host.goBack())
            XCTAssertEqual(log.values, ["Root appearing", "Root navigatedTo"])
        }
    }

    /// A page shown by itself stands in the window's own frame, its header bar the window's title bar.
    func testAPageByItselfStandsInAFrameWithItsHeaderBar() throws {
        try onUIThread {
            let host = GTKRenderer.running { TitledPage(title: "Alone") }
            let frame = try XCTUnwrap(host.window?.pageFrame)

            XCTAssertEqual(frame.chrome.title, "Alone")
            XCTAssertEqual(host.windowTitle, "Alone")
            XCTAssertTrue(gtk_widget_get_parent(frame.page.widget) != nil, "the page stands in the frame")
        }
    }

    /// The visible page's actions stand at its header bar's end in their priority's order, the overflow's behind the
    /// bar's menu; choosing one runs its handler, and one that cannot be chosen runs nothing.
    func testThePagesActionsFollowTheirOrderAndPriority() throws {
        try onUIThread {
            let heard = Received<String>()
            let host = GTKRenderer.running {
                NavigationStack(State(wrappedValue: [Int]()).projectedValue) {
                    TitledPage(title: "Notes", actions: [
                        ToolbarItem("Delete").placement(.overflow).onClicked { heard.values.append("delete") },
                        ToolbarItem("Save").priority(1).onClicked { heard.values.append("save") },
                        ToolbarItem("Add").priority(0).disabled(!false).onClicked { heard.values.append("add") },
                    ])
                } destination: { _ in
                    TitledPage(title: "Note")
                }
            }
            let frame = try XCTUnwrap(host.views(GTKNavigationView.self).first?.frames.last)
            XCTAssertEqual(frame.buttons.map(\.text), ["Add", "Save"])
            XCTAssertEqual(frame.overflowButtons.map(\.text), ["Delete"])
            XCTAssertEqual(gtk_widget_get_sensitive(frame.buttons[0].widget), 0, "Add cannot be chosen")

            for button in frame.buttons + frame.overflowButtons where gtk_widget_get_sensitive(button.widget) != 0 {
                button.click()
            }
            host.runtime.pump.turn()
            XCTAssertEqual(heard.values, ["save", "delete"])
        }
    }

    /// A destructive action is libadwaita's destructive button on the header bar; in the overflow's flat menu its
    /// words take the theme's destructive colour, not the white that button writes on its red fill.
    func testADestructiveActionWearsTheThemesDestructiveColour() throws {
        try onUIThread {
            let host = GTKRenderer.running {
                TitledPage(title: "Notes", actions: [
                    ToolbarItem("Remove").isDestructive(true),
                    ToolbarItem("Clear").isDestructive(true).placement(.overflow),
                    ToolbarItem("Later").placement(.overflow),
                ])
            }
            let frame = try XCTUnwrap(host.window?.pageFrame)
            let remove = try XCTUnwrap(frame.buttons.first)
            XCTAssertNotEqual(gtk_widget_has_css_class(remove.widget, "destructive-action"), 0)

            let colors = frame.overflowButtons.map { button in
                var color = GdkRGBA()
                gtk_widget_get_color(button.widget, &color)
                return color
            }
            XCTAssertEqual(colors.count, 2)
            XCTAssertGreaterThan(colors[0].red - max(colors[0].green, colors[0].blue), 0.3, "Clear's words are red")
            XCTAssertLessThan(abs(colors[1].red - colors[1].green), 0.1, "Later's words are the menu's own")
        }
    }

    /// An action with a picture stands on the header bar as an icon named by its title; one whose picture the
    /// application does not hold shows its title, and the overflow's menu shows titles.
    func testAnActionWithAPictureStandsAsAnIcon() throws {
        try onUIThread {
            let host = GTKRenderer.running {
                TitledPage(title: "Notes", actions: [
                    ToolbarItem("Wide").icon("test_wide.png"),
                    ToolbarItem("Lost").icon("missing.png"),
                    ToolbarItem("Later").icon("test_wide.png").placement(.overflow),
                ])
            }
            let frame = try XCTUnwrap(host.window?.pageFrame)
            let wide = try XCTUnwrap(frame.buttons.first)
            let image = try XCTUnwrap(gtk_button_get_child(wide.widget.of(GtkButton.self)))

            XCTAssertEqual(g_type_name(UnsafeMutablePointer<GTypeInstance>(image.opaque).pointee.g_class.pointee.g_type)
                .map { String(cString: $0) }, "GtkImage")
            XCTAssertNotEqual(gtk_widget_has_css_class(wide.widget, "image-button"), 0)
            XCTAssertEqual(gtk_widget_get_tooltip_text(wide.widget).map { String(cString: $0) }, "Wide")
            XCTAssertEqual(frame.buttons.map(\.text), ["", "Lost"])
            XCTAssertEqual(frame.overflowButtons.map(\.text), ["Later"])
        }
    }

    /// A stack's bar colours paint the header bar of every page on it, and what stands on the bar.
    func testAStacksBarColoursPaintItsPagesHeaderBars() throws {
        try onUIThread {
            let host = GTKRenderer.running {
                NavigationStack(State(wrappedValue: [Int]()).projectedValue) {
                    TitledPage(title: "Painted")
                } destination: { _ in
                    TitledPage(title: "Next")
                }
                .barBackgroundColor(Color("#FF0000"))
                .barForegroundColor(Color("#FFFFFF"))
            }
            let frame = try XCTUnwrap(host.views(GTKNavigationView.self).first?.frames.last)
            host.layOut()

            XCTAssertNotEqual(gtk_widget_has_css_class(frame.header, "swiftomniui-bar-bFF0000FF-fFFFFFFFF"), 0)
            XCTAssertEqual(GTKTestHost.pixels(of: frame.header, at: [(4, 4)]), [0xFFFF_0000])
        }
    }

    /// A header bar no arrangement colours takes the colours of the window's title bar.
    func testABarNoArrangementColoursTakesTheTitleBars() throws {
        try onUIThread {
            let host = GTKRenderer.running { TitleBarPage() }
            let frame = try XCTUnwrap(host.window?.pageFrame)
            host.settle { gtk_widget_has_css_class(frame.header, "swiftomniui-bar-b00FF00FF-fFFFFFFFF") != 0 }

            XCTAssertNotEqual(gtk_widget_has_css_class(frame.header, "swiftomniui-bar-b00FF00FF-fFFFFFFFF"), 0)
        }
    }

    /// A page's title view stands at the middle of its header bar; a page pushed over it has its own title.
    func testAPagesTitleViewStandsInItsHeaderBar() throws {
        try onUIThread {
            let path = State(wrappedValue: [Int]())
            let host = GTKRenderer.running {
                NavigationStack(path.projectedValue) {
                    SearchingPage()
                } destination: { _ in
                    TitledPage(title: "Result")
                }
            }
            let navigation = try XCTUnwrap(host.views(GTKNavigationView.self).first)
            let field = try XCTUnwrap(host.views(GTKTextFieldView.self).first)
            let root = try XCTUnwrap(navigation.frames.first)
            XCTAssertTrue(root.chrome.titleView === field)
            XCTAssertTrue(adw_header_bar_get_title_widget(root.header.opaque) == field.widget)

            path.wrappedValue = [1]
            host.runtime.pump.turn()
            XCTAssertNil(navigation.frames.last?.chrome.titleView)
            XCTAssertEqual(navigation.frames.last?.chrome.title, "Result")
            XCTAssertTrue(adw_header_bar_get_title_widget(root.header.opaque) == field.widget, "still the root's")
        }
    }

    /// A page that hides its navigation bar shows no header bar.
    func testAPageWithoutANavigationBarShowsNoHeaderBar() throws {
        try onUIThread {
            let host = GTKRenderer.running {
                NavigationStack(State(wrappedValue: [1]).projectedValue) {
                    TitledPage(title: "Root")
                } destination: { _ in
                    TitledPage(title: "Bare", actions: [ToolbarItem("Save")], hidesBar: true)
                }
            }
            let frame = try XCTUnwrap(host.views(GTKNavigationView.self).first?.frames.last)
            XCTAssertFalse(frame.chrome.showsBar)
            XCTAssertEqual(adw_toolbar_view_get_reveal_top_bars(frame.widget.opaque), 0)
        }
    }

    /// A sheet is libadwaita's dialog over the window, its page in a frame of its own; the user closing it - Escape,
    /// its close button - takes it off the modal stack, and the program's close tells nothing.
    func testASheetTheUserClosesLeavesTheModalStack() throws {
        try onUIThread {
            let sheets = State(wrappedValue: [1, 2])
            let host = GTKRenderer.running { StackHost(sheets: sheets.projectedValue) }
            host.settle { host.sheets.count == 2 }
            XCTAssertEqual(host.sheets.map { $0.sheet.frame?.chrome.title }, ["Sheet 1", "Sheet 2"])
            XCTAssertNotEqual(gtk_widget_get_mapped(host.sheets[1].sheet.page.widget), 0, "the top sheet shows")

            adw_dialog_close(host.sheets[1].sheet.dialog)
            host.settle { sheets.wrappedValue == [1] }
            XCTAssertEqual(sheets.wrappedValue, [1], "the user's close")

            sheets.wrappedValue = []
            host.settle { host.sheets.isEmpty }
            XCTAssertEqual(sheets.wrappedValue, [], "the program's close heard by nobody")
        }
    }
}

/// A page with a title, maybe a log of its phases, the actions it puts on its header bar, and whether it hides its
/// navigation bar.
struct TitledPage: View {
    let title: String
    var log: Received<String>? = nil
    var actions: [ToolbarItem] = []
    var hidesBar = false

    @Environment private var page: PageSession

    var body: some View {
        let log = self.log
        let title = self.title
        let page = self.page

        return Text(title)
            .onAppear {
                page.title = title
                page.toolbarItems = actions
                if hidesBar { page.hasNavigationBar = false }
            }
            .onChange(of: page.phase) { log?.values.append("\(title) \(page.phase)") }
    }
}

/// A page under a modal stack the test drives.
private struct StackHost: View {
    @Environment private var window: WindowSession
    let sheets: Binding<[Int]>

    var body: some View {
        let window = self.window
        let sheets = self.sheets
        return Text("Beneath").onAppear {
            window.modalStack = ModalStack(sheets) { number in
                TitledPage(title: "Sheet \(number)")
            }
        }
    }
}

/// A page that gives its window a green title bar with white on it.
private struct TitleBarPage: View {
    @Environment private var window: WindowSession

    var body: some View {
        let window = self.window
        return Text("under a title bar").onAppear {
            window.titleBar = TitleBar("Titled").background(Color("#00FF00")).barForegroundColor(Color("#FFFFFF"))
        }
    }
}

/// A page whose title view is a search field.
private struct SearchingPage: View {
    @Environment private var page: PageSession
    @State private var query = ""

    var body: some View {
        let page = self.page
        let query = $query
        return Text("Results").onAppear {
            page.title = "Search"
            page.titleView = TextField(query).placeholder("Search")
        }
    }
}
