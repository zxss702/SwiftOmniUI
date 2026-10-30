// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore

/// The window of a `OneWindowApplication`, its page built again each time the window is.
public struct OneWindow: WindowScene {
    /// The page the window shows.
    public let content: @Sendable @MainActor () -> any Page

    /// A window showing `content`.
    public init(content: @escaping @Sendable @MainActor () -> any Page) {
        self.content = content
    }

    public var page: any Page { content() }
}
