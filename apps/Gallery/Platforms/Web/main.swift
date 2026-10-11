// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import GalleryUI
import SwiftOmniUIWeb

// Register the application module and show it in the page; the browser calls it
// from then on.
swiftomniui_app_register()
SwiftOmniUIWeb.run(name: "Gallery")
