// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// Optional lazy row work, after the frame's visible render. Work stays on the
/// UI thread; a source, viewport or direction change replaces its owner's job.
@_spi(Host) @MainActor public final class LazyPrefetchQueue {
    private struct Job {
        weak var owner: AnyObject?
        let serial: UInt64
        let ready: (() -> Bool)?
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
    public func schedule(owner: AnyObject, ready: (() -> Bool)? = nil, step: @escaping () -> Bool) {
        serial &+= 1
        jobs[ObjectIdentifier(owner)] = Job(owner: owner, serial: serial, ready: ready, step: step)
        onPending?()
    }

    public func cancel(owner: AnyObject) { jobs[ObjectIdentifier(owner)] = nil }

    /// Ready jobs may take another bounded step in this frame. A host still
    /// waiting for native layout yields until a later frame; it never busy-waits.
    /// Jobs without a readiness signal retain their one-step-per-frame contract.
    public func drain(until deadline: ContinuousClock.Instant, commit: (() -> Void)? = nil) {
        var pending = jobs.sorted { $0.value.serial < $1.value.serial }
        var index = 0
        while index < pending.count {
            guard now() < deadline else { break }
            let (id, job) = pending[index]
            index += 1
            guard jobs[id]?.serial == job.serial else { continue }
            guard job.owner != nil else { jobs[id] = nil; continue }
            guard job.ready?() != false else { continue }
            let more = job.step()
            // Include realization in this unit's budget before checking readiness again.
            commit?()
            // A synchronous render can replace or cancel this very job.
            if jobs[id]?.serial == job.serial {
                if more {
                    serial &+= 1
                    let next = Job(owner: job.owner, serial: serial, ready: job.ready, step: job.step)
                    jobs[id] = next
                    if job.ready != nil { pending.append((id, next)) }
                } else { jobs[id] = nil }
            }
        }
    }
}
