// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// A native rectangle whose fill follows WinUI's separator theme resource.
/// The host's divider axis supplies its thickness and expanding dimension.
@MainActor
final class WinUIDividerView: WinUIView {
    init() {
        super.init { _ in swiftomniui_winui_divider_make() }
    }

    /// The separator takes its allocated room without adding an intrinsic size to the containing stack.
    override func measure(width: Double?, height: Double?) -> LayoutSize {
        _ = super.measure(width: 0, height: 0)
        return LayoutSize(width: 0, height: 0)
    }
}
