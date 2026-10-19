// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

@MainActor
private final class FractionalAllocationPanel: WinUISingleChildView {
    var fixedHeight: Double?
    var nativeMeasures = 0
    var measuresDuringArrange = 0

    override func measure(width: Double, height: Double) -> LayoutSize {
        nativeMeasures += 1
        if WinUIView.arranging > 0 { measuresDuringArrange += 1 }
        return super.measure(width: width, height: height)
    }

    override func contentSize(width: Double?) -> LayoutSize {
        var size = super.contentSize(width: width)
        if let fixedHeight { size.height = fixedHeight }
        return size
    }
}

@MainActor
private struct FractionalAllocationTree {
    let root = FractionalAllocationPanel()
    let frame = FractionalAllocationPanel()
    let content = FractionalAllocationPanel()
    let text = WinUILabelView()

    init() {
        text.setText("Content inside the first allocated frame")
        content.setItems([WinUILayoutItem(view: text)])
        frame.fixedHeight = 800
        frame.setItems([WinUILayoutItem(view: content)])
        var item = WinUILayoutItem(view: frame)
        item.values.height = 800
        root.setItems([item])
    }

    var counts: [Int] { [root.nativeMeasures, frame.nativeMeasures, content.nativeMeasures] }
    var measuresDuringArrange: Int {
        root.measuresDuringArrange + frame.measuresDuringArrange + content.measuresDuringArrange
    }
}

final class WinUIFractionalAllocationTests: XCTestCase {
    func testFirstFractionalArrangeKeepsNativeDesiredSizeAndPlacesTheCompleteSubtree() {
        onUIThread {
            let tree = FractionalAllocationTree()
            tree.root.prepareMeasure(width: 320, height: 792)
            let counts = tree.counts
            let desired = tree.frame.desiredSize
            // Reproduce the log's 175% display-scale allocation without
            // depending on the monitor used to run this test.
            let allocatedHeight = Double(Float(792 + 1 / 1.75))

            swiftomniui_winui_arrange(tree.root.handle, 0, 0, 320, allocatedHeight)

            XCTAssertEqual(tree.counts, counts,
                           "Arrange must prepare a SOUI panel's child plan without measuring that panel again")
            XCTAssertEqual(tree.measuresDuringArrange, 0)
            XCTAssertEqual(tree.frame.desiredSize, desired,
                           "the parent's active Arrange must not replace its child's native measure result")
            XCTAssertEqual(desired.height, 792)
            let descendants: [WinUIView] = [tree.frame, tree.content, tree.text]
            for view in descendants {
                XCTAssertEqual(view.laidOutFrame.height, allocatedHeight, accuracy: 0.001,
                               "keeping DesiredSize must still arrange every descendant at the actual allocation")
            }
        }
    }

    func testRepeatedMeasuredAndFractionalAllocatedSlotsDoNotRestartNativeMeasurement() {
        onUIThread {
            let tree = FractionalAllocationTree()
            tree.root.prepareMeasure(width: 320, height: 792)
            let counts = tree.counts
            let allocatedHeight = Double(Float(792 + 1 / 1.75))

            for _ in 0..<8 {
                tree.root.prepareMeasure(width: 320, height: 792)
                swiftomniui_winui_arrange(tree.root.handle, 0, 0, 320, allocatedHeight)
            }

            XCTAssertEqual(tree.counts, counts,
                           "one physical pixel between Measure and Arrange cannot create another native pass")
            XCTAssertEqual(tree.measuresDuringArrange, 0)
            XCTAssertEqual(tree.content.placedFrame.height, allocatedHeight)
        }
    }

    func testAnAllocationPlanDoesNotSuppressTheNextRealMeasureOrTextChange() {
        onUIThread {
            let tree = FractionalAllocationTree()
            tree.root.prepareMeasure(width: 320, height: 792)
            swiftomniui_winui_arrange(tree.root.handle, 0, 0, 320, Double(Float(792 + 1 / 1.75)))
            let measures = tree.root.nativeMeasures

            tree.root.prepareMeasure(width: 120, height: 240)
            swiftomniui_winui_arrange(tree.root.handle, 0, 0, 120, 240)
            XCTAssertGreaterThan(tree.root.nativeMeasures, measures)
            XCTAssertEqual(tree.content.laidOutFrame.width, 120, accuracy: 0.001)
            let before = tree.content.naturalSize(width: 120).height

            tree.text.setText("Changed\ncontent\nwith\nmore\nlines")
            tree.text.invalidateMeasure()
            tree.content.invalidateMeasurements()
            tree.root.prepareMeasure(width: 120, height: 240)
            swiftomniui_winui_arrange(tree.root.handle, 0, 0, 120, 240)

            XCTAssertGreaterThan(tree.content.naturalSize(width: 120).height, before)
            XCTAssertGreaterThan(tree.text.laidOutFrame.height, 0)
            XCTAssertTrue(tree.content.items.first?.view === tree.text)
        }
    }
}
