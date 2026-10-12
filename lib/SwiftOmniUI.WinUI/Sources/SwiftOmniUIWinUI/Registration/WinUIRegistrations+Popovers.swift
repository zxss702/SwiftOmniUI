// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

extension WinUIRegistrations {
    /// A popover: WinUI's `Flyout` beside the view it hangs off - `WinUIElement` names that view - opened and closed
    /// as the state says, and the user's dismissal heard.
    static func popovers(_ registry: Registry<WinUIView>) {
        registry.add(PopoverContract.self, create: { reports in
            let popover = WinUIPopoverView()
            popover.onDismissed = { reports.raise(PopoverContract.dismissed) }
            return popover
        }, members: { popover in
            popover.property(PopoverContract.arrowEdge) { view, edge in
                view.edge = edge ?? .top
            }
            popover.property(PopoverContract.isOpen) { view, open in
                view.setOpen(open ?? false)
            }
            popover.raises(PopoverContract.dismissed)
        })
    }
}
