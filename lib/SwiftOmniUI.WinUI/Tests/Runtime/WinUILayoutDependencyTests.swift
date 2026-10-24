// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

@MainActor
private final class DependencySizedPanel: WinUISingleChildView {
    var queries: [Double?: Int] = [:]

    override func contentSize(width: Double?) -> LayoutSize {
        queries[width, default: 0] += 1
        return super.contentSize(width: width)
    }
}

final class WinUILayoutDependencyTests: XCTestCase {
    func testFirstConsumedContextKeepsIntrinsicQueriesButRealInsetsInvalidate() {
        onUIThread {
            let words = WinUILabelView()
            words.setText("A file name with several words that wrap inside its row")
            words.setLines(breaking: .wordWrap, maximum: nil)
            let child = DependencySizedPanel()
            child.setItems([WinUILayoutItem(view: words)])
            let original = child.naturalSize(width: 120)
            let queries = child.queries
            let revision = child.layoutContextRevision
            let room = Rect(0, 0, 120, 100)
            let consumed = EdgeInsets(top: 48, leading: 0, bottom: 0, trailing: 0)
            child.setLayoutContext(SafeAreaContext(bounds: room, consumed: consumed))
            XCTAssertEqual(child.naturalSize(width: 120), original)
            XCTAssertEqual(child.queries, queries,
                           "the ancestor's consumed title bar cannot make a file row measure twice")
            XCTAssertEqual(child.layoutContextRevision, revision)
            child.prepareMeasure(width: 120, height: 100)
            swiftomniui_winui_arrange(child.handle, 0, 0, 120, 100)
            XCTAssertEqual(child.safeAreaContext?.consumed, consumed)
            XCTAssertGreaterThan(words.desiredSize.height, 0)
            XCTAssertEqual(words.placedFrame.y, 0)

            child.setLayoutContext(SafeAreaContext(bounds: room,
                container: Rect(0, 12, 120, 88), consumed: consumed))
            XCTAssertGreaterThan(child.layoutContextRevision, revision)
            child.prepareMeasure(width: 120, height: 100)
            swiftomniui_winui_arrange(child.handle, 0, 0, 120, 100)
            XCTAssertEqual(words.placedFrame.y, 12)

            let external = DependencySizedPanel()
            let before = external.measurementRevision
            external.safeAreaContext = SafeAreaContext(bounds: room, consumed: consumed)
            XCTAssertGreaterThan(external.measurementRevision, before,
                                 "initial external context must still start native layout")
        }
    }

    func testFixedFrameSkipsIntrinsicSubtreeProbesButPreparesNativeText() {
        onUIThread {
            let words = WinUILabelView()
            words.setText("A fixed frame still prepares its wrapped native text")
            words.setLines(breaking: .wordWrap, maximum: nil)
            let child = DependencySizedPanel()
            child.setItems([WinUILayoutItem(view: words)])
            var values = LayoutValues()
            values.width = 120
            values.height = 64
            let item = WinUILayoutItem(view: child, values: values)
            for width in [nil, 0, 80, 240] as [Double?] {
                XCTAssertEqual(WinUILayoutView.querySize { item.size(offered: width) },
                               LayoutSize(width: 120, height: 64))
            }
            XCTAssertTrue(child.queries.isEmpty)
            let root = WinUISingleChildView()
            root.setItems([item])
            root.prepareMeasure(width: 120, height: 64)
            swiftomniui_winui_arrange(root.handle, 0, 0, 120, 64)
            XCTAssertFalse(child.queries.isEmpty)
            XCTAssertGreaterThan(words.desiredSize.height, 0)
            XCTAssertEqual(words.laidOutFrame.width, 120, accuracy: 1)
        }
    }

    func testNativeRetriesDoNotInvalidateAnUnchangedDescendantsIntrinsicProposals() {
        onUIThread {
            let words = WinUILabelView()
            words.setText("An unchanged nested subtree")
            let inner = DependencySizedPanel()
            inner.setItems([WinUILayoutItem(view: words)])
            let middle = DependencySizedPanel()
            middle.setItems([WinUILayoutItem(view: inner)])
            let root = WinUISingleChildView()
            root.setItems([WinUILayoutItem(view: middle)])
            root.prepareMeasure(width: 320, height: 100)
            swiftomniui_winui_arrange(root.handle, 0, 0, 320, 100)
            let queries = [middle.queries, inner.queries]
            let revision = words.measurementRevision
            let desired = words.desiredSize

            for _ in 0..<4 {
                // Model XAML retrying the native root at the same constraint,
                // without a Swift property or subtree dependency change.
                swiftomniui_winui_invalidate_measure(root.handle)
                var size = [0.0, 0.0]
                swiftomniui_winui_measure(root.handle, 320, 100, &size)
                swiftomniui_winui_arrange(root.handle, 0, 0, 320, 100)
                XCTAssertEqual([middle.queries, inner.queries], queries,
                               "a native pass is not a content revision of every descendant")
                XCTAssertEqual(words.measurementRevision, revision)
                XCTAssertEqual(words.desiredSize, desired)
                XCTAssertEqual(words.laidOutFrame.width, 320, accuracy: 1)
            }
        }
    }

    func testNativeWidthChangesReuseKnownProposalsButRealContentChangesDiscardThem() {
        onUIThread {
            let words = WinUILabelView()
            words.setText("Words that wrap when their allocated width becomes narrow")
            let child = DependencySizedPanel()
            child.setItems([WinUILayoutItem(view: words)])
            let root = WinUISingleChildView()
            root.setItems([WinUILayoutItem(view: child)])

            for width in [320.0, 120, 320, 120, 320] {
                swiftomniui_winui_invalidate_measure(root.handle)
                var size = [0.0, 0.0]
                swiftomniui_winui_measure(root.handle, width, 240, &size)
                swiftomniui_winui_arrange(root.handle, 0, 0, width, 240)
                XCTAssertEqual(words.laidOutFrame.width, width, accuracy: 1)
            }
            XCTAssertEqual(child.queries[320], 1)
            XCTAssertEqual(child.queries[120], 1)
            let previous = words.measurementRevision
            // Apply the same invalidation as a measured property patch, rather
            // than relying on another native pass to discover a Swift write.
            words.setText("New content\nwith another line\nand a third")
            words.invalidateMeasure()
            child.invalidateMeasurements()
            root.prepareMeasure(width: 320, height: 240)
            swiftomniui_winui_arrange(root.handle, 0, 0, 320, 240)

            XCTAssertGreaterThan(words.measurementRevision, previous)
            XCTAssertEqual(child.queries[320], 2)
            XCTAssertGreaterThan(words.desiredSize.height, 0)
            XCTAssertEqual(words.laidOutFrame.width, 320, accuracy: 1)
        }
    }
}
