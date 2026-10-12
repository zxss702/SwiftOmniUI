// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// A `.mask` realized: the mask held like any child - laid out in the same room the content stands in - and never
/// drawn; what the panel shows is cut to the mask's own silhouette.
/// Design: docs/design/platforms/winui/drawing.md#a-mask
@MainActor
final class WinUIMaskedView: WinUIZStackView {
    /// The mask's own view: the child the `.mask` modifier writes after the content.
    private var maskView: WinUIView?

    /// The mask is held and laid out, and never drawn; a click passes through it to the content under it.
    @discardableResult
    override func setItems(_ items: [WinUILayoutItem]) -> Bool {
        maskView = items.count > 1 ? items.last?.view : nil
        let changed = super.setItems(items)
        maskView?.setOpacity(0)
        maskView?.setIgnoresInput(true)
        return changed
    }

    /// Cuts the panel to the mask's silhouette once the pass has laid the mask out and drawn its geometry for the
    /// room: the mask's own corner of the panel is where its silhouette stands.
    override func arrange(in bounds: Rect) {
        super.arrange(in: bounds)
        let corner = maskView?.placed ?? Rect(x: 0, y: 0, width: 0, height: 0)
        swiftomniui_winui_clip_to_shape(handle, maskView?.handle, corner.x, corner.y)
    }
}
