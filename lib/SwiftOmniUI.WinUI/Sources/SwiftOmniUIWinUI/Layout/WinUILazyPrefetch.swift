// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// Distances are DIPs, time is milliseconds. The next observed frame can move
/// while requested rows are being built and arranged. The compositor's viewport
/// observation can lag its latest offset. Existing neighbours
/// already cover part of that distance; only the remainder needs prefetch.
enum WinUILazyPrefetch {
    /// Arrangement can finish another batch before the next scroll callback.
    /// Retire the batch a native Rendered already completed before merging
    /// more work; otherwise continuous scrolling measures the whole gesture.
    struct PreparedRows {
        struct Completion {
            let duration: Double
            let identities: Set<String>
        }
        private var pending: (started: Double, rendered: Double, identities: Set<String>)?

        mutating func completed(at rendered: Double) -> Completion? {
            guard let pending, rendered > pending.rendered else { return nil }
            self.pending = nil
            return Completion(duration: max(0, rendered - pending.started), identities: pending.identities)
        }

        mutating func arranged(started: Double, rendered: Double, identities: Set<String>) -> Completion? {
            let completion = completed(at: rendered)
            if var previous = pending {
                previous.started = min(previous.started, started)
                previous.identities.formUnion(identities)
                pending = previous
            } else { pending = (started, rendered, identities) }
            return completion
        }

        mutating func reset() { pending = nil }
    }

    /// Rendering can arrive several times inside one display refresh. Keep
    /// those distances together before estimating speed and acceleration;
    /// dispatcher-sized fragments otherwise produce alternating spikes.
    struct MotionSamples {
        private var latest: (offset: Double, time: Double)?
        private var preceding: (offset: Double, time: Double)?
        private var observed: (offset: Double, time: Double)?
        private var direction: Double = 0

        mutating func observe(offset: Double, time: Double, refreshInterval: Double)
            -> (velocity: Double, interval: Double, acceleration: Double)? {
            guard let latest else {
                latest = (offset, time)
                observed = (offset, time)
                return nil
            }
            guard let observed, time > observed.time else { return nil }
            let movement = offset - observed.offset
            self.observed = (offset, time)
            // Animation setup may emit stationary frames before movement begins.
            // They establish the start of motion, not part of its travel time.
            // Once motion starts, retain stationary samples in the denominator
            // so a delayed native offset cannot produce a velocity spike.
            if direction == 0, movement == 0 {
                self.latest = (offset, time)
                return nil
            }
            if movement * direction < 0 {
                // A refresh may contain both forward and backward movement.
                // Do not keep prefetching the old edge while waiting to merge
                // the next sample, or cancel the reversal against forward travel.
                // Keep at least a refresh's denominator: short dispatcher
                // fragments must not magnify a small reversal into a large lead.
                let interval = max(refreshInterval, time - observed.time)
                self.preceding = nil
                self.latest = (offset, time)
                direction = movement
                return (movement / interval, interval, 0)
            }
            let beginsMotion = direction == 0 && movement != 0
            if movement != 0 { direction = movement }
            let elapsed = time - latest.time
            guard offset != latest.offset, elapsed > 0 else { return nil }
            if elapsed < refreshInterval {
                // Rendering cadence is not an exact multiple of the monitor's
                // period. The first moved frame can arrive just short of it.
                // Publish a conservative initial speed now rather than leave
                // the incoming edge with zero lead for another whole frame.
                // Keep latest unchanged so the normal merged sample still
                // accounts for all movement once a full period has elapsed.
                guard beginsMotion else { return nil }
                return ((offset - latest.offset) / refreshInterval, refreshInterval, 0)
            }
            let delta = offset - latest.offset
            let velocity: Double
            let interval: Double
            let acceleration: Double
            if let preceding, delta * (latest.offset - preceding.offset) > 0 {
                let previousInterval = latest.time - preceding.time
                let recent = delta / elapsed
                let previous = (latest.offset - preceding.offset) / previousInterval
                let change = (recent - previous) / ((elapsed + previousInterval) / 2)
                // Use acceleration only while speed is increasing. Braking is
                // allowed to shorten the next observation, never reverse the
                // predicted direction before the native position reverses.
                acceleration = change * recent > 0 ? change : 0
                velocity = recent + acceleration * elapsed / 2
                interval = max(elapsed, previousInterval)
            } else {
                velocity = delta / elapsed
                interval = elapsed
                acceleration = 0
            }
            self.preceding = latest
            self.latest = (offset, time)
            return (velocity, interval, acceleration)
        }
    }

    static func distance(velocity: Double, interval: Double, readiness: Double,
                         neighbour: Double, observationLead: Double = 0, acceleration: Double = 0) -> Double {
        guard velocity != 0 else { return 0 }
        let lead = velocity < 0 ? -observationLead : observationLead
        let time = interval + readiness
        let increasing = max(0, velocity < 0 ? -acceleration : acceleration)
        // Re-observe acceleration next frame. Extrapolating a short speed-up
        // quadratically across an expensive row's entire preparation latency
        // would request pages of speculative content and amplify the stall.
        let travel = abs(velocity) * time + increasing * interval * interval / 2 + max(0, lead)
        let extra = max(0, travel - max(0, neighbour))
        return velocity < 0 ? -extra : extra
    }
}
