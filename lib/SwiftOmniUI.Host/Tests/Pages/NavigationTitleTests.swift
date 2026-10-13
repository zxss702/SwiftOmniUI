// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) @testable import SwiftOmniUICore
@_spi(Host) @testable import SwiftOmniUIHost
import XCTest

@MainActor final class NavigationTitleTests: XCTestCase {
    func testSplitTitlesFlowThroughAFramedWrapperAndNestedStack() throws {
        let runtime = HostRuntime.still()
        runtime.tree.apply(window(), complete: true)
        let root = try XCTUnwrap(runtime.tree.root)
        let wrapper = try XCTUnwrap(root.first(id: .manual("wrapper")))
        let page = try XCTUnwrap(root.first(id: .manual("main")))
        let chrome = WindowChrome(window: root, arrangement: wrapper)
        XCTAssertEqual(chrome.title, "Project")
        XCTAssertEqual(chrome.subtitle, "Conversation")
        XCTAssertEqual(chrome.document, "/tmp/project")
        XCTAssertEqual(page.navigationValue(.title)?.string, "Project")
        XCTAssertEqual(page.navigationValue(.subtitle)?.string, "Conversation")
        XCTAssertNil(root.first(id: .manual("sidebar"))?.navigationValue(.subtitle))
        XCTAssertNil(root.first(id: .manual("auxiliary"))?.navigationValue(.subtitle))
        XCTAssertNil(root.first(id: .manual("sheet"))?.navigationValue(.title))
    }

    func testPushedPageOverridesThenClearsAndFallsBackToTheSplitTitle() throws {
        let runtime = HostRuntime.still()
        runtime.tree.apply(window(), complete: true)
        let root = try XCTUnwrap(runtime.tree.root)
        let wrapper = try XCTUnwrap(root.first(id: .manual("wrapper")))
        let stack = try XCTUnwrap(root.first(id: .manual("stack")))
        let main = try XCTUnwrap(root.first(id: .manual("main")))
        func chrome() -> WindowChrome { WindowChrome(window: root, arrangement: wrapper) }

        runtime.tree.apply(window(pushed: [.title: .string("File.swift"), .subtitle: .string("Editing")]), complete: true)
        XCTAssertEqual(chrome().title, "File.swift")
        XCTAssertEqual(chrome().subtitle, "Editing")
        runtime.tree.apply(window(pushed: [.title: .string(""), .subtitle: .string("")]), complete: true)
        XCTAssertEqual(chrome().title, "", "an explicitly empty title is not an absent title")
        XCTAssertEqual(chrome().subtitle, "")
        runtime.tree.apply(window(pushed: [:]), complete: true)
        XCTAssertEqual(chrome().title, "Project", "removing the modifier restores the enclosing title")
        XCTAssertEqual(chrome().subtitle, "Conversation")
        runtime.tree.apply(window(title: "Other project", subtitle: "New conversation"), complete: true)
        XCTAssertEqual(chrome().title, "Other project")
        XCTAssertEqual(chrome().subtitle, "New conversation")
        XCTAssertTrue(root.first(id: .manual("stack")) === stack)
        XCTAssertTrue(root.first(id: .manual("main")) === main)
    }

    func testInheritedTitleAndSubtitleResolveTheirLocalizationKeys() throws {
        let runtime = HostRuntime.still()
        runtime.tree.localization = { key in
            if key == LocalizedStringKey("Project") { return "项目" }
            if key == LocalizedStringKey("Conversation") { return "对话" }
            return nil
        }
        var patch = window()
        // Keep the fallback words and localized keys on the arrangement that declared them.
        patch.children = .arranged([node("split", .navigationSplitView, [
            .title: .string("Project"), .titleKey: LocalizedStringKey("Project").propValue,
            .subtitle: .string("Conversation"), .subtitleKey: LocalizedStringKey("Conversation").propValue,
        ], children: [node("sidebar", .page), node("main", .page)])])
        runtime.tree.apply(patch, complete: true)
        let root = try XCTUnwrap(runtime.tree.root)
        let chrome = WindowChrome(window: root, arrangement: root.first(id: .manual("split")))
        XCTAssertEqual(chrome.title, "项目")
        XCTAssertEqual(chrome.subtitle, "对话")
    }

    func testTitlesWrittenOnTheLayerAroundASplitReachOnlyItsMainColumn() throws {
        let runtime = HostRuntime.still()
        let split = node("split", .navigationSplitView, children: [
            node("sidebar", .page),
            node("stack", .navigationStack, children: [node("main", .page)]),
            node("auxiliary", .page),
        ])
        runtime.tree.apply(node("window", .windowScene, children: [
            node("wrapper", .page, children: [node("layer", .zStack, [
                .title: .string("Project"), .subtitle: .string("Conversation"),
            ], children: [split, node("decoration", .text)])]),
        ]), complete: true)
        let root = try XCTUnwrap(runtime.tree.root)
        let chrome = WindowChrome(window: root, arrangement: root.first(id: .manual("wrapper")))
        XCTAssertEqual(chrome.title, "Project")
        XCTAssertEqual(chrome.subtitle, "Conversation")
        XCTAssertEqual(root.first(id: .manual("main"))?.navigationValue(.subtitle)?.string, "Conversation")
        XCTAssertNil(root.first(id: .manual("sidebar"))?.navigationValue(.subtitle))
        XCTAssertNil(root.first(id: .manual("auxiliary"))?.navigationValue(.subtitle))
    }

    func testBoundNavigationMetadataAsksForChromeRefreshOnOrdinaryContent() {
        XCTAssertTrue(WindowChrome.follows(.text, changing: [.title]))
        XCTAssertTrue(WindowChrome.follows(.vStack, changing: [.subtitle]))
        XCTAssertTrue(WindowChrome.follows(.text, changing: [.titleKey]))
        XCTAssertFalse(WindowChrome.follows(.text, changing: [.text]))
        XCTAssertFalse(WindowChrome.follows(.lazyVStack, changing: [.items]))
    }

    private func window(title: String = "Project", subtitle: String = "Conversation", pushed: [Prop: HostValue]? = nil) -> HostPatch {
        var pages = [node("main", .page, children: [node("body", .text)])]
        if let pushed { pages.append(node("pushed", .page, pushed)) }
        return node("window", .windowScene, [.title: .string("Window")], children: [
            node("wrapper", .page, children: [node("frame", .vStack, children: [
                node("split", .navigationSplitView, [
                    .title: .string(title), .subtitle: .string(subtitle), .document: .string("/tmp/project"),
                ], children: [node("sidebar", .page),
                              node("stack", .navigationStack, children: pages), node("auxiliary", .page)]),
            ])]),
            node("sheets", .modalStack, children: [node("sheet", .page)]),
        ])
    }

    private func node(_ id: String, _ type: NodeType, _ properties: [Prop: HostValue] = [:], children: [HostPatch] = []) -> HostPatch {
        var patch = HostPatch(id: .manual(id), type: type)
        patch.properties = properties
        patch.children = .arranged(children)
        return patch
    }
}
