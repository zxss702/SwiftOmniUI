// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@testable import SwiftOmniUIWinUI
import XCTest

final class WinUILazyPrefetchTests: XCTestCase {
    func testIncreasingSpeedPredictsTravelFromTheCurrentFrameInBothDirections() {
        for direction in [-1.0, 1.0] {
            var samples = WinUILazyPrefetch.MotionSamples()
            // x(t) = 0.125 * t squared. At t=32 velocity is 8 DIP/ms;
            // the next 16ms travel 160 DIP, not the preceding interval's 96.
            _ = samples.observe(offset: 0, time: 0, refreshInterval: 0)
            _ = samples.observe(offset: direction * 32, time: 16, refreshInterval: 0)
            let motion = samples.observe(offset: direction * 128, time: 32, refreshInterval: 0)!
            XCTAssertEqual(motion.velocity, direction * 8, accuracy: 0.001)
            XCTAssertEqual(motion.acceleration, direction * 0.25, accuracy: 0.001)
            XCTAssertEqual(WinUILazyPrefetch.distance(velocity: motion.velocity, interval: 16,
                readiness: 0, neighbour: 0, acceleration: motion.acceleration), direction * 160, accuracy: 0.001)
            let reversed = samples.observe(offset: 0, time: 48, refreshInterval: 0)!
            XCTAssertEqual(reversed.velocity, -direction * 8, accuracy: 0.001)
            XCTAssertEqual(reversed.acceleration, 0)
        }
    }

    func testBrakingDoesNotPredictAReversalOrRetainAcceleration() {
        var samples = WinUILazyPrefetch.MotionSamples()
        _ = samples.observe(offset: 0, time: 0, refreshInterval: 0)
        _ = samples.observe(offset: 160, time: 16, refreshInterval: 0)
        let motion = samples.observe(offset: 176, time: 32, refreshInterval: 0)!
        XCTAssertEqual(motion.velocity, 1)
        XCTAssertEqual(motion.acceleration, 0)
        XCTAssertEqual(WinUILazyPrefetch.distance(velocity: 8, interval: 16,
            readiness: 160, neighbour: 0, acceleration: 0.25), 1_440,
            "a short acceleration must not grow quadratically with a slow row's preparation time")
    }

    func testSeveralNoticesWithinARefreshKeepTheirWholeMovementForTheNextSample() {
        var samples = WinUILazyPrefetch.MotionSamples()
        XCTAssertNil(samples.observe(offset: 0, time: 0, refreshInterval: 16))
        XCTAssertNil(samples.observe(offset: 8, time: 4, refreshInterval: 16))
        XCTAssertNil(samples.observe(offset: 16, time: 8, refreshInterval: 16))
        XCTAssertNil(samples.observe(offset: 24, time: 12, refreshInterval: 16))
        let next = samples.observe(offset: 32, time: 16, refreshInterval: 16)
        XCTAssertEqual(next?.velocity, 2)
        XCTAssertEqual(next?.interval, 16)
        XCTAssertNil(samples.observe(offset: 48, time: 24, refreshInterval: 16))
        XCTAssertEqual(samples.observe(offset: 64, time: 32, refreshInterval: 16)?.velocity, 2)
        // A reversal uses the new direction immediately at the next sample,
        // rather than averaging forward motion into the backward lead.
        XCTAssertEqual(samples.observe(offset: 32, time: 48, refreshInterval: 16)?.velocity, -2)
    }

    func testRepeatedAndBackwardsTimestampsCannotReplaceTheLastMovementSample() {
        var samples = WinUILazyPrefetch.MotionSamples()
        XCTAssertNil(samples.observe(offset: 0, time: 0, refreshInterval: 0))
        XCTAssertNil(samples.observe(offset: 20, time: 0, refreshInterval: 0))
        XCTAssertNil(samples.observe(offset: 30, time: -1, refreshInterval: 0))
        XCTAssertEqual(samples.observe(offset: 40, time: 32, refreshInterval: 0)?.velocity, 1.25)
        XCTAssertEqual(samples.observe(offset: 0, time: 64, refreshInterval: 0)?.velocity, -1.25)
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
