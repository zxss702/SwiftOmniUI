// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// A closed vocabulary, numbered by SwiftOmniUI: append a case, never insert one.
// Design: docs/design/types/vocabularies.md#written-out-and-appended

/// Whether a scroll view springs back past its content's end.
public enum ScrollBounceBehavior: Int32, Sendable {
    /// As the platform sees fit - bounces where bouncing is the platform's way.
    case automatic = 0

    /// Always, whether the content fills the view or not.
    case always = 1

    /// Only where the content is big enough to move.
    case basedOnSize = 2
}

extension ScrollBounceBehavior: HostRepresentable {}
extension ScrollBounceBehavior: StateChoice {}
