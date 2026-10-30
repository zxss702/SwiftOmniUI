// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
import CSwiftOmniUIWinUI

/// A TextField: a WinUI `TextBox` on one line, whose Enter submits.
@MainActor
final class WinUITextFieldView: WinUIInputView {
    init() {
        super.init { number in swiftomniui_winui_field_make(number) }
    }

    /// The logical style, mapped to the box's own chrome.
    func setStyle(_ style: TextFieldStyleKind?) {
        swiftomniui_winui_field_set_style(handle, (style ?? .automatic).rawValue)
    }
}
