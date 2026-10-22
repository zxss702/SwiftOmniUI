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

    public init() {}

    public var isPending: Bool { jobs.values.contains { $0.owner != nil } }

    /// `step` performs one bounded unit and returns whether more remains.
    /// It must capture its owner weakly.
    public func schedule(owner: AnyObject, ready: (() -> Bool)? = nil, step: @escaping () -> Bool) {
        serial &+= 1
        jobs[ObjectIdentifier(owner)] = Job(owner: owner, serial: serial, ready: ready, step: step)
        onPending?()
    }

    public func cancel(owner: AnyObject) { jobs[ObjectIdentifier(owner)] = nil }

    /// Take one unit per ready owner, then return to native input and layout.
    /// A ready signal permits work; it must never turn this drain into a loop
    /// that materializes a whole predicted window in one UI frame.
    public func drain(commit: (() -> Void)? = nil) {
        let pending = jobs.sorted { $0.value.serial < $1.value.serial }
        var index = 0
        while index < pending.count {
            let (id, job) = pending[index]
            index += 1
            guard jobs[id]?.serial == job.serial else { continue }
            guard job.owner != nil else { jobs[id] = nil; continue }
            guard job.ready?() != false else { continue }
            let more = job.step()
            // Commit this unit before checking native readiness again.
            commit?()
            // A synchronous render can replace or cancel this very job.
            if jobs[id]?.serial == job.serial {
                if more {
                    serial &+= 1
                    let next = Job(owner: job.owner, serial: serial, ready: job.ready, step: job.step)
                    jobs[id] = next
                } else { jobs[id] = nil }
            }
        }
    }
}
