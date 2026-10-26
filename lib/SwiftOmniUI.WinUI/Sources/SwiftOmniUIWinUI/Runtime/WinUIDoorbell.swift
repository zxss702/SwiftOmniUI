// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI
import WinSDK

/// The doorbell: a thread parked until the core has work, posting a turn to the UI thread's queue.
/// Design: docs/design/platforms/winui/runtime.md#the-doorbell
enum WinUIDoorbell {
    /// Whether the thread runs.
    @MainActor private static var installed = false

    /// Starts the thread, once; each turn it posts reaches the host through the relay's `turn`.
    @MainActor static func install() {
        guard !installed else { return }
        installed = true
        startThread()
    }

    /// Started from a nonisolated function: a closure written in a `@MainActor` one is MainActor's.
    /// Design: docs/design/platforms/winui/runtime.md#the-doorbell
    private nonisolated static func startThread() {
        let thread = CreateThread(nil, 0, { _ in
            CoreLink().ringForever { swiftomniui_winui_post_turn() }
        }, nil, 0, nil)
        if let thread { CloseHandle(thread) }
    }

    /// A turn the relay posted: the work a layout pass left, then the turn.
    @MainActor static func turn() {
        commitPending()
        WinUIRenderer.shared?.runtime.pump.turn()
    }

    /// Also drained by CompositionTarget.Rendering: realization and measurement
    /// must not wait for the ordinary dispatcher turn while input keeps arriving.
    @MainActor static func commitPending() {
        guard WinUIView.arranging == 0, WinUIView.measuring == 0 else { return }
        let works = pending
        pending = []
        for work in works { work() }
    }
}

extension WinUIDoorbell {
    /// Runs `work` in the next turn posted, once the layout pass under way is over: what a pass decides - a split
    /// view's first room - is said once WinUI has finished laying out.
    @MainActor static var workObserver: ((String, Double) -> Void)?

    @MainActor static func afterPass(_ work: @escaping @MainActor () -> Void, caller: StaticString = #function) {
        let needsTurn = pending.isEmpty
        if workObserver != nil {
            pending.append {
                let start = WinUIFrameClock.monotonic()
                work()
                workObserver?(String(describing: caller), WinUIFrameClock.monotonic() - start)
            }
        } else {
            pending.append(work)
        }
        if needsTurn { swiftomniui_winui_post_turn() }
        WinUIRenderer.shared?.runtime.displayCycle.hold()
    }

    @MainActor static var hasPendingWork: Bool { !pending.isEmpty }

    /// Work waiting for the pass under way to end.
    @MainActor private static var pending: [@MainActor () -> Void] = []
}
