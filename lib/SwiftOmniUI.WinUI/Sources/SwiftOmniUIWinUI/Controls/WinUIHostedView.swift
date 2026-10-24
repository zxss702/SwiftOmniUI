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

    override var registeredPropertiesAffectSize: Bool { control.contentAffectsSize }

    init(_ control: Control) {
        self.control = control
        super.init { _ in swiftomniui_winui_retain(control.element) }
    }

    override func measure(width: Double?, height: Double?) -> LayoutSize {
        if !control.sizesToContentHeight, height?.isFinite != true {
            // A scrolling control has no intrinsic document height. Answer
            // the layout's size query without measuring its native viewport
            // at zero: doing so alternates the scroller's constraint with
            // its real allocation and can cycle its scrollbar layout.
            // prepareMeasure still measures the actual allocation before
            // the parent's normal Arrange, including the very first frame.
            return LayoutSize(width: width.flatMap { $0.isFinite ? max(0, $0) : nil } ?? 0, height: 0)
        }
        return super.measure(width: width, height: height)
    }
}
