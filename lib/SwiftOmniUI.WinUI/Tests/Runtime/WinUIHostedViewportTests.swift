// SPDX-License-Identifier: Apache-2.0
import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI
import SwiftOmniUIConformance
import XCTest

private enum ViewportProbeContract: ElementContract {
    static let nodeType: NodeType = "Tests.NativeViewport"
    static let tiers: [any Contract.Type] = [ViewContract.self]
    static let members: [any ContractMember] = []
}
private struct ViewportProbe: VisualElement {
    var node = Node(contract: ViewportProbeContract.self)
}
@MainActor private final class ViewportProbeControl: WinUIControl {
    let element = swiftomniui_winui_text_make()!
    let sizesToContentHeight = false
    let contentAffectsSize = false
    let scrollsUnderSafeArea = true
    var insets: EdgeInsets?
    var insetWrites = 0
    func safeAreaInsetsDidChange(top: Double, right: Double, bottom: Double, left: Double) {
        insets = EdgeInsets(top: top, leading: left, bottom: bottom, trailing: right)
        insetWrites += 1
    }
    isolated deinit { swiftomniui_winui_release(element) }
}

final class WinUIHostedViewportTests: XCTestCase {
    func testNativeScrollingControlReceivesFullViewportAndNonCumulativeDocumentInsets() throws {
        try onUIThread {
            SwiftOmniUIControls.add(ViewportProbeContract.self, create: { _ in ViewportProbeControl() })
            let header = State(wrappedValue: 40.0)
            let host = WinUIRenderer.running(reducesMotion: true) {
                NavigationStack {
                    ViewportProbe().frame(maxWidth: .infinity, maxHeight: .infinity)
                        .safeAreaInset(edge: .top, spacing: 0) { Text("Header").frame(height: header.wrappedValue) }
                        .safeAreaInset(edge: .bottom, spacing: 0) { Text("Footer").frame(height: 32) }
                }
            }
            let view = try XCTUnwrap(host.views(WinUIHostedView<ViewportProbeControl>.self).first)
            for height in [40.0, 72, 40] {
                header.wrappedValue = height
                for _ in 0..<8 { host.step(); host.frame() }
                let context = view.layoutSafeArea(in: Rect(0, 0, view.laidOutFrame.width, view.laidOutFrame.height))
                let expected = SafeAreaContext.insets(of: context.safe, in: context.bounds)
                let actual = try XCTUnwrap(view.control.insets)
                XCTAssertEqual(actual, expected)
                XCTAssertGreaterThanOrEqual(actual.top, height)
                XCTAssertGreaterThanOrEqual(actual.bottom, 32)
                var native = [Double](repeating: 0, count: 4)
                swiftomniui_winui_frame(view.control.element, &native)
                XCTAssertEqual(native[0], context.bounds.x, accuracy: 1)
                XCTAssertEqual(native[1], context.bounds.y, accuracy: 1)
                XCTAssertEqual(native[2], context.bounds.width, accuracy: 1)
                XCTAssertEqual(native[3], context.bounds.height, accuracy: 1)
                let writes = view.control.insetWrites
                for _ in 0..<4 { host.step(); host.frame() }
                XCTAssertEqual(view.control.insetWrites, writes, "unchanged layout must not rewrite the document's margins")
            }
        }
    }
}
