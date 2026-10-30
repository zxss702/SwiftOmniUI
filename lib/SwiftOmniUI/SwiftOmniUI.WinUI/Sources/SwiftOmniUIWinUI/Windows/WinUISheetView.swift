// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI

/// A sheet: a page the window's modal stack presents. Design: docs/design/platforms/winui/pages.md#the-modal-stack
@MainActor
final class WinUISheetView: WinUIView {
    init() {
        super.init { _ in swiftomniui_winui_sheet_make() }
    }

    /// Shows `page` under `title`, the card `height` tall - under 0 the window's height minus it, 0 the content's.
    func show(title: String, page: WinUIView?, height: Double = 0) {
        swiftomniui_winui_sheet_set_height(handle, height)
        swiftomniui_winui_sheet_set(handle, title, page?.presentationHandle)
    }
}
