// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import CSwiftOmniUIWinUI
import XCTest

@MainActor
private final class SafeBarPreparationProbe: WinUILayoutView {
    var preparations: [ProposedViewSize] = []
    var nativeMeasurements: [ProposedViewSize] = []

    override func prepareMeasure(width: Double, height: Double? = nil) {
        preparations.append(ProposedViewSize(width: width, height: height))
        super.prepareMeasure(width: width, height: height)
    }

    override func measure(width: Double, height: Double) -> LayoutSize {
        nativeMeasurements.append(ProposedViewSize(width: width, height: height))
        return super.measure(width: width, height: height)
    }

    override func contentSize(width: Double?) -> LayoutSize {
        LayoutSize(width: width ?? 80, height: 40)
    }
}

final class WinUISafeBarOwnershipTests: XCTestCase {
    func testWindowDoesNotMeasureAPendingBarAtZeroWidthAndReusesItWhenReady() {
        onUIThread {
            let window = WinUIWindow()
            let page = WinUISingleChildView()
            let content = WinUILabelView()
            content.setText("Page")
            page.setItems([WinUILayoutItem(view: content)])
            let bar = SafeBarPreparationProbe()
            let native = WinUISafeAreaBarHost(bar: bar)
            let originalHandle = bar.handle
            defer {
                swiftomniui_winui_window_set_safe_area_bars(window.handle, nil, 0)
                native.releaseBar()
                window.close()
            }
            window.show(page, present: false)
            let handles: [SwiftOmniUIObjectRef?] = [native.presentationHandle]
            swiftomniui_winui_window_set_safe_area_bars(window.handle, handles, 1)
            swiftomniui_winui_window_set_safe_area_bar_frame(window.handle, 0, 0, 0)
            window.presentContent()
            WinUITestHost.pump()
            swiftomniui_winui_update_layout(page.handle)
            XCTAssertTrue(bar.nativeMeasurements.isEmpty,
                          "a pending page frame must not become a visible zero-width measurement")

            swiftomniui_winui_window_set_safe_area_bar_frame(window.handle, 0, 0, 120)
            swiftomniui_winui_update_layout(page.handle)
            XCTAssertFalse(bar.nativeMeasurements.isEmpty)
            XCTAssertTrue(bar.nativeMeasurements.allSatisfy { $0.width == 120 })
            XCTAssertEqual(bar.handle, originalHandle)

            bar.nativeMeasurements.removeAll()
            swiftomniui_winui_window_set_safe_area_bar_frame(window.handle, 0, 0, 0)
            swiftomniui_winui_update_layout(page.handle)
            XCTAssertTrue(bar.nativeMeasurements.isEmpty)
            swiftomniui_winui_window_set_safe_area_bar_frame(window.handle, 0, 0, 200)
            swiftomniui_winui_update_layout(page.handle)
            XCTAssertTrue(bar.nativeMeasurements.contains { $0.width == 200 })
            XCTAssertEqual(bar.handle, originalHandle)
        }
    }

    func testOnlyTheNativeHostPreparesAPromotedBarAtItsOwnWidth() {
        onUIThread {
            let bar = SafeBarPreparationProbe()
            let originalHandle = bar.handle
            let logical = WinUISingleChildView()
            logical.setItems([WinUILayoutItem(view: bar)])
            let native = WinUISafeAreaBarHost(bar: bar)
            defer { native.releaseBar() }

            XCTAssertEqual(logical.naturalSize(width: 320).height, 40,
                           "promotion must preserve the bar's logical size contribution")
            logical.prepareMeasure(width: 320, height: 40)
            XCTAssertTrue(bar.preparations.isEmpty,
                          "a logical plan must not select the promoted bar's native proposal")

            for width in [0.0, 120] {
                bar.preparations.removeAll()
                bar.nativeMeasurements.removeAll()
                native.prepareMeasure(width: width, height: 40)

                XCTAssertFalse(bar.preparations.isEmpty)
                XCTAssertTrue(bar.preparations.allSatisfy { $0.width == width && $0.height == 40 })
                XCTAssertFalse(bar.nativeMeasurements.isEmpty,
                               "the actual native owner must still prepare a real XAML measurement")
                XCTAssertTrue(bar.nativeMeasurements.allSatisfy { $0.width == width && $0.height == 40 })

                let preparations = bar.preparations.count
                logical.prepareMeasure(width: 320, height: 40)
                XCTAssertEqual(bar.preparations.count, preparations,
                               "logical preparation must not overwrite the native host's selected width")
                XCTAssertEqual(bar.handle, originalHandle)
                XCTAssertTrue(bar.nativeSafeBarOwner === native)
                XCTAssertTrue(bar.placingLayout === logical)
                XCTAssertTrue(logical.items.first?.view === bar)
            }
        }
    }

    func testReleasingTheNativeHostRestoresLogicalPreparationOnTheSameControl() {
        onUIThread {
            let bar = SafeBarPreparationProbe()
            let originalHandle = bar.handle
            let logical = WinUISingleChildView()
            logical.setItems([WinUILayoutItem(view: bar)])
            let native = WinUISafeAreaBarHost(bar: bar)
            native.prepareMeasure(width: 120, height: 40)
            native.releaseBar()
            bar.preparations.removeAll()

            logical.prepareMeasure(width: 320, height: 40)

            XCTAssertFalse(bar.preparations.isEmpty)
            XCTAssertTrue(bar.preparations.allSatisfy { $0.width == 320 && $0.height == 40 })
            XCTAssertNil(bar.nativeSafeBarOwner)
            XCTAssertEqual(bar.handle, originalHandle)
            XCTAssertTrue(bar.placingLayout === logical)
        }
    }
}
