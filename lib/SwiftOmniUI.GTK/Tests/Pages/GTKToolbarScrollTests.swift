// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIGTK
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIGTK
import XCTest

final class GTKToolbarScrollTests: XCTestCase {
    func testAPlainScrollerStartsBelowTheNativeHeaderAndStillScrolls() throws {
        try onUIThread {
            let host = GTKRenderer.running {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(0..<100, id: \.self) { number in Text("Row \(number)").frame(height: 30) }
                    }
                }.navigationTitle("Document")
            }
            let frame = try XCTUnwrap(host.window?.pageFrame)
            let scroll = try XCTUnwrap(host.views(GTKScrollView.self).first)
            var header = graphene_rect_t()
            XCTAssertNotEqual(gtk_widget_compute_bounds(frame.header, frame.widget, &header), 0)
            var viewport = graphene_rect_t()
            XCTAssertNotEqual(gtk_widget_compute_bounds(scroll.scroller.widget, frame.widget, &viewport), 0)
            XCTAssertGreaterThanOrEqual(Double(viewport.origin.y), Double(header.origin.y + header.size.height) - 1)
            XCTAssertEqual(scroll.safeAreaContext?.bounds.y, 0, "native row exclusion must not expand the viewport a second time")
            let adjustment = try XCTUnwrap(gtk_scrolled_window_get_vadjustment(scroll.scroller.widget.opaque))
            XCTAssertGreaterThan(gtk_adjustment_get_upper(adjustment), gtk_adjustment_get_page_size(adjustment))
            gtk_adjustment_set_value(adjustment, 120)
            host.step()
            XCTAssertGreaterThan(gtk_adjustment_get_value(adjustment), 0)
            XCTAssertEqual(adw_toolbar_view_get_top_bar_style(frame.widget.opaque), ADW_TOOLBAR_RAISED)
        }
    }

    func testASafeBarKeepsTheFirstRowBelowTheCompleteToolbarRegion() throws {
        try onUIThread {
            let host = GTKRenderer.running {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(0..<500, id: \.self) { number in Text("Row \(number)").frame(height: 30) }
                    }
                }.safeAreaInset(edge: .top, spacing: 0) {
                    HStack { Text("Breadcrumb") }.frame(maxWidth: .infinity).frame(height: 32).id("bar")
                }
            }
            let bar = try XCTUnwrap(host.runtime.tree.root?.first(id: .manual("bar"))?.gtk.view)
            let first = try XCTUnwrap(host.views(GTKLabelView.self).first { $0.text == "Row 0" })
            let barRect = try XCTUnwrap(bar.windowRect()), rowRect = try XCTUnwrap(first.windowRect())
            XCTAssertGreaterThanOrEqual(rowRect.y, barRect.y + barRect.height - 1)
            let lazy = try XCTUnwrap(host.views(GTKLazyView.self).first)
            XCTAssertLessThan(lazy.cells.built.count, 100)
            let requests = lazy.cells.requests
            for _ in 0..<8 { host.layOut(); host.step() }
            XCTAssertEqual(lazy.cells.requests, requests, "idle layout must not continually request the same lazy window")
        }
    }
}
