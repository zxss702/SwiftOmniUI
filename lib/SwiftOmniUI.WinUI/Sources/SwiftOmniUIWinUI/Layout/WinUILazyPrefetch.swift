// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// Distances are DIPs, time is milliseconds. The next observed frame can move
/// while requested rows are being built and arranged. The compositor's viewport
/// observation can lag its latest offset. Existing neighbours
/// already cover part of that distance; only the remainder needs prefetch.
enum WinUILazyPrefetch {
    /// ViewChanged and Rendering can report the same physical frame in several
    /// callbacks. Keep their distance together instead of giving each fragment
    /// a whole refresh period, which underestimates velocity during a fling.
    struct MotionSamples {
        private var latest: (offset: Double, time: Double)?
        private var preceding: (offset: Double, time: Double)?

        mutating func observe(offset: Double, time: Double, refreshInterval: Double)
            -> (velocity: Double, interval: Double)? {
            guard let latest else {
                latest = (offset, time)
                return nil
            }
            let elapsed = time - latest.time
            guard offset != latest.offset, elapsed > 0, elapsed >= refreshInterval else { return nil }
            let delta = offset - latest.offset
            let velocity: Double
            let interval: Double
            if let preceding, delta * (latest.offset - preceding.offset) > 0 {
                velocity = (offset - preceding.offset) / (time - preceding.time)
                interval = max(elapsed, latest.time - preceding.time)
            } else {
                velocity = delta / elapsed
                interval = elapsed
            }
            self.preceding = latest
            self.latest = (offset, time)
            return (velocity, interval)
        }
    }

    static func distance(velocity: Double, interval: Double, readiness: Double,
                         neighbour: Double, observationLead: Double = 0) -> Double {
        guard velocity != 0 else { return 0 }
        let lead = velocity < 0 ? -observationLead : observationLead
        let time = interval + readiness
        let travel = abs(velocity) * time + max(0, lead)
        let extra = max(0, travel - max(0, neighbour))
        return velocity < 0 ? -extra : extra
    }
}
