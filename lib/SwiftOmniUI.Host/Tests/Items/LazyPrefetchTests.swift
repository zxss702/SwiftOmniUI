// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) @testable import SwiftOmniUIHost
import XCTest

@MainActor final class LazyPrefetchTests: XCTestCase {
    private final class Owner {}

    func testNativeMeasurementReadinessPausesWithoutSpinning() {
        let queue = LazyPrefetchQueue()
        let owner = Owner()
        var ready = true
        var calls = 0
        queue.schedule(owner: owner, ready: { ready }) {
            calls += 1
            ready = false
            return true
        }
        queue.drain()
        XCTAssertEqual(calls, 1)
        queue.drain()
        XCTAssertEqual(calls, 1)
        ready = true
        queue.drain()
        XCTAssertEqual(calls, 2)
        queue.cancel(owner: owner)
    }

    func testDirectionChangeDefersReplacementInsteadOfContinuingOldWork() {
        let queue = LazyPrefetchQueue()
        let owner = Owner()
        var calls: [Int] = []
        queue.schedule(owner: owner, ready: { true }) {
            calls.append(1)
            queue.schedule(owner: owner, ready: { true }) { calls.append(-1); return false }
            return true
        }
        queue.drain()
        XCTAssertEqual(calls, [1])
        queue.drain()
        XCTAssertEqual(calls, [1, -1])
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
        queue.drain()
        XCTAssertEqual(calls, [1])
        XCTAssertTrue(queue.isPending, "the old job's completion must not cancel its replacement")
        queue.drain()
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
        queue.drain()
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
