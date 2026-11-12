// SPDX-FileCopyrightText: 2026 Pawe? Krzywdzi?ski and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIGTK
import SwiftOmniUIConformance
import XCTest

final class GTKScrollPositionTests: XCTestCase {
    func testScrollPositionModifierScopesToTheScrollViewWithTheModifier() throws {
        try onUIThread {
            let position = State(wrappedValue: ScrollPosition(edge: .bottom))
            let host = GTKRenderer.running(reducesMotion: true) {
                ScrollView { Text("content").frame(height: 1000) }
                    .scrollPosition(position.projectedValue)
                    .frame(width: 240, height: 200)
            }
            XCTAssertEqual(host.views(GTKScrollView.self).count, 1)
            XCTAssertFalse(position.wrappedValue.isPositionedByUser)
        }
    }
}
