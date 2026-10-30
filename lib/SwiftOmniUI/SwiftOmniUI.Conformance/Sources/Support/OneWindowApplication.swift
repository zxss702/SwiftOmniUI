// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore

/// The smallest complete application around one page: one scene, one window.
public struct OneWindowApplication: App {
    /// The page, built again each time the window is.
    public let page: @Sendable @MainActor () -> any Page

    /// An application of one empty window.
    public init() {
        self.page = { EmptyView() }
    }

    /// An application showing `page` in its one window.
    public init(page: @escaping @Sendable @MainActor () -> any Page) {
        self.page = page
    }

    public var body: some Scene { OneWindow(content: page) }
}
