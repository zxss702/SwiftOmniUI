// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// A ProgressBar: WinUI's `ProgressBar`, how far along from 0 to 1.
@MainActor
final class WinUIProgressBarView: WinUIView {
    override var takesDirection: Bool { true }

    init() {
        super.init { _ in swiftomniui_winui_progress_bar_make() }
    }

    /// How far along, from 0 to 1: a share past either end standing at that end.
    func setProgress(_ progress: Double) {
        swiftomniui_winui_progress_bar_set(handle, ValueArithmetic.share(progress))
    }

    /// How far along WinUI shows it.
    var progress: Double { swiftomniui_winui_progress_bar_value(handle) }
}
