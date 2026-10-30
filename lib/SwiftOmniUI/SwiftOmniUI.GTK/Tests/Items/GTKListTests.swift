// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIGTK
import CSwiftOmniUIGTK
import XCTest

final class GTKListTests: XCTestCase {
    /// A row stands as tall as its entry, so only the rows its view holds are shown: at their least, a SwiftOmniUI
    /// panel's nothing, every row GTK binds would stand in view at once.
    func testARowStandsAsTallAsItsEntry() throws {
        try onUIThread {
            let host = GTKRenderer.running {
                VStack { List(0..<100) { Text("Item \($0)").contentPadding(12) }.frame(width: 300).frame(height: 300) }
            }
            let list = try XCTUnwrap(host.views(GTKItemsView.self).first)
            host.settle { list.shownRows.count == 7 }
            let rows = list.shownRows

            XCTAssertEqual(rows.count, 7, "as many as 300 holds")
            XCTAssertEqual(Set(rows).count, 1, "each as tall as its entry")
        }
    }
}

extension GTKListTests {
    /// A row is named by what its entry says (`MountedElement.spokenWords`): the screen reader reads a row by its
    /// name alone.
    func testARowIsNamedByWhatItsEntrySays() throws {
        try onUIThread {
            let host = GTKRenderer.running {
                VStack { List(0..<3) { Text("Item \($0)").contentPadding(12) }.frame(width: 300).frame(height: 300) }
            }
            let list = try XCTUnwrap(host.views(GTKItemsView.self).first)
            let names = {
                list.made.compactMap { row, cell in
                    cell.identity.map { _ in gtk_list_item_get_accessible_label(row).map { String(cString: $0) } ?? "" }
                }.sorted()
            }
            host.settle { names() == ["Item 0", "Item 1", "Item 2"] }

            XCTAssertEqual(names(), ["Item 0", "Item 1", "Item 2"])
        }
    }
}

private extension GTKItemsView {
    /// The heights of the rows GTK shows, in order.
    var shownRows: [Int32] {
        var scrolled = gtk_widget_get_first_child(widget)
        while let each = scrolled, g_type_check_instance_is_a(each.of(GTypeInstance.self), gtk_scrolled_window_get_type()) == 0 {
            scrolled = gtk_widget_get_first_child(each)
        }
        guard let scrolled, let list = gtk_scrolled_window_get_child(scrolled.opaque) else { return [] }
        var rows: [Int32] = []
        var row = gtk_widget_get_first_child(list)
        while let each = row {
            if gtk_widget_get_mapped(each) != 0 { rows.append(gtk_widget_get_height(each)) }
            row = gtk_widget_get_next_sibling(each)
        }
        return rows
    }
}
