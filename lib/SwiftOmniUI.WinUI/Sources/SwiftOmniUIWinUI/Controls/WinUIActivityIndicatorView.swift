// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIWinUI
@_spi(Host) import SwiftOmniUICore

/// An ActivityIndicator: WinUI's `ProgressRing`, turning while its work runs.
@MainActor
final class WinUIActivityIndicatorView: WinUIView {
    private var diameter = 24.0

    init() {
        super.init { _ in swiftomniui_winui_progress_ring_make() }
    }

    /// Size the native ring itself, so a compact frame does not clip a 24-DIP template.
    func setControlSize(_ size: ControlSize?) {
        let diameter: Double
        switch size ?? .regular {
        case .mini: diameter = 12
        case .small: diameter = 16
        case .regular: diameter = 24
        case .large: diameter = 32
        case .extraLarge: diameter = 48
        }
        guard diameter != self.diameter else { return }
        self.diameter = diameter
        swiftomniui_winui_progress_ring_set_size(handle, diameter)
        invalidateMeasure()
    }

    /// Whether it turns.
    func setRunning(_ running: Bool) {
        swiftomniui_winui_progress_ring_set_running(handle, running)
    }

    /// Whether WinUI turns it.
    var isRunning: Bool { swiftomniui_winui_progress_ring_running(handle) }
}
