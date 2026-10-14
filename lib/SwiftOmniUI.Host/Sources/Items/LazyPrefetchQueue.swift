// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// Optional lazy row work, after the frame's visible render. Work stays on the
/// UI thread; a source, viewport or direction change replaces its owner's job.
@_spi(Host) @MainActor public final class LazyPrefetchQueue {
    private struct Job {
        weak var owner: AnyObject?
        let serial: UInt64
        let step: () -> Bool
    }
    private var jobs: [ObjectIdentifier: Job] = [:]
    private var serial: UInt64 = 0
    var onPending: (() -> Void)?
    var now: () -> ContinuousClock.Instant = { .now }

    public init() {}

    public var isPending: Bool { jobs.values.contains { $0.owner != nil } }

    /// `step` performs at most one bounded run and returns whether more remains.
    /// It must capture its owner weakly.
    public func schedule(owner: AnyObject, step: @escaping () -> Bool) {
        serial &+= 1
        jobs[ObjectIdentifier(owner)] = Job(owner: owner, serial: serial, step: step)
        onPending?()
    }

    public func cancel(owner: AnyObject) { jobs[ObjectIdentifier(owner)] = nil }

    /// A job gets one turn per frame. Builders cannot be preempted, so check
    /// the deadline before each turn and never drain an idle loop to exhaustion.
    public func drain(until deadline: ContinuousClock.Instant) {
        let pending = jobs.sorted { $0.value.serial < $1.value.serial }
        for (id, job) in pending {
            guard now() < deadline else { break }
            guard jobs[id]?.serial == job.serial else { continue }
            guard job.owner != nil else { jobs[id] = nil; continue }
            let more = job.step()
            // A synchronous render can replace or cancel this very job.
            if jobs[id]?.serial == job.serial {
                if more {
                    serial &+= 1
                    jobs[id] = Job(owner: job.owner, serial: serial, step: job.step)
                } else { jobs[id] = nil }
            }
        }
    }
}
