// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// `.keyboardShortcut`: a key that clicks the control from anywhere in its window.

extension View {
    /// A keyboard shortcut that activates the control from anywhere in the
    /// window it is in.
    ///
    ///     Button("Save", action: save)
    ///         .keyboardShortcut("s")
    ///
    /// Modifiers default to the platform's command key; say them for anything
    /// else:
    ///
    ///     .keyboardShortcut("s", modifiers: [.command, .shift])
    ///     .keyboardShortcut(.return)
    ///
    /// The host binds the shortcut as its own controls do - an accelerator on
    /// Windows, a key equivalent on macOS - so the platform's own affordances,
    /// like showing it in menus, come with it.
    public func keyboardShortcut(
        _ key: KeyEquivalent, modifiers: EventModifiers = .command
    ) -> ModifiedContent {
        setting(ButtonContract.shortcut, KeyboardShortcut(key, modifiers: modifiers))
    }

    /// A keyboard shortcut from a state, `$s`: the host rebinds as it moves.
    public func keyboardShortcut(_ shortcut: Binding<KeyboardShortcut>) -> ModifiedContent {
        revised { $0.drivePlain(ButtonContract.shortcut, by: shortcut) }
    }
}
