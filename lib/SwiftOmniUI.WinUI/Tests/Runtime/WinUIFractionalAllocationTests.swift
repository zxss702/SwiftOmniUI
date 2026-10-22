// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

@MainActor
private final class FractionalIntrinsicPanel: WinUILayoutView {
    let requirement: LayoutSize

    init(requirement: LayoutSize) {
        self.requirement = requirement
        super.init()
    }

    override func contentSize(width: Double?) -> LayoutSize { requirement }
}

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
private final class FractionalPreparationText: WinUITextView {
    var allocations: [ProposedViewSize] = []

    override func prepareMeasure(width: Double, height: Double? = nil) {
        allocations.append(ProposedViewSize(width: width, height: height))
        super.prepareMeasure(width: width, height: height)
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
    func testNativeIntrinsicMeasurementContainsTheCompleteLogicalRequirement() {
        onUIThread {
            // A representable text extent plus icon/padding crosses a Float
            // exponent boundary. Nearest conversion loses part of the text's
            // measured width/height, despite there being no real compression.
            let requirement = LayoutSize(width: Double(Float(42).nextUp) + 48,
                                         height: Double(Float(14).nextUp) + 32)
            XCTAssertLessThan(Double(Float(requirement.width)), requirement.width)
            let panel = FractionalIntrinsicPanel(requirement: requirement)
            let arithmetic = panel.naturalSize(width: nil)
            let native = WinUILayoutView.querySize { panel.measure(width: nil, height: nil) }
            XCTAssertEqual(native, arithmetic, "Swift and XAML must reserve the same intrinsic room")
            XCTAssertGreaterThanOrEqual(native.width, requirement.width)
            XCTAssertGreaterThanOrEqual(native.height, requirement.height)
            XCTAssertLessThan(Double(Float(native.width).nextDown), requirement.width,
                              "reserve only the smallest enclosing native extent, not pixel padding")
            XCTAssertLessThan(Double(Float(native.height).nextDown), requirement.height)

            // An actual smaller proposal still constrains native DesiredSize.
            // Outward intrinsic conversion must not disable real compression.
            let offered = LayoutSize(width: 80, height: 30)
            let constrained = WinUILayoutView.querySize {
                panel.measure(width: Optional(offered.width), height: Optional(offered.height))
            }
            XCTAssertLessThanOrEqual(constrained.width, offered.width)
            XCTAssertLessThanOrEqual(constrained.height, offered.height)
        }
    }

    func testEquivalentFloatStackAllocationsKeepTheSameNativeTextProposals() {
        onUIThread {
            let owner = WinUISingleChildView()
            let stack = WinUIStackView(axis: .vertical)
            stack.spacing = 16
            let heading = FractionalPreparationText()
            heading.setText("Heading")
            heading.setTextFont(size: 80, attributes: nil, family: nil)
            let subtitle = FractionalPreparationText()
            subtitle.setText("Subtitle")
            subtitle.setTextFont(size: 32, attributes: nil, family: nil)
            let row = FractionalAllocationPanel()
            row.fixedHeight = 112
            stack.setItems([WinUILayoutItem(view: heading), WinUILayoutItem(view: subtitle), WinUILayoutItem(view: row)])
            owner.setItems([WinUILayoutItem(view: stack)])

            // A quarter of one Float ULP changes Double stack compression,
            // but is the very same height at the native XAML boundary.
            let measured = Float(stack.naturalSize(width: 448).height).nextDown
            let measuredHeight = Double(measured)
            let logicalHeight = measuredHeight + Double(measured.ulp) / 4
            XCTAssertNotEqual(logicalHeight, measuredHeight)
            XCTAssertEqual(Float(logicalHeight), measured)
            stack.prepareMeasure(width: 448, height: measuredHeight)
            let desired = [heading.desiredSize, subtitle.desiredSize]
            let proposals = [heading.allocations.last!, subtitle.allocations.last!]
            let revision = stack.measurementRevision
            let rowMeasures = row.nativeMeasures
            heading.allocations.removeAll()
            subtitle.allocations.removeAll()

            for _ in 0..<8 {
                owner.withNativeArrange {
                    stack.prepareAllocation(in: Rect(0, 0, 448, logicalHeight))
                }
                XCTAssertEqual([heading.desiredSize, subtitle.desiredSize], desired,
                               "equivalent native allocations cannot change a leaf's DesiredSize during Arrange")
                stack.prepareMeasure(width: 448, height: measuredHeight)
                XCTAssertEqual(stack.measurementRevision, revision)
            }
            XCTAssertTrue(heading.allocations.allSatisfy { $0 == proposals[0] })
            XCTAssertTrue(subtitle.allocations.allSatisfy { $0 == proposals[1] },
                          "preparation and XAML Measure must select the same compressed text height")
            XCTAssertEqual(row.nativeMeasures, rowMeasures)
        }
    }

    func testFractionalStackCompressionDoesNotAlternateConsumedInsetsOrInvalidateItsRow() {
        onUIThread {
            let owner = WinUISingleChildView()
            let stack = WinUIStackView(axis: .vertical)
            stack.spacing = 16
            let heading = FractionalAllocationPanel()
            heading.fixedHeight = 114.96000671386719
            let headingText = FractionalPreparationText()
            headingText.setText("Heading")
            headingText.setTextFont(size: 160, attributes: nil, family: nil)
            heading.setItems([WinUILayoutItem(view: headingText)])
            let subtitle = FractionalAllocationPanel()
            subtitle.fixedHeight = 45.98400115966797
            let subtitleText = FractionalPreparationText()
            subtitleText.setText("Subtitle")
            subtitleText.setTextFont(size: 80, attributes: nil, family: nil)
            subtitle.setItems([WinUILayoutItem(view: subtitleText)])
            let buttonRow = FractionalAllocationPanel()
            buttonRow.fixedHeight = 112
            var headingItem = WinUILayoutItem(view: heading)
            headingItem.values.width = 180
            var subtitleItem = WinUILayoutItem(view: subtitle)
            subtitleItem.values.width = 448
            var buttonItem = WinUILayoutItem(view: buttonRow)
            buttonItem.values.width = 320
            stack.setItems([headingItem, subtitleItem, buttonItem])
            owner.setItems([WinUILayoutItem(view: stack)])

            let rawHeight = 304.94400787353516
            let measuredHeight = Double(Float(rawHeight))
            let consumed = EdgeInsets(top: 48, leading: 0, bottom: 0, trailing: 0)
            stack.safeAreaContext = SafeAreaContext(bounds: Rect(0, 0, 448, rawHeight), consumed: consumed)
            stack.prepareMeasure(width: 448, height: measuredHeight)
            let revision = buttonRow.measurementRevision
            let measures = buttonRow.nativeMeasures
            let subtitleDesired = subtitleText.desiredSize
            let subtitleProposal = subtitleText.allocations.last!

            for _ in 0..<16 {
                // The logical parent prepares the unrounded slot; XAML's
                // native Measure uses the single-precision height in the log.
                owner.withNativeArrange {
                    stack.prepareAllocation(in: Rect(0, 0, 448, rawHeight))
                }
                XCTAssertEqual(subtitleText.desiredSize, subtitleDesired,
                               "the log's exact Double/Float heights must not toggle the native subtitle's size")
                XCTAssertEqual(buttonRow.safeAreaContext?.consumed, consumed)
                stack.prepareMeasure(width: 448, height: measuredHeight)
                XCTAssertEqual(buttonRow.safeAreaContext?.consumed, consumed)
                XCTAssertEqual(buttonRow.measurementRevision, revision,
                               "no safe-area edge changed, so a row cannot become dirty on every phase")
                XCTAssertEqual(buttonRow.nativeMeasures, measures)
            }
            XCTAssertTrue(subtitleText.allocations.allSatisfy { $0 == subtitleProposal })
        }
    }

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
