// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// A closed vocabulary, numbered by SwiftOmniUI: append a case, never insert one.
// Design: docs/design/types/vocabularies.md#written-out-and-appended

/// When the scroll bars are drawn - what `.scrollIndicators` takes.
public enum ScrollIndicatorVisibility: Int32, Sendable {
    /// As the platform sees fit.
    case automatic = 0

    /// Always shown.
    case visible = 1

    /// Never shown, though it still scrolls.
    case hidden = 2
}

extension ScrollIndicatorVisibility: HostRepresentable {}
extension ScrollIndicatorVisibility: StateChoice {}
