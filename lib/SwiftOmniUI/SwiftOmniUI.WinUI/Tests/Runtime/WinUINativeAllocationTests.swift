// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import XCTest

@MainActor
private final class NativeAllocationContent: WinUILayoutView {
    var nativeMeasures = 0
    var naturalHeight = 40.0
    var arrangedHeights: [Double] = []

    override func measure(width: Double, height: Double) -> LayoutSize {
        nativeMeasures += 1
        return super.measure(width: width, height: height)
    }

    override func contentSize(width: Double?) -> LayoutSize {
        LayoutSize(width: 80, height: naturalHeight)
    }

    override func arrange(in bounds: Rect) {
        arrangedHeights.append(bounds.height)
    }
}

final class WinUINativeAllocationTests: XCTestCase {
    func testSOUIOwnedPanelDoesNotTurnItsMeasuredDestinationIntoANativeMinimum() {
        onUIThread {
            let parent = WinUIStackView(axis: .vertical)
            let child = NativeAllocationContent()
            child.naturalHeight = 128
            parent.setItems([WinUILayoutItem(view: child)])
            child.prepareMeasure(width: 320, height: 128)
            XCTAssertEqual(child.naturalSize(width: 320), LayoutSize(width: 80, height: 128))
            XCTAssertEqual(child.desiredSize, .zero,
                           "the Swift parent already reads intrinsic size and owns the actual native slot")
            let measures = child.nativeMeasures
            for height in [40.0, 52, 84, 128, 84, 40] {
                swiftomniui_winui_arrange(child.handle, 0, 0, 320, height)
                XCTAssertEqual(child.arrangedHeights.last, height,
                               "XAML must pass the presentation slot to ArrangeOverride, rather than expand it to 128")
                XCTAssertEqual(child.laidOutFrame.height, height, accuracy: 0.01)
                XCTAssertEqual(child.nativeMeasures, measures,
                               "a presentation allocation does not require a compensating native Measure")
            }
        }
    }

    func testScrollDocumentStillPublishesItsExtentToItsNativeOwner() {
        onUIThread {
            let child = NativeAllocationContent()
            child.naturalHeight = 1000
            let document = WinUIScrollDocument()
            document.setItems([WinUILayoutItem(view: child)])
            document.prepareMeasure(width: 320)
            XCTAssertEqual(document.desiredSize.height, 1000)
            XCTAssertEqual(child.desiredSize, .zero)
        }
    }

    func testNativeMeasurementContractChangesWithOwnershipAtTheSameProposal() {
        onUIThread {
            let parent = WinUIStackView(axis: .vertical)
            let child = NativeAllocationContent()
            child.prepareMeasure(width: 320, height: 128)
            let intrinsic = child.desiredSize
            XCTAssertEqual(intrinsic, LayoutSize(width: 80, height: 40))
            parent.setItems([WinUILayoutItem(view: child)])
            child.prepareMeasure(width: 320, height: 128)
            XCTAssertEqual(child.desiredSize, .zero)
            XCTAssertFalse(parent.setItems([WinUILayoutItem(view: child)]),
                           "the ownership observer must be included in the stored child revision snapshot")
            parent.setItems([])
            child.prepareMeasure(width: 320, height: 128)
            XCTAssertEqual(child.desiredSize, intrinsic,
                           "leaving SOUI allocation must restore the native owner's intrinsic contract")
        }
    }

    func testNativeOwnedPageReportsItsAllocatedFrameWhileKeepingItsNaturalSize() {
        onUIThread {
            let owner = WinUINavigationView()
            let child = NativeAllocationContent()
            let page = WinUISingleChildView()
            page.setItems([WinUILayoutItem(view: child)])
            owner.setItems([WinUILayoutItem(view: page)])

            page.prepareMeasure(width: 320, height: 240)

            XCTAssertEqual(page.naturalSize(width: 320).height, 40)
            XCTAssertEqual(page.desiredSize, LayoutSize(width: 320, height: 240),
                           "XAML must see the same page allocation that was used to prepare its child plan")
            let measures = child.nativeMeasures
            swiftomniui_winui_arrange(page.handle, 0, 0, 320, 240)
            XCTAssertEqual(child.nativeMeasures, measures,
                           "the first native Arrange must not switch from an intrinsic frame to the allocated frame")
            XCTAssertEqual(child.placedFrame, Rect(0, 0, 320, 240))

            page.prepareMeasure(width: 320)
            XCTAssertEqual(page.desiredSize.height, 40,
                           "an unspecified axis still reports its real intrinsic extent")
            page.prepareMeasure(width: 120, height: 80)
            XCTAssertEqual(page.desiredSize, LayoutSize(width: 120, height: 80))
            XCTAssertEqual(page.naturalSize(width: 120).height, 40)
        }
    }

    func testAContentSizedNativeLabelDoesNotClaimItsMaximumAvailableSpace() {
        onUIThread {
            let label = WinUISingleChildView()
            label.setItems([WinUILayoutItem(view: NativeAllocationContent())])
            label.prepareMeasure(width: 320, height: 240)
            XCTAssertEqual(label.desiredSize.height, 40,
                           "a native button/flyout label still requests its content's height")
            XCTAssertLessThan(label.desiredSize.width, 320)
        }
    }

    func testSplitQueriesMeasureTheirOwnCompleteProposalBeforeAnySplitCallback() {
        onUIThread {
            let split = WinUISplitView()
            let pane = WinUISingleChildView()
            pane.setItems([WinUILayoutItem(view: NativeAllocationContent())])
            let detail = WinUISingleChildView()
            detail.setItems([WinUILayoutItem(view: NativeAllocationContent())])
            split.setItems([WinUILayoutItem(view: pane), WinUILayoutItem(view: detail)])

            let firstProposal = ProposedViewSize(width: 480, height: 240)
            let first = split.naturalSize(proposal: firstProposal)
            XCTAssertGreaterThan(first.width, 0)
            XCTAssertGreaterThan(first.height, 0,
                                 "the initial intrinsic query cannot read a zero previous measurement")
            XCTAssertEqual(first, split.sidebar.measure(width: 480, height: 240))
            for proposal in [ProposedViewSize(width: 480, height: 80),
                             ProposedViewSize(width: 320, height: 160)] {
                let size = split.naturalSize(proposal: proposal)
                XCTAssertEqual(size, split.sidebar.measure(width: proposal.width, height: proposal.height))
            }
            XCTAssertEqual(split.naturalSize(proposal: firstProposal), first,
                           "a later height must not overwrite the earlier proposal's intrinsic answer")
        }
    }

    func testContentSizedWelcomeNavigationCompletesItsFirstWindowLayout() throws {
        try onUIThread {
            let host = WinUIRenderer.running(reducesMotion: true, application: { NativeAllocationWelcomeApp() })
            let pages = host.views(WinUISingleChildView.self).filter { $0.nativeLayoutOwner is WinUINavigationView }
            XCTAssertFalse(pages.isEmpty)
            for page in pages {
                XCTAssertGreaterThan(page.laidOutFrame.width, 0)
                XCTAssertGreaterThan(page.laidOutFrame.height, 0)
                XCTAssertEqual(page.desiredSize.width, page.laidOutFrame.width, accuracy: 1)
                XCTAssertEqual(page.desiredSize.height, page.laidOutFrame.height, accuracy: 1)
            }
            let button = try XCTUnwrap(host.view(id: .manual("start")))
            XCTAssertGreaterThan(button.laidOutFrame.width, 0)
            WinUIDoorbell.commitPending()
            host.layOut()
            let sizings = WinUILayoutView.sizings
            for _ in 0..<4 { host.layOut() }
            XCTAssertEqual(WinUILayoutView.sizings, sizings)
            XCTAssertTrue(host.view(id: .manual("start")) === button)
        }
    }
}

private struct NativeAllocationWelcomeApp: App {
    var body: some Scene {
        Window("Welcome", id: "native.allocation.welcome") {
            NavigationStack {
                VStack(spacing: 16) {
                    Text("Welcome").font(.system(size: 48))
                    Text("A content-sized navigation window")
                    Button {} label: {
                        Text("Start").frame(maxWidth: 256).frame(height: 48)
                    }.buttonStyle(.plain).padding(32).id("start")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(32)
                .overlay(alignment: .bottom) { Text("Footer").padding(16) }
                .toolbar { ToolbarItem { Text("") } }
            }
            .frame(width: 720, height: 400)
        }
        .windowResizability(.contentSize)
    }
}
