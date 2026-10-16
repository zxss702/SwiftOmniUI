// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// A control that is on or off - a WinUI `ToggleSwitch`, `CheckBox` or `RadioButton` - whose turn reaches Swift
/// through the relay.
/// Design: docs/design/platforms/winui/controls.md#on-or-off
@MainActor
class WinUIToggleView: WinUIView {
    override var takesDirection: Bool { true }

    /// What the control does when the user turns it.
    var onToggled: ((Bool) -> Void)?

    override func toggled(_ on: Bool) {
        onToggled?(on)
    }

    /// Whether the control stands on.
    var isOn: Bool { swiftomniui_winui_toggle_is_on(handle) }

    /// Turns the control on or off.
    func setOn(_ on: Bool) {
        swiftomniui_winui_toggle_set_on(handle, on)
    }

    /// What the control is drawn over; nil for WinUI's own.
    func setBackground(_ value: HostValue?) {
        let brush = WinUIBrush(value)
        paint("background", followsSize: brush.followsSize) { [handle] size in
            brush.withRelayBrush(over: size) { swiftomniui_winui_toggle_set_background(handle, $0) }
        }
    }

    override func detach() {
        super.detach()
        onToggled = nil
    }
}
