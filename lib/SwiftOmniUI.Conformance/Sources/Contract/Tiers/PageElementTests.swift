// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// `PageElementContract` on a host: a page and an arrangement stand under the title and with the icon the tree gives
/// them where another container presents them - a tabbed view's tab - and under the titles the tree changes them to;
/// the visible page's title names its window. Each case made for every element wearing the tier.
@_spi(Host) public enum PageElementTests: ConformanceFamily {
    public static let name = "PageElement"

    public static var cases: [ConformanceCase] {
        Specimens.wearing(PageElementContract.self).flatMap { element in
            [
                inTab(PageElementContract.title, of: element, "Notes", then: "Drafts"),
                inTab(PageElementContract.icon, of: element, "test_dot.png", then: "test_wide.png"),
                inTab(PageElementContract.titleKey, of: element, "notes", then: "drafts"),
                inTab(PageElementContract.subtitle, of: element, "One", then: "Two"),
                inTab(PageElementContract.subtitleKey, of: element, "one", then: "two"),
                inTab(PageElementContract.document, of: element, "A.txt", then: "B.txt"),
                inTab(PageElementContract.badge, of: element, "1", then: "2"),
                inTab(PageElementContract.presentationDetents, of: element, [.medium], then: [.large]),
                inTab(PageElementContract.presentationDragIndicator, of: element, .hidden, then: .visible),
                inTab(PageElementContract.interactiveDismissDisabled, of: element, false, then: true),
                inTab(PageElementContract.preferredColumnWidth, of: element, [200], then: [300]),
                inTab(PageElementContract.toolbarVisibility, of: element, .hidden, then: .visible),
                inTab(PageElementContract.toolbarBackground, of: element, .hidden, then: .visible),
                inTab(PageElementContract.windowBackground, of: element, .red, then: .blue),
            ]
        } + [titled]
    }

    /// `member` of `element`, presented as a tabbed view's first tab, holds what the tree gives it and what the tree
    /// changes it to.
    static func inTab<Value: HostRepresentable & Sendable & Equatable>(
        _ member: ElementProperty<PageElementContract, Value>, of element: String, _ first: Value, then second: Value
    ) -> ConformanceCase {
        ConformanceCase("\(element).\(member.name).standsOnItsTab", proves: [
            Covered(member, on: element),
        ], needs: [Covered(ButtonContract.clicked)]) { s in
            let value = State(wrappedValue: first)
            s.start {
                TabView([0, 1]) { tab -> any Page in
                    guard tab == 0 else { return Text("Other") }
                    return Presented.page(element, member, value.wrappedValue, beside: [
                        Button("Change").onClicked { value.wrappedValue = second }.id("change"),
                    ])
                }
            }
            let kind = s.elements(ofType: NodeType(element))
            let presented = element == "TabView" ? kind.last : kind.first
            guard let specimen = element == "Page" ? try tabPage(s) : presented else {
                return s.fail("no \(element) presented")
            }
            try s.settle { try s.held(member, on: specimen) == first }
            s.expect(try s.held(member, on: specimen), first, "the value the tree gave")

            try s.perform(.activate, on: s.element("change"))
            try s.settle { try s.held(member, on: specimen) == second }
            s.expect(try s.held(member, on: specimen), second, "the value the tree changed it to")
        }
    }

    /// The page of the tabbed view's first tab.
    @MainActor static func tabPage(_ s: Session) throws -> MountedElement {
        guard let tabs = s.elements(ofType: TabViewContract.nodeType).first,
              let page = tabs.children.first(where: { $0.type == PageContract.nodeType })
        else { throw DriverCannot("find the tab's page") }
        return page
    }

    /// The visible page's title names its window.
    static var titled: ConformanceCase {
        ConformanceCase("Page.theVisiblePagesTitleNamesItsWindow", proves: [
            Covered(PageElementContract.title, on: "Page"),
        ]) { s in
            s.start { SessionPage { page, _ in page.title = "Notes" } }

            try s.settle { try s.held(WindowSceneContract.title, on: s.element(ofType: WindowSceneContract.nodeType)) == "Notes" }
            s.expect(try s.held(WindowSceneContract.title, on: s.element(ofType: WindowSceneContract.nodeType)), "Notes")
        }
    }
}

/// A page of each kind wearing the tier - a page of its own, or an arrangement - carrying one of the tier's members.
@MainActor enum Presented {
    /// A page of `element`'s kind whose `member` is `value`, `beside` its words.
    static func page<Value: HostRepresentable & Sendable & Equatable>(
        _ element: String, _ member: ElementProperty<PageElementContract, Value>, _ value: Value, beside: [any View]
    ) -> any Page {
        let others: [Element] = beside.map { $0 }
        let written = Write(member, value)
        switch element {
        case "NavigationStack":
            return written.worn(by: NavigationStack(State(wrappedValue: [Int]()).projectedValue) {
                VStack { [Text("Root")] + others }
            } destination: { _ in Text("Pushed") })
        case "NavigationSplitView":
            return written.worn(by: NavigationSplitView(State(wrappedValue: true).projectedValue) {
                Text("Sidebar")
            } detail: { VStack { [Text("Detail")] + others } })
        case "TabView":
            return written.worn(by: TabView([0]) { _ in VStack { [Text("Inner")] + others } })
        default:
            return SessionPage(beside: others, key: "\(value)") { page, _ in
                if let title = value as? String, member.name == PageElementContract.title.name { page.title = title }
                if let icon = value as? ImageSource, member.name == PageElementContract.icon.name { page.icon = icon }
            }
        }
    }
}
