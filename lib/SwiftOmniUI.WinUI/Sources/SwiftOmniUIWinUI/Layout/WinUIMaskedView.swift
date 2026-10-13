// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// A live XAML source and alpha source composited by Windows, including every
/// descendant's drawing, opacity and transform. The original controls stay
/// attached for layout and input; the native alpha host suppresses mask input.
/// Design: docs/design/platforms/winui/drawing.md#a-mask
@MainActor
final class WinUIMaskedView: WinUIZStackView {
    private var maskView: WinUIView?

    override init() {
        super.init { number in swiftomniui_winui_masked_panel_make(number) }
    }

    isolated deinit { swiftomniui_winui_masked_panel_clear(handle) }

    @discardableResult
    override func setItems(_ items: [WinUILayoutItem]) -> Bool {
        let current = items.filter { !$0.departing }
        maskView = current.count > 1 ? current.last?.view : nil
        return super.setItems(items)
    }

    override func holdNativeChildren(_ handles: [SwiftOmniUIObjectRef?]) {
        swiftomniui_winui_masked_panel_set_children(handle, handles, Int32(handles.count), maskView?.handle)
    }

    /// A mask uses the source's allocation; its own intrinsic size must not
    /// enlarge the content that it is masking.
    override func contentSize(width: Double?) -> LayoutSize {
        ZStackArithmetic.size(of: Array(items.filter { !$0.departing }.prefix(1)),
                              padding: padding, width: width)
    }

    override func detach() {
        super.detach()
        swiftomniui_winui_masked_panel_clear(handle)
        maskView = nil
    }
}
