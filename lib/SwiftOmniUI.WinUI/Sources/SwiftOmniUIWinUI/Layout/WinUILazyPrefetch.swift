// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// Distances are DIPs, time is milliseconds. The next observed frame can move
/// while requested rows are being built and arranged. The compositor's viewport
/// observation can lag its latest offset. Existing neighbours
/// already cover part of that distance; only the remainder needs prefetch.
enum WinUILazyPrefetch {
    /// Rendering can arrive several times inside one display refresh. Keep
    /// those distances together before estimating speed and acceleration;
    /// dispatcher-sized fragments otherwise produce alternating spikes.
    struct MotionSamples {
        private var latest: (offset: Double, time: Double)?
        private var preceding: (offset: Double, time: Double)?

        mutating func observe(offset: Double, time: Double, refreshInterval: Double)
            -> (velocity: Double, interval: Double, acceleration: Double)? {
            guard let latest else {
                latest = (offset, time)
                return nil
            }
            let elapsed = time - latest.time
            guard offset != latest.offset, elapsed > 0, elapsed >= refreshInterval else { return nil }
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
