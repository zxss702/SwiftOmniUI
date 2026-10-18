// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// A control of the application's own, standing in the tree as a view of this host that holds a reference of its own
/// to the control's element: placed, sized and shown like any other, the control held while its element lives.
@MainActor
final class WinUIHostedView<Control: WinUIControl>: WinUIView {
    /// The application's control.
    let control: Control

    init(_ control: Control) {
        self.control = control
        super.init { _ in swiftomniui_winui_retain(control.element) }
    }

    override func measure(width: Double?, height: Double?) -> LayoutSize {
        let viewportHeight = height.flatMap { $0.isFinite ? $0 : nil } ?? 0
        return super.measure(width: width, height: control.sizesToContentHeight ? height : viewportHeight)
    }
}
