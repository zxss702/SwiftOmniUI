// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// `navigationDocument(_:)` taking a `URL` - SwiftUI's spelling, where the
// core modifier only knows a document path as text.

import Foundation
import SwiftOmniUICore

extension View {
    /// The document the page stands for, as a file `URL` - SwiftUI's
    /// `.navigationDocument(url)`. Its path is what crosses to the host.
    ///
    ///     EditorView()
    ///         .navigationDocument(documentURL)
    public func navigationDocument(_ url: URL) -> ModifiedContent {
        navigationDocument(url.path)
    }
}
