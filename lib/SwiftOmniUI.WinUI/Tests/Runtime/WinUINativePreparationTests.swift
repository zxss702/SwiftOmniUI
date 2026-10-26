// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

/// Counts native callbacks and explicit invalidations separately: changing a
/// proposal may enter Measure, but it must not dirty the view being measured.
@MainActor private final class PreparationCallbackPanel: WinUISingleChildView {
    var nativeMeasures = 0
    var nativeArrangements = 0
    var nativeInvalidations = 0

    override func measure(width: Double, height: Double) -> LayoutSize {
        nativeMeasures += 1
        return super.measure(width: width, height: height)
    }

    override func arrange(in bounds: Rect) {
        nativeArrangements += 1
        super.arrange(in: bounds)
    }

    override func invalidateNativeMeasure() {
        nativeInvalidations += 1
        super.invalidateNativeMeasure()
    }
}

final class WinUINativePreparationTests: XCTestCase {
    func testFiniteAndUnboundedPreparationInAWindowSettlesWithoutRedirtyingThePanel() {
        onUIThread {
            let label = WinUILabelView()
            label.setText("A short line")
            let child = PreparationCallbackPanel()
            child.setItems([WinUILayoutItem(view: label)])
            let root = PreparationCallbackPanel()
            root.setItems([WinUILayoutItem(view: child)])
            WinUITestHost.window.show(root)
            defer { WinUITestHost.window.show(nil) }
            for _ in 0..<8 {
                swiftomniui_winui_update_layout(root.handle)
                WinUIDoorbell.commitPending()
            }
            let width = root.laidOutFrame.width
            let height = root.laidOutFrame.height
            XCTAssertGreaterThan(width, 0)
            XCTAssertGreaterThan(height, 0)
            let invalidations = [root.nativeInvalidations, child.nativeInvalidations]
            let desired = root.desiredSize

            let offeredHeights: [Double?] = [128, nil, 40, nil, 128, height]
            for offeredHeight in offeredHeights {
                root.prepareMeasure(width: width, height: offeredHeight)
            }
            XCTAssertEqual([root.nativeInvalidations, child.nativeInvalidations], invalidations,
                           "proposal changes call native Measure without forcing InvalidateMeasure")
            XCTAssertEqual(root.desiredSize, desired,
                           "all proposals fit the same unchanged native content")

            for _ in 0..<8 {
                swiftomniui_winui_update_layout(root.handle)
                WinUIDoorbell.commitPending()
            }
            let measures = [root.nativeMeasures, child.nativeMeasures]
            let arrangements = [root.nativeArrangements, child.nativeArrangements]
            for _ in 0..<8 {
                swiftomniui_winui_update_layout(root.handle)
                WinUIDoorbell.commitPending()
            }
            XCTAssertEqual([root.nativeMeasures, child.nativeMeasures], measures)
            XCTAssertEqual([root.nativeArrangements, child.nativeArrangements], arrangements,
                           "unchanged native DesiredSize must reach a fixed point")
        }
    }

    func testRestoringAProbeWithUnchangedDesiredSizeDoesNotRemeasureTheNativeParent() {
        onUIThread {
            // Clear spacers participate in arithmetic without replacing the
            // native allocation already prepared for the containing row.
            let spacer = WinUIPathView()
            let spacerParent = PreparationCallbackPanel()
            spacerParent.setItems([WinUILayoutItem(view: spacer)])
            spacerParent.prepareMeasure(width: 320, height: 128)
            swiftomniui_winui_arrange(spacerParent.handle, 0, 0, 320, 128)
            let spacerMeasures = spacerParent.nativeMeasures
            for width in [nil, 20.0, 480] as [Double?] {
                XCTAssertEqual(spacer.measure(width: width, height: nil), .zero)
                spacerParent.prepareMeasure(width: 320, height: 128)
                XCTAssertEqual(spacerParent.nativeMeasures, spacerMeasures)
            }
            // The native owner can resize a shape with no Swift placing parent.
            // ArrangeOverride must publish that size without SizeChanged help.
            let standalone = WinUIPathView()
            for width in [80.0, 120, 64] {
                standalone.prepareMeasure(width: width, height: 40)
                swiftomniui_winui_arrange(standalone.handle, 0, 0, width, 40)
                XCTAssertEqual(standalone.committedFrame, Rect(0, 0, width, 40))
            }
            let label = WinUILabelView()
            label.setText("Short")
            let child = PreparationCallbackPanel()
            child.setItems([WinUILayoutItem(view: label)])
            let root = PreparationCallbackPanel()
            root.setItems([WinUILayoutItem(view: child)])
            root.prepareMeasure(width: 320, height: 128)
            let desired = label.desiredSize
            let measures = [root.nativeMeasures, child.nativeMeasures]

            for _ in 0..<3 {
                _ = child.naturalSize(width: 200)
                XCTAssertEqual(label.desiredSize, desired,
                               "both proposals fit the same line without changing native DesiredSize")
                root.prepareMeasure(width: 320, height: 128)
                XCTAssertEqual([root.nativeMeasures, child.nativeMeasures], measures,
                               "restoring a descendant's proposal must not invalidate its unchanged native parent")
                XCTAssertEqual(label.desiredSize, desired)
            }
        }
    }

    func testPreparingAnUnchangedRootRestoresADescendantDisturbedByAnIntrinsicProbe() {
        onUIThread {
            let label = WinUILabelView()
            label.setText("A descendant's speculative narrow proposal must not remain its native allocation")
            label.setTextFont(size: 17, attributes: nil, family: nil)
            let child = PreparationCallbackPanel()
            child.setItems([WinUILayoutItem(view: label)])
            let root = PreparationCallbackPanel()
            root.setItems([WinUILayoutItem(view: child)])

            root.prepareMeasure(width: 320, height: 128)
            let wide = label.desiredSize
            let rootDesired = root.desiredSize
            let invalidations = root.nativeInvalidations
            _ = WinUILayoutView.querySize { child.naturalSize(width: 48) }
            XCTAssertGreaterThan(label.desiredSize.height, wide.height)
            XCTAssertLessThan(label.desiredSize.width, wide.width)

            // Root's native constraint is still 320 x 128. XAML may return its
            // cached result, so the host must restore the descendant plan too.
            root.prepareMeasure(width: 320, height: 128)
            XCTAssertEqual(root.nativeInvalidations, invalidations)
            XCTAssertEqual(root.desiredSize, rootDesired)
            XCTAssertEqual(label.desiredSize, wide,
                           "a native cache hit cannot leave the leaf measured at the speculative width")
            swiftomniui_winui_arrange(root.handle, 0, 0, 320, 128)
            XCTAssertEqual(label.laidOutFrame.width, 320, accuracy: 1)
            let measures = [root.nativeMeasures, child.nativeMeasures]
            for _ in 0..<4 { root.prepareMeasure(width: 320, height: 128) }
            XCTAssertEqual(label.desiredSize, wide)
            XCTAssertEqual([root.nativeMeasures, child.nativeMeasures], measures,
                           "the restored native subtree can reuse its completed preparation")
        }
    }

    func testWrappedTextRestoresWideNarrowWideAllocationsAndStillMeasuresNewContent() throws {
        try onUIThread {
            let width = State(wrappedValue: 320.0)
            let words = State(wrappedValue: "Wrapping words must follow the actual width selected by their parent layout.")
            let host = WinUIRenderer.running(reducesMotion: true) {
                VStack(spacing: 0) {
                    Text(words.wrappedValue).font(.system(size: 17)).id("words")
                }.frame(width: width.wrappedValue)
            }
            for _ in 0..<8 { host.step(); host.layOut() }
            let label = try XCTUnwrap(host.view(id: .manual("words")))
            let wide = label.laidOutFrame
            XCTAssertEqual(wide.width, 320, accuracy: 1)

            width.wrappedValue = 88
            for _ in 0..<8 { host.step(); host.layOut() }
            XCTAssertEqual(label.laidOutFrame.width, 88, accuracy: 1)
            XCTAssertGreaterThan(label.laidOutFrame.height, wide.height)

            width.wrappedValue = 320
            for _ in 0..<8 { host.step(); host.layOut() }
            XCTAssertEqual(label.laidOutFrame.width, wide.width, accuracy: 1)
            XCTAssertEqual(label.laidOutFrame.height, wide.height, accuracy: 1)
            let revision = label.measurementRevision
            words.wrappedValue = Array(repeating: "New native content must still be measured.", count: 8)
                .joined(separator: "\n")
            for _ in 0..<8 { host.step(); host.layOut() }
            XCTAssertTrue(host.view(id: .manual("words")) === label)
            XCTAssertGreaterThan(label.measurementRevision, revision)
            XCTAssertGreaterThan(label.laidOutFrame.height, wide.height)
            let changed = label.laidOutFrame
            let sizings = WinUILayoutView.sizings
            for _ in 0..<8 { host.step(); host.layOut() }
            XCTAssertEqual(label.laidOutFrame, changed)
            XCTAssertEqual(WinUILayoutView.sizings, sizings,
                           "a real content update settles after producing its new layout")
        }
    }
}
