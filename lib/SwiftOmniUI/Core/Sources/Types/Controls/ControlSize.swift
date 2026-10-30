// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// A closed vocabulary, numbered by SwiftOmniUI: append a case, never insert one.
// Design: docs/design/types/vocabularies.md#written-out-and-appended

/// How big a control draws - the SwiftUI spelling, the same cases it names.
///
///     Button("Install") { install() }
///         .controlSize(.large)
///
/// Set on a control it sizes that control; set on a container it sizes every
/// control inside - the way `.controlSize` is inherited in SwiftUI.
public enum ControlSize: Int32, Sendable {
    /// The smallest size the platform draws - a mini control.
    case mini = 0

    /// Small - a compact control beside ordinary ones.
    case small = 1

    /// The ordinary size, where the modifier is never written.
    case regular = 2

    /// Large - a prominent control.
    case large = 3

    /// The largest size the platform draws.
    case extraLarge = 4
}

extension ControlSize: HostRepresentable {}
extension ControlSize: StateChoice {}
