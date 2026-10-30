// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIAndroid
import XCTest

/// A `LazyVStack` on Android answers the same window questions as everywhere:
/// the rows the scroller's reach holds are mounted, and no more.
final class AndroidLazyTests: XCTestCase {
    static var allTests: [(String, (AndroidLazyTests) -> () throws -> Void)] {
        [
            ("testOnlyTheWindowedRowsAreBuilt", testOnlyTheWindowedRowsAreBuilt),
            ("testScrollingBuildsAheadAndLetsGoBehind", testScrollingBuildsAheadAndLetsGoBehind),
            ("testTheScrollRoomIsTheWholeRunAtOnce", testTheScrollRoomIsTheWholeRunAtOnce),
            ("testALazyStackWithNoScrollerBuildsAll", testALazyStackWithNoScrollerBuildsAll),
        ]
    }

    /// Of a thousand rows a window's worth are built, and no more.
    func testOnlyTheWindowedRowsAreBuilt() throws {
        try onMainActor {
            let host = AndroidRenderer.running { LazyRowsPage() }
            host.layOut()
            host.settle { host.views(AndroidLabelView.self).count > 4 }

            XCTAssertLessThan(host.views(AndroidLabelView.self).count, 60, "a window's reach of a thousand rows")
        }
    }

    /// Scrolling asks the rows the window moved to be built, and lets the
    /// ones it left go.
    func testScrollingBuildsAheadAndLetsGoBehind() throws {
        try onMainActor {
            let host = AndroidRenderer.running { LazyRowsPage() }
            let scroll = try XCTUnwrap(host.views(AndroidScrollView.self).first)
            host.layOut()
            host.settle { host.views(AndroidLabelView.self).contains { $0.text == "Row 0" } }

            Java.call(scroll.scrollers[0].reference, JavaAPI.scrollTo, .int(0), .int(40_000))
            host.layOut()
            host.settle { host.views(AndroidLabelView.self).contains { $0.text == "Row 500" } }

            let standing = host.views(AndroidLabelView.self).map(\.text)
            XCTAssertFalse(standing.contains("Row 0"), "the first row was let go")
            XCTAssertLessThan(standing.count, 150, "still a window's reach")
        }
    }

    /// The room is the run's whole length before most of its rows exist.
    func testTheScrollRoomIsTheWholeRunAtOnce() throws {
        try onMainActor {
            let host = AndroidRenderer.running { LazyRowsPage() }
            host.layOut()
            host.settle { host.views(AndroidLabelView.self).count > 4 }

            // A thousand forty-point rows at two pixels a point: the lazy view's height is their run.
            let lazy = try XCTUnwrap(host.views(AndroidLazyStackView.self).first)
            XCTAssertEqual(Double(lazy.frame.height), 80_000, accuracy: 8_000)
        }
    }

    /// Outside a scroller there is no window to narrow by: every child is
    /// built, as a plain stack's would be. The run hears so on the frame after
    /// a layout, said by hand here where no window lays the root out.
    func testALazyStackWithNoScrollerBuildsAll() throws {
        try onMainActor {
            let host = AndroidRenderer.running { LazyRowsPage(count: 30, scrolls: false) }
            host.layOut()
            host.runtime.frames.laidOut()
            host.frame()
            host.settle { host.views(AndroidLabelView.self).count == 30 }

            XCTAssertEqual(host.views(AndroidLabelView.self).count, 30)
        }
    }
}

/// A thousand forty-point rows in a scroller - or thirty, where it does not
/// scroll.
private struct LazyRowsPage: View {
    var count = 1_000
    var scrolls = true

    var body: some View {
        if scrolls {
            ScrollView {
                LazyVStack {
                    ForEach(0..<count) { row in
                        Text("Row \(row)").frame(height: 40)
                    }
                }
            }
        } else {
            LazyVStack {
                ForEach(0..<count) { row in
                    Text("Row \(row)").frame(height: 40)
                }
            }
        }
    }
}
