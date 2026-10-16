// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// A popover: the card WinUI's `Flyout` shows beside the view it hangs off, holding the popover's content in this
/// layout - which no parent's layout places: the card is its room.
@MainActor
final class WinUIPopoverView: WinUISingleChildView {
    /// The flyout showing the card, made the first time it opens.
    private var flyout: SwiftOmniUIObjectRef?

    /// The view the card stands beside, read each time it opens.
    var anchor: () -> WinUIView? = { nil }

    /// The edge of the anchor the card prefers.
    var edge = Edge.top

    /// The user took the card away: a click beside it, Escape.
    var onDismissed: (() -> Void)?

    /// Whether the card is to show, as the element last said.
    private(set) var isOpen = false

    isolated deinit {
        if let flyout { swiftomniui_winui_release(flyout) }
    }

    /// Opens the card beside its anchor or takes it away; written only where it differs.
    func setOpen(_ open: Bool) {
        guard open != isOpen else { return }
        isOpen = open
        if open { show() } else if let flyout { swiftomniui_winui_popover_hide(flyout) }
    }

    private func show() {
        guard let anchor = anchor(), let flyout = flyout ?? swiftomniui_winui_popover_make(number, presentationHandle) else { return }
        self.flyout = flyout
        swiftomniui_winui_popover_show(flyout, anchor.handle, Int32(edge.rawValue))
    }

    /// Takes the card away as the user does, so it is heard as their dismissal - what a test does.
    func dismissAsUser() {
        if let flyout { swiftomniui_winui_popover_hide(flyout) }
    }

    /// Whether WinUI shows the card - what a test reads.
    var showsCard: Bool {
        flyout.map { swiftomniui_winui_popover_is_open($0) } ?? false
    }

    /// The flyout closed: of the user's accord while the element still says open, which the element hears; the
    /// host's own closing says nothing.
    override func presented(_ open: Bool) {
        super.presented(open)
        guard !open, isOpen else { return }
        isOpen = false
        onDismissed?()
    }

    /// The card's size is the content's own, as a popover's is - no width offered to stretch it across the window -
    /// within the room the window leaves it.
    override func measure(width: Double, height: Double) -> LayoutSize {
        let size = super.measure(width: .infinity, height: .infinity)
        return LayoutSize(width: min(size.width, width), height: min(size.height, height))
    }

    override func detach() {
        super.detach()
        onDismissed = nil
        anchor = { nil }
        if isOpen, let flyout {
            isOpen = false
            swiftomniui_winui_popover_hide(flyout)
        }
    }
}
