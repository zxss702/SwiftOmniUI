// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@testable import SwiftOmniUIWinUI
import XCTest

final class WinUILazyPrefetchTests: XCTestCase {
    func testBunchedNativeNoticesCannotInventMovementFasterThanTheirDisplayInterval() {
        XCTAssertEqual(WinUILazyPrefetch.velocity(distance: 20, elapsed: 0.1, refreshInterval: 16), 1.25)
        XCTAssertEqual(WinUILazyPrefetch.velocity(distance: -40, elapsed: 32, refreshInterval: 16), -1.25)
        XCTAssertEqual(WinUILazyPrefetch.velocity(distance: 20, elapsed: 0, refreshInterval: 0), 0)
    }

    func testExistingNeighbourCoversIdleAndSlowMotion() {
        for velocity in [0.0, 0.5, -0.5] {
            XCTAssertEqual(WinUILazyPrefetch.distance(velocity: velocity, interval: 16, readiness: 20,
                                                    neighbour: 40), 0)
        }
    }

    func testDistanceUsesMeasuredSpeedAndReadinessInTheMovingDirection() {
        for direction in [-1.0, 1.0] {
            XCTAssertEqual(WinUILazyPrefetch.distance(velocity: direction * 4, interval: 16, readiness: 20,
                                                    neighbour: 40), direction * 104)
            XCTAssertEqual(WinUILazyPrefetch.distance(velocity: direction * 4, interval: 16, readiness: 4,
                                                    neighbour: 40), direction * 40)
        }
    }

    func testFastMotionUsesItsCalculatedDistanceWithoutAFixedScreenCap() {
        XCTAssertEqual(WinUILazyPrefetch.distance(velocity: 40, interval: 16, readiness: 20,
                                                neighbour: 40), 1_400)
    }

    func testMeasuredViewportLagIsCoveredOnlyInTheMovingDirection() {
        XCTAssertEqual(WinUILazyPrefetch.distance(velocity: 0, interval: 16, readiness: 20,
                                                neighbour: 40, observationLead: 50), 0)
        XCTAssertEqual(WinUILazyPrefetch.distance(velocity: 4, interval: 16, readiness: 20,
                                                neighbour: 40, observationLead: 50), 154)
        XCTAssertEqual(WinUILazyPrefetch.distance(velocity: -4, interval: 16, readiness: 20,
                                                neighbour: 40, observationLead: -50), -154)
        XCTAssertEqual(WinUILazyPrefetch.distance(velocity: 4, interval: 16, readiness: 20,
                                                neighbour: 40, observationLead: -50), 104)
    }

    func testRepeatedNotificationsForOneRenderingTimeRunOnlyOneFrame() throws {
        try onUIThread {
            let clock = WinUIFrameClock(now: { 0 }, ticksWithWinUI: true)
            var calls = 0
            clock.onFrame = { _ in calls += 1 }
            clock.held = true
            defer { clock.held = false }
            clock.frame(renderingTime: 10)
            clock.frame(renderingTime: 10)
            clock.held = false
            clock.held = true
            clock.frame(renderingTime: 10)
            clock.frame(renderingTime: 20)
            XCTAssertEqual(calls, 2)
        }
    }
}
