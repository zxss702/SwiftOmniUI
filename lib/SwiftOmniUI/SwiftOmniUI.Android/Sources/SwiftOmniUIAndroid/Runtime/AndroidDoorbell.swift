// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import Android
import CSwiftOmniUIAndroid

/// The doorbell posts core work to the main looper through an eventfd.
/// Design: docs/design/platforms/android/runtime.md#the-doorbell
enum AndroidDoorbell {
    /// The eventfd any posting thread writes and the main looper watches.
    nonisolated(unsafe) private static var bell: Int32 = -1

    /// What the main looper runs when the bell rings.
    @MainActor private static var ring: () -> Void = {}

    /// Watches the bell from the main looper and registers its thread-safe post.
    @MainActor static func install(ring: @escaping () -> Void) {
        guard bell < 0 else { return }

        self.ring = ring
        bell = eventfd(0, Int32(EFD_CLOEXEC) | Int32(EFD_NONBLOCK))

        guard let looper = ALooper_forThread() else {
            AndroidRenderer.log.error("the doorbell found no looper on the main thread")
            return
        }

        ALooper_acquire(looper)
        ALooper_addFd(looper, bell, Int32(ALOOPER_POLL_CALLBACK), Int32(ALOOPER_EVENT_INPUT), { descriptor, _, _ in
            var count: UInt64 = 0
            _ = read(descriptor, &count, 8)
            MainActor.assumeIsolated { Java.frame { AndroidDoorbell.ring() } }
            return 1
        }, nil)

        CoreLink().postTurns(with: { [descriptor = bell] in
            var one: UInt64 = 1
            _ = write(descriptor, &one, 8)
        })
    }
}
