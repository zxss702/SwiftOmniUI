// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import GalleryUI
import SwiftOmniUIGTK
import SwiftOmniUIWebViewGTK

// Register the gallery module, then hand GTK this thread until the last window
// closes. The web view's backend, over WebKitGTK, is registered first.
swiftomniui_app_register()
SwiftOmniUIWebViewGTK.register()
SwiftOmniUIGTK.run(applicationID: "com.swiftomniui.gallery")
