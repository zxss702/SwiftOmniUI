// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUIHost
import XCTest

@MainActor final class ProgramWriteTests: XCTestCase {
    func testNestedWritesCommitOnlyAfterTheOuterPatch() {
        var events: [Int] = []
        ProgramWrite.perform {
            ProgramWrite.afterWrites { events.append(3); XCTAssertFalse(ProgramWrite.isWriting) }
            ProgramWrite.perform {
                events.append(1)
                ProgramWrite.afterWrites { events.append(4) }
            }
            XCTAssertEqual(events, [1])
            events.append(2)
        }
        XCTAssertEqual(events, [1, 2, 3, 4])
        ProgramWrite.afterWrites { events.append(5) }
        XCTAssertEqual(events.last, 5)
    }

    func testFailedWriteStillReleasesItsNativeInvalidations() {
        enum Failure: Error { case expected }
        var committed = false
        XCTAssertThrowsError(try ProgramWrite.perform {
            ProgramWrite.afterWrites { committed = true }
            throw Failure.expected
        })
        XCTAssertTrue(committed)
        XCTAssertFalse(ProgramWrite.isWriting)
    }
}
