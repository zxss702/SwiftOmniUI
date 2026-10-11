// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import GalleryUI
import SwiftOmniUIWebViewWinUI
import SwiftOmniUIWinUI

// Register the application module, then hand WinUI this thread until the last
// window closes. The web view's backend, over WebView2, is registered first.
swiftomniui_app_register()
SwiftOmniUIWebViewWinUI.register()
SwiftOmniUIWinUI.run()
