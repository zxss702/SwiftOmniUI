// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

extension WinUIRegistrations {
    /// A Button: its caption and its look, whether it takes a press, and the click.
    static func buttons(_ registry: Registry<WinUIView>) {
        // A Menu living in the view: the `Menu` view makes the element and a press on the button opens its entries.
        registry.add(MenuButtonContract.self, create: { _ in WinUIMenuButtonView() }) { menu in
            menu.property(VisualElementContract.isEnabled) { view, enabled in
                view.setEnabled(enabled ?? true)
            }
            menu.applies([MenuButtonContract.menuStyle, MenuButtonContract.buttonStyle]) { view, values in
                let style = values[MenuButtonContract.buttonStyle] ?? .automatic
                view.setBorderless(style == .plain || style == .borderless
                    || (style == .automatic && values[MenuButtonContract.menuStyle] == "borderlessButton"))
            }
            menu.property(MenuButtonContract.menuIndicator) { view, indicator in
                view.setIndicator((indicator ?? .automatic) != .hidden)
            }
            menu.raises(MenuButtonContract.contentRequested)
        }

        registry.add(ButtonContract.self, create: { reports in
            let button = WinUIButtonView()
            button.onClicked = { reports.raise(ButtonContract.clicked) }
            button.onToggled = { on in
                reports.report(ButtonContract.isOn, on, as: ButtonContract.toggled)
            }
            button.onPressed = { reports.raise(ButtonContract.pressed) }
            button.onReleased = { reports.raise(ButtonContract.released) }
            return button
        }, members: { button in
            button.applies(TextMembers.members) { view, values in applyText(view, values) }
            button.applies([
                VisualElementContract.background,
                BorderElementContract.shape, BorderElementContract.stroke, BorderElementContract.strokeWidth,
            ]) { view, values in
                view.setLook(
                    background: values[VisualElementContract.background]?.propValue,
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
                view.setIcon(icon)
            }
            button.raises(ButtonContract.clicked)
            button.raises(ButtonContract.pressed)
            button.raises(ButtonContract.released)
            button.raises(ButtonContract.toggled)
        })
    }
}
