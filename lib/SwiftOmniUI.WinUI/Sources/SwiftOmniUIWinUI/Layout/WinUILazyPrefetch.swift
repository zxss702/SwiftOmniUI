// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// Distances are DIPs, time is milliseconds. The next observed frame can move
/// while requested rows are being built and arranged. The compositor's viewport
/// observation can lag its latest offset. Existing neighbours
/// already cover part of that distance; only the remainder needs prefetch.
enum WinUILazyPrefetch {
    static func velocity(distance: Double, elapsed: Double, refreshInterval: Double) -> Double {
        let interval = max(elapsed, refreshInterval)
        return interval > 0 ? distance / interval : 0
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
