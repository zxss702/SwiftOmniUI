// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIAndroid
import XCTest

/// A page whose second button goes when the first is clicked.
struct LeavingPage: View {
    @State private var shown = true

    var body: some View {
        VStack {
            Button("Hide")
                .onClicked { shown = false }
            if shown {
                Button("Leaving")
            }
        }
    }
}

final class AndroidLeaveTests: XCTestCase {
    static var allTests: [(String, (AndroidLeaveTests) -> () throws -> Void)] {
        [
            ("testAViewThatLeavesIsLetGoAndItsGroupNoLongerHoldsIt", testAViewThatLeavesIsLetGoAndItsGroupNoLongerHoldsIt),
        ]
    }

    /// Nothing in the host holds a control after the tree drops it: its number no longer answers a Java callback.
    func testAViewThatLeavesIsLetGoAndItsGroupNoLongerHoldsIt() throws {
        try onMainActor {
            let host = AndroidRenderer.running { LeavingPage() }
            XCTAssertEqual(host.views(AndroidButtonView.self).map(\.text), ["Hide", "Leaving"])
            let hide = try XCTUnwrap(host.views(AndroidButtonView.self).first)
            let leaving = try XCTUnwrap(host.views(AndroidButtonView.self).last?.number)
            let stack = try XCTUnwrap(host.views(AndroidStackView.self).first)

            hide.click()

            XCTAssertEqual(host.views(AndroidButtonView.self).map(\.text), ["Hide"])
            XCTAssertEqual(Java.callInt(stack.reference, TestJava.getChildCount), 1)
            XCTAssertNil(AndroidView.find(leaving))
        }
    }
}
