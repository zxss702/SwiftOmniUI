// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@_spi(Host) @testable import SwiftOmniUICore

@MainActor private var stackPositions: [Int: Int] = [:]

private struct NestedLevel: View {
    let depth: Int

    var body: some View {
        var position = depth
        withUnsafeMutablePointer(to: &position) {
            stackPositions[depth] = Int(bitPattern: $0)
        }
        return VStack {
            if depth < 40 { NestedLevel(depth: depth + 1) }
            else { Text("bottom") }
        }
    }
}

@MainActor final class DifferStackTests: XCTestCase {
    func testDeepTreesDoNotRetainPreparationFramesAtEveryLevel() throws {
        stackPositions = [:]
        let patch = Renders().render(NestedLevel(depth: 0).node)
        XCTAssertEqual(stackPositions.count, 41)
        XCTAssertTrue(patch.subtree.contains { $0.properties[.text] == .string("bottom") })
        let first = try XCTUnwrap(stackPositions[1])
        let last = try XCTUnwrap(stackPositions[40])
        XCTAssertLessThan(abs(first - last) / 39, 24 * 1024,
                          "temporary preparation and completion frames must return before descending")
    }
}
