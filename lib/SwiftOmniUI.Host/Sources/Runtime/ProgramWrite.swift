// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore

/// The one mark that the program, not the user, is writing a native control.
/// Design: docs/design/host/patches.md#program-write
@_spi(Host) @MainActor public enum ProgramWrite {
    private static var depth = 0
    private static var completions: [() -> Void] = []

    /// Native hosts can coalesce invalidations across a patch or display frame.
    /// Cache invalidation still happens synchronously; only native requests wait.
    public static func afterWrites(_ work: @escaping () -> Void) {
        guard isWriting else { work(); return }
        completions.append(work)
    }

    /// Whether the host is writing a native control right now.
    public static var isWriting: Bool { depth > 0 }

    /// Runs `body` as the program's write: a native callback raised inside reports nothing.
    public static func perform<Result>(_ body: () throws -> Result) rethrows -> Result {
        depth += 1
        defer {
            depth -= 1
            if depth == 0 {
                let ready = completions
                completions.removeAll(keepingCapacity: true)
                for work in ready { work() }
            }
        }
        return try body()
    }
}
