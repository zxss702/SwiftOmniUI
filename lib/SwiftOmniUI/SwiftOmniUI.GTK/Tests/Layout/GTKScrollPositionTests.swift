// SPDX-FileCopyrightText: 2026 Pawe? Krzywdzi?ski and Contributors
// SPDX-License-Identifier: Apache-2.0

import Foundation
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIGTK
import SwiftOmniUIConformance
import XCTest

final class GTKScrollPositionTests: XCTestCase {
    func testScrollPositionModifierScopesToTheScrollViewWithTheModifier() {
        onUIThread {
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

    func testOnScrollGeometryChangeReportsContainerSizeAndContentUpdates() {
        onUIThread {
            var reportedWidths: [(CGFloat, CGFloat)] = []
            var reportedOffsets: [(CGFloat, CGFloat)] = []
            let width = State(wrappedValue: 240.0)
            let position = State(wrappedValue: ScrollPosition())
            let host = GTKRenderer.running(reducesMotion: true) {
                VStack {
                    Button("Wider").onClicked { width.wrappedValue = 320 }
                    Button("Scroll").onClicked { position.wrappedValue.scrollTo(x: 120) }
                    ScrollView(.horizontal) {
                        Text("wide content").frame(width: 800, height: 40)
                    }
                    .scrollPosition(position.projectedValue)
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        geometry.containerSize.width
                    } action: { old, new in
                        reportedWidths.append((old, new))
                    }
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        geometry.contentOffset.x
                    } action: { old, new in
                        reportedOffsets.append((old, new))
                    }
                    .frame(width: width.wrappedValue, height: 80)
                }
            }

            XCTAssertEqual(reportedWidths.count, 1)
            XCTAssertEqual(reportedWidths.first?.0 ?? -1, 0, accuracy: 0.5)
            XCTAssertEqual(reportedWidths.first?.1 ?? -1, 240, accuracy: 0.5)

            let buttons = host.views(GTKButtonView.self)
            buttons[0].click()
            host.settle { reportedWidths.count >= 2 }
            XCTAssertEqual(reportedWidths.count, 2)
            XCTAssertEqual(reportedWidths.last?.0 ?? -1, 240, accuracy: 0.5)
            XCTAssertEqual(reportedWidths.last?.1 ?? -1, 320, accuracy: 0.5)

            buttons[1].click()
            host.settle { reportedOffsets.last?.1 ?? 0 >= 119 }
            XCTAssertEqual(reportedOffsets.last?.0 ?? -1, 0, accuracy: 0.5)
            XCTAssertEqual(reportedOffsets.last?.1 ?? -1, 120, accuracy: 0.5)
        }
    }
}
