// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// `.onOpenURL`: a URL the platform handed the application, delivered to the
// nearest listener beneath. SwiftOmniUI's core carries the URL as a string - it
// holds no Foundation - and this bridge says it as a URL.

import Foundation
@_spi(Host) import SwiftOmniUICore

extension View {
    /// Runs `action` with each URL the platform hands the application -
    /// a document opened on it, a link activated into it.
    ///
    ///     ContentView()
    ///         .onOpenURL { url in open(url) }
    ///
    /// The listener on the nearest ancestor answers; one URL reaches the
    /// first listener found walking up from the window's root.
    ///
    /// - Parameter action: what runs with the URL.
    public func onOpenURL(perform action: @escaping (URL) -> Void) -> some View {
        hearing(AppContract.urlOpened) { payload in
            let url = URL(string: payload) ?? URL(fileURLWithPath: payload)
            action(url)
        }
    }
}
