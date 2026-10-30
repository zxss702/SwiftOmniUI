// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

/// A menu of rows like the Gallery's sidebar: a stack with a picture, words and a tap on it, the chosen one
/// marked by the colour and weight the application writes on top of its style.
private struct MenuRowsPage: View {
    let titles: [String]
    @State private var chosen = -1

    var body: some View {
        VStack {
            ForEach(titles.indices, id: \.self) { index in
                HStack {
                    Image("test_dot.png")
                        .frame(width: 20)
                        .frame(height: 20)
                        .verticalAlignment(.center)
                    Text(titles[index])
                        .foregroundStyle(index == chosen ? Color("#FF6A00") : Color("#5A5A5A"))
                        .fontWeight(index == chosen ? .bold : .regular)
                }
                .spacing(14)
                .contentPadding(EdgeInsets(18, 13))
                .background(index == chosen ? Color("#E5DFF5") : .transparent)
                .onTapGesture { chosen = index }
            }
        }
        .horizontalAlignment(.start)
        .verticalAlignment(.start)
    }
}

/// The same rows in the split view's pane, in a scroller, carrying what the Gallery's carry: an accessibility
/// name and a picture asked to hide when it has none.
private struct SplitMenuPage: View {
    let titles: [String]
    @State private var chosen = -1
    @State private var open = true

    var body: some View {
        NavigationSplitView($open) {
            ScrollView {
                VStack {
                    ForEach(titles.indices, id: \.self) { index in
                        HStack {
                            Image("test_dot.png")
                                .frame(width: 20)
                                .frame(height: 20)
                                .hidden(false)
                                .verticalAlignment(.center)
                            Text(titles[index])
                                .foregroundStyle(index == chosen ? Color("#FF6A00") : Color("#5A5A5A"))
                                .fontWeight(index == chosen ? .bold : .regular)
                        }
                        .spacing(14)
                        .contentPadding(EdgeInsets(18, 13))
                        .background(index == chosen ? Color("#E5DFF5") : .transparent)
                        .accessibilityIdentifier("menu.\(index)")
                        .accessibilityLabel(titles[index])
                        .onTapGesture { chosen = index }
                    }
                }
            }
        } detail: {
            Text("detail")
        }
    }
}

final class WinUIMenuRowTests: XCTestCase {
    /// A row tapped in a split view's pane keeps its words, and so does every row beside it.
    func testATappedRowInASplitPaneKeepsItsWordsAndEveryRows() throws {
        try onUIThread {
            let host = WinUIRenderer.running(
                room: WinUITestHost.wideRoom
            ) { SplitMenuPage(titles: ["Home", "One", "Two", "Three", "Four"]) }
            let labels = { host.views(WinUILabelView.self).filter { $0.text != "detail" } }
            XCTAssertEqual(labels().map(\.text).sorted(), ["Four", "Home", "One", "Three", "Two"].sorted())

            let rows = host.views(WinUIStackView.self)
            XCTAssertTrue(try XCTUnwrap(rows.dropFirst(2).first).press())
            for _ in 0..<10 { host.step() }
            host.layOut()

            XCTAssertEqual(labels().map(\.text).sorted(), ["Four", "Home", "One", "Three", "Two"].sorted(),
                           "a row's words are gone")
            for label in labels() {
                XCTAssertTrue(label.isShown)
                XCTAssertGreaterThan(label.frame.width, 0)
                XCTAssertNotEqual(label.wordsStyle.color >> 24, 0)
            }
        }
    }

    /// A row tapped in a menu keeps its words, and so does every row beside it - a tap redraws the marks, never
    /// the words away.
    func testATappedMenuRowKeepsItsWordsAndEveryRows() throws {
        try onUIThread {
            let host = WinUIRenderer.running { MenuRowsPage(titles: ["Home", "One", "Two", "Three", "Four"]) }
            let labels = { host.views(WinUILabelView.self) }
            XCTAssertEqual(labels().map(\.text), ["Home", "One", "Two", "Three", "Four"])

            let rows = host.views(WinUIStackView.self)
            XCTAssertTrue(try XCTUnwrap(rows.dropFirst(2).first).press())
            for _ in 0..<10 { host.step() }
            host.layOut()

            for (index, label) in labels().enumerated() {
                XCTAssertFalse(label.text.isEmpty, "row \(index) lost its words")
                XCTAssertTrue(label.isShown, "row \(index) collapsed")
                XCTAssertGreaterThan(label.frame.width, 0, "row \(index) measured at nothing")
                XCTAssertNotEqual(label.wordsStyle.color >> 24, 0, "row \(index) coloured clear")
            }
        }
    }
}
