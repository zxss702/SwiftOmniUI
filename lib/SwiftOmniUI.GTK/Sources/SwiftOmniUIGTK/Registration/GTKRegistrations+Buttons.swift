// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

extension GTKRegistrations {
    /// A Button: its caption and its look, whether it takes a press, and the click.
    static func buttons(_ registry: Registry<GTKView>) {
        // A Menu living in the view: the `Menu` view makes the element and the
        // `GtkMenuButton` opens its entries; the contract's own members are all it takes.
        registry.add(MenuButtonContract.self, create: { _ in GTKMenuButtonView() }) { menu in
            menu.property(VisualElementContract.isEnabled) { view, enabled in
                view.opensMenu = enabled ?? true
            }
            menu.property(MenuButtonContract.menuStyle) { view, style in
                view.borderless = style == "borderlessButton"
            }
            menu.property(MenuButtonContract.menuIndicator) { view, indicator in
                view.showsArrow = (indicator ?? .automatic) != .hidden
            }
        }

        registry.add(ButtonContract.self, create: { reports in
            // A toggle widget at heart: it draws an ordinary button until
            // `isOn` gives it a state to keep.
            let button = GTKButtonView(toggles: true)
            button.onClicked = { reports.raise(ButtonContract.clicked) }
            button.onToggled = { on in
                reports.report(ButtonContract.isOn, on, as: ButtonContract.toggled)
            }
            return button
        }, members: { button in
            button.applies(TextMembers.members) { view, values in applyText(view, values) }
            button.applies([
                VisualElementContract.background,
                BorderElementContract.shape, BorderElementContract.stroke, BorderElementContract.strokeWidth,
            ]) { view, values in
                view.setBox(
                    fill: values[VisualElementContract.background]?.propValue,
                    stroke: values[BorderElementContract.stroke]?.propValue,
                    strokeWidth: values[BorderElementContract.strokeWidth],
                    shape: values[BorderElementContract.shape]?.propValue)
            }
            button.property(VisualElementContract.isEnabled) { view, enabled in
                view.setEnabled(enabled ?? true)
            }
            button.property(ButtonContract.buttonStyle) { view, style in
                view.setStyle(style)
            }
            button.property(ButtonContract.shortcut) { view, shortcut in
                view.setShortcut(shortcut)
            }
            button.property(ButtonContract.isOn) { view, on in
                view.setOn(on)
            }
            button.property(ButtonContract.icon) { view, icon in
                view.setPicture(icon)
            }
            button.raises(ButtonContract.clicked)
            button.raises(ButtonContract.toggled)
        })
    }
}
