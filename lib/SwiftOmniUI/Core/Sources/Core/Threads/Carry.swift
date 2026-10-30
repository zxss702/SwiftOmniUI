// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// A `Sendable` box for `assumeIsolated`'s result: the callers stand on the
// UI thread already, so the box crosses the signature, never a thread.
struct Carry<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

// Runs `body` on the UI thread: its callers - result builders and scene
// plumbing - always stand there already (docs/design/core/concurrency.md).
@discardableResult
func onMain<Value>(_ body: @MainActor () -> Value) -> Value {
    return MainActor.assumeIsolated { Carry(body()) }.value
}
