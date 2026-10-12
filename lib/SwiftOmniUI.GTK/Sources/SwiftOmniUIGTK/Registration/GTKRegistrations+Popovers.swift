// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

extension GTKRegistrations {
    /// A popover: a `GtkPopover` on the widget of the view it hangs off - `GTKElement` names that view - opened and
    /// closed as the state says, and the user's dismissal heard.
    static func popovers(_ registry: Registry<GTKView>) {
        registry.add(PopoverContract.self, create: { reports in
            let popover = GTKPopoverView()
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
