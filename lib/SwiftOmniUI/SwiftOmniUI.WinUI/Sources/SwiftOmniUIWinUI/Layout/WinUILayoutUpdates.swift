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
    private static var logicalWalks: Set<Int64> = []
    private static var nativeWalks: Set<Int64> = []

    /// Invalidation has already reached the ancestors of this branch in the
    /// current write batch. Keep logical and native ownership walks separate:
    /// a scroll document or native content owner may belong to only one path.
    static func visitLogicalAncestors(_ element: WinUIElement) -> Bool {
        // View numbers are never reused. Object addresses can be reused when
        // a lazy batch removes one row and creates another. Viewless elements
        // simply walk through to the next native ancestor.
        guard ProgramWrite.isWriting, let view = element.view else { return true }
        schedule()
        return logicalWalks.insert(view.number).inserted
    }

    static func visitNativeAncestors(_ view: WinUIView) -> Bool {
        guard ProgramWrite.isWriting else { return true }
        schedule()
        return nativeWalks.insert(view.number).inserted
    }

    /// A read can repopulate an ancestor without descending into a dirty child
    /// (for example a fixed-size layout). Rearm all propagation paths, not only
    /// the path of the view being read. A reparent also changes those paths.
    static func rearmAncestorWalks() {
        if !logicalWalks.isEmpty { logicalWalks.removeAll(keepingCapacity: true) }
        if !nativeWalks.isEmpty { nativeWalks.removeAll(keepingCapacity: true) }
    }

    static func invalidate(_ view: WinUIView) -> Bool {
        guard ProgramWrite.isWriting else { return true }
        schedule()
        return invalidated.insert(view.number).inserted
    }

    /// Arithmetic has observed the preceding writes. A later write in this
    /// batch must invalidate the answer again, even when no XAML Measure ran.
    /// This does not consume or submit a pending native layout request.
    static func readLayoutCache(_ view: WinUIView) {
        rearmAncestorWalks()
        invalidated.remove(view.number)
    }

    static func measured(_ view: WinUIView) {
        readLayoutCache(view)
        // A native Measure inside a patch must see preceding writes immediately.
        if pending[view.number]?.measure == true {
            pending[view.number]?.measure = false
            view.requestNativeMeasure()
        }
    }

    static func beganNativeMeasure(_ view: WinUIView) {
        readLayoutCache(view)
        pending[view.number]?.measure = false
        view.beganNativeMeasure()
    }

    static func beganNativeArrange(_ view: WinUIView) {
        pending[view.number]?.arrange = false
    }

    static func enqueue(_ view: WinUIView, measure: Bool) -> Bool {
        // A fresh SOUI panel is already dirty in XAML. Initial properties and
        // child attachment still invalidate Swift's arithmetic synchronously,
        // but must not allocate one redundant native request per new node.
        if measure && !view.requiresNativeMeasureInvalidation { return true }
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
            rearmAncestorWalks()
            scheduled = false
            for entry in ready.values {
                guard let view = entry.view, !view.isDetached else { continue }
                if entry.measure { view.requestNativeMeasure() }
                if entry.arrange { (view as? WinUILayoutView)?.invalidateArrange() }
            }
        }
    }
}
