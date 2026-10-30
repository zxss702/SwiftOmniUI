// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// `OpenURLAction(handler:)` - SwiftUI's spelling, where the handler answers
// whether it dealt with the URL or the system should after all. The core
// action only knows a URL as text, so `URL` and the `Result` round-trip
// live here with Foundation.

import Foundation
import SwiftOmniUICore

extension OpenURLAction {
    /// What the handler answers for a URL - SwiftUI's `OpenURLAction.Result`.
    public enum Result: Sendable {
        /// The handler dealt with the URL; nothing else opens it.
        case handled

        /// The handler declines the URL; nothing opens it.
        case discarded

        /// The system opens the URL after all.
        case systemAction

        /// The system opens a different URL in its place - what
        /// `systemAction(_ url:)` spells at a call site.
        case systemActionRedirect(URL)

        /// `.systemAction(otherURL)` - the system opens `url` in place of the
        /// one tapped. A function rather than an overloaded case: Swift enums
        /// cannot carry two cases of one name.
        public static func systemAction(_ url: URL) -> Result {
            .systemActionRedirect(url)
        }
    }

    /// An action that asks `handler` what to do with each URL - SwiftUI's
    /// `OpenURLAction(handler:)`:
    ///
    ///     .environment(\.openURL, OpenURLAction { url in
    ///         url.isFileURL ? .discarded : .systemAction
    ///     })
    ///
    /// `.systemAction` defers to the same platform opener the default
    /// action uses.
    public init(handler: @escaping @Sendable (URL) -> Result) {
        self.init({ (text: String) in
            guard let url = URL(string: text) else { return }
            switch handler(url) {
            case .handled, .discarded:
                break
            case .systemAction:
                Task { try? await Links.launch(text) }
            case .systemActionRedirect(let other):
                Task { try? await Links.launch(other.absoluteString) }
            }
        })
    }
}
