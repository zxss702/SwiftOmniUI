// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

@MainActor private final class GeometryCommitProbe: WinUIView {
    var commits: [Rect] = []
    init() { super.init { swiftomniui_winui_panel_make($0) } }
    override func commitGeometry(in bounds: Rect) { commits.append(bounds) }
}

@MainActor private final class NativeMeasurementProbe: WinUILayoutView {
    var reportedHeight = 40.0
    override func contentSize(width: Double?) -> LayoutSize {
        LayoutSize(width: width ?? 240, height: reportedHeight)
    }
}

final class WinUIGeometryCommitTests: XCTestCase {
    func testAnimationSamplesDoNotDrawAtAnUncommittedNativeSize() {
        onUIThread {
            let view = GeometryCommitProbe()
            let first = Rect(0, 0, 240, 40), next = Rect(0, 0, 240, 128)
            view.prepareMeasure(width: first.width, height: first.height)
            view.withNativeArrange { view.layout(first) }
            XCTAssertEqual(view.commits, [first])
            XCTAssertEqual(view.committedFrame, first)

            view.placedFrame = next
            XCTAssertEqual(view.placedFrame, next, "the animator retains its current sample")
            XCTAssertEqual(view.committedFrame, first)
            XCTAssertEqual(view.commits, [first], "sampling is not a drawing commit")
            var brushSizes: [LayoutSize] = []
            view.paint("probe", followsSize: true) { brushSizes.append($0) }
            XCTAssertEqual(brushSizes, [LayoutSize(width: 240, height: 40)])

            view.prepareMeasure(width: next.width, height: next.height)
            view.withNativeArrange { view.layout(next) }
            XCTAssertEqual(view.committedFrame, next)
            XCTAssertEqual(view.commits, [first, next])
            XCTAssertEqual(brushSizes.last, LayoutSize(width: 240, height: 128))
            view.withNativeArrange { view.layout(next) }
            XCTAssertEqual(brushSizes.count, 2, "an unchanged allocation does not repaint size-dependent brushes")
        }
    }

    func testAllocationMeasurementsDoNotPublishAnotherContentInvalidation() {
        onUIThread {
            let parent = WinUIStackView(axis: .vertical)
            let child = NativeMeasurementProbe()
            parent.setItems([WinUILayoutItem(view: child)])
            WinUIDoorbell.commitPending()
            _ = child.measure(width: 240, height: 128)
            let revisions = [parent.measurementRevision, child.measurementRevision]
            for height in [40.0, 54, 84, 112, 128, 84, 40] {
                child.reportedHeight = height
                _ = child.measure(width: 240, height: 128)
                WinUIDoorbell.commitPending()
                XCTAssertEqual([parent.measurementRevision, child.measurementRevision], revisions)
            }
        }
    }
}
