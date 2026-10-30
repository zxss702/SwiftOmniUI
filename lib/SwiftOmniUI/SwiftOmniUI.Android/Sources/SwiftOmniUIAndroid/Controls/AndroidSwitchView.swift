// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIAndroid

/// A Switch: an `android.widget.Switch`.
@MainActor
final class AndroidSwitchView: AndroidToggleView {
    init() {
        super.init { _ in Java.new(JavaAPI.switchView, JavaAPI.newSwitch, .object(AndroidRenderer.context)) }
    }
}
