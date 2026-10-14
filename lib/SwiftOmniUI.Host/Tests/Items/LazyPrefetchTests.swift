// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) @testable import SwiftOmniUIHost
import XCTest

@MainActor final class LazyPrefetchTests: XCTestCase {
    private final class Owner {}

    func testDeadlineStopsOptionalWorkAndEachOwnerGetsOneTurnPerFrame() {
        let queue = LazyPrefetchQueue()
        let first = Owner(), second = Owner()
        let start = ContinuousClock.now
        var time = start
        queue.now = { time }
        var calls: [Int] = []
        queue.schedule(owner: first) { calls.append(1); time = time.advanced(by: .milliseconds(5)); return true }
        queue.schedule(owner: second) { calls.append(2); return false }
        queue.drain(until: start)
        XCTAssertTrue(calls.isEmpty)
        queue.drain(until: start.advanced(by: .milliseconds(4)))
        XCTAssertEqual(calls, [1])
        XCTAssertTrue(queue.isPending)
        queue.drain(until: start.advanced(by: .seconds(1)))
        XCTAssertEqual(calls, [1, 2, 1], "unfinished owners rotate so other layouts get the next frame")
        queue.cancel(owner: first)
        XCTAssertFalse(queue.isPending)
    }

    func testLatestViewportReplacesStaleWorkEvenDuringAJob() {
        let queue = LazyPrefetchQueue()
        let owner = Owner()
        var calls: [Int] = []
        queue.schedule(owner: owner) { calls.append(0); return false }
        queue.schedule(owner: owner) {
            calls.append(1)
            queue.schedule(owner: owner) { calls.append(2); return false }
            return false
        }
        queue.drain(until: ContinuousClock.now.advanced(by: .seconds(1)))
        XCTAssertEqual(calls, [1])
        XCTAssertTrue(queue.isPending, "the old job's completion must not cancel its replacement")
        queue.drain(until: ContinuousClock.now.advanced(by: .seconds(1)))
        XCTAssertEqual(calls, [1, 2])
        XCTAssertFalse(queue.isPending)
    }

    func testAnUnmountedOwnerDoesNotKeepTheClockOrItsRowClosureAlive() {
        let queue = LazyPrefetchQueue()
        var owner: Owner? = Owner()
        weak var held = owner
        var called = false
        queue.schedule(owner: owner!) { called = true; return false }
        owner = nil
        XCTAssertNil(held)
        XCTAssertFalse(queue.isPending)
        queue.drain(until: ContinuousClock.now.advanced(by: .seconds(1)))
        XCTAssertFalse(called)
    }

    func testPendingPrefetchHoldsTheDisplayClockUntilCancelled() {
        let runtime = HostRuntime.still()
        let owner = Owner()
        runtime.lazyPrefetch.schedule(owner: owner) { true }
        XCTAssertTrue(runtime.clock.held)
        runtime.lazyPrefetch.cancel(owner: owner)
        runtime.displayCycle.hold()
        XCTAssertFalse(runtime.clock.held)
    }
}
