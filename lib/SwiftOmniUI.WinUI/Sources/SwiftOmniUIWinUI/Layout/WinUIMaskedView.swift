// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// A `.mask` realized: both children stand in one room, the content first and the mask last, and the panel is cut
/// to the silhouette of the first shape standing in the mask - a geometric clip on the panel's own visual. The mask
/// itself is never drawn, and no click of the user's reaches it.
/// Design: docs/design/platforms/winui/drawing.md#a-mask
@MainActor
final class WinUIMaskedView: WinUIZStackView {
    /// The mask's own view: the child the `.mask` modifier writes after the content.
    private var maskView: WinUIView?

    /// The mask is held and laid out like the content it stands over, and never drawn: nothing of it shows, and a
    /// click passes through it to the content under it.
    @discardableResult
    override func setItems(_ items: [WinUILayoutItem]) -> Bool {
        maskView = items.count > 1 ? items.last?.view : nil
        let changed = super.setItems(items)
        maskView?.setOpacity(0)
        maskView?.setIgnoresInput(true)
        return changed
    }

    /// Cuts the panel to the mask's silhouette once this pass has laid the mask out: the room the shape was given
    /// is the shape's own, known only here.
    override func arrange(in bounds: Rect) {
        super.arrange(in: bounds)
        clipToMask()
    }

    /// Cuts the panel to the first shape standing in the mask, told in the panel's own coordinates - the room each
    /// layout gave its child, walked down from the mask - and to the mask's own box where the mask holds no shape
    /// WinUI cuts a silhouette from; a panel with no mask at all shows whole.
    private func clipToMask() {
        guard let maskView else {
            swiftomniui_winui_clip_to_shape(handle, -1, 0, 0, 0, 0, 0)
            return
        }
        let corner = maskView.placedFrame
        guard let shape = firstShape(in: maskView, at: Point(x: corner.x, y: corner.y)) else {
            swiftomniui_winui_clip_to_shape(handle, 0, 0, corner.x, corner.y, corner.width, corner.height)
            return
        }
        let silhouette = shape.view.silhouette
        let room = shape.view.placedFrame
        let inset = silhouette.inset
        swiftomniui_winui_clip_to_shape(
            handle, silhouette.kind, silhouette.radius,
            shape.origin.x + inset, shape.origin.y + inset,
            max(0, room.width - inset * 2), max(0, room.height - inset * 2))
    }

    /// The first shape standing in `view`, and where it stands within the panel, `origin` being where `view`
    /// itself was placed.
    private func firstShape(in view: WinUIView, at origin: Point) -> (view: WinUIPathView, origin: Point)? {
        if let shape = view as? WinUIPathView { return (shape, origin) }
        guard let layout = view as? WinUILayoutView else { return nil }
        for item in layout.items {
            let place = item.view.placedFrame
            let found = firstShape(in: item.view, at: Point(x: origin.x + place.x, y: origin.y + place.y))
            if let found { return found }
        }
        return nil
    }
}
