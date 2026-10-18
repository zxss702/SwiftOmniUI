// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUIHost

/// A patch/frame invalidates shared ancestors once, unless a measurement has
/// consumed their caches in the meantime. Native requests wait for the batch.
@MainActor
enum WinUILayoutUpdates {
    private struct Pending {
        weak var view: WinUIView?
        var measure = false
        var arrange = false
    }
    private static var invalidated: Set<Int64> = []
    private static var pending: [Int64: Pending] = [:]
    private static var scheduled = false

    static func invalidate(_ view: WinUIView) -> Bool {
        guard ProgramWrite.isWriting else { return true }
        schedule()
        return invalidated.insert(view.number).inserted
    }

    static func measured(_ view: WinUIView) {
        invalidated.remove(view.number)
        // A native Measure inside a patch must see preceding writes immediately.
        if pending[view.number]?.measure == true {
            pending[view.number]?.measure = false
            view.requestNativeMeasure()
        }
    }

    static func beganNativeMeasure(_ view: WinUIView) {
        invalidated.remove(view.number)
        pending[view.number]?.measure = false
        view.beganNativeMeasure()
    }

    static func beganNativeArrange(_ view: WinUIView) {
        pending[view.number]?.arrange = false
    }

    static func enqueue(_ view: WinUIView, measure: Bool) -> Bool {
        guard ProgramWrite.isWriting else { return false }
        var next = pending[view.number] ?? Pending(view: view)
        if measure { next.measure = true } else { next.arrange = true }
        pending[view.number] = next
        schedule()
        return true
    }

    private static func schedule() {
        guard !scheduled else { return }
        scheduled = true
        ProgramWrite.afterWrites {
            let ready = pending
            pending.removeAll(keepingCapacity: true)
            invalidated.removeAll(keepingCapacity: true)
            scheduled = false
            for entry in ready.values {
                guard let view = entry.view, !view.isDetached else { continue }
                if entry.measure { view.requestNativeMeasure() }
                if entry.arrange { (view as? WinUILayoutView)?.invalidateArrange() }
            }
        }
    }
}
