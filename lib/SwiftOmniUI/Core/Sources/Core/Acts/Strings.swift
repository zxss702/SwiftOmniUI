// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// Lookup keys resolved where a string crosses to the host outside a member -
/// a dialog's title, a prompt's caption. Mounted members' `*Key` values the
/// host resolves itself as it reads them; these are asked of it one by one.
public enum Strings {
    /// What `key` resolves to in the host's tables - its pattern formatted
    /// with its arguments where the host names no table for it, which is also
    /// the answer where no page is showing to ask.
    ///
    /// - Parameter key: the lookup key - a literal, or `key:` built by hand.
    /// - Returns: the resolved words.
    public static nonisolated(nonsending) func localize(_ key: LocalizedStringKey) async -> String {
        (try? await stateUICall(AppContract.localizedString, key)) ?? key.displayString
    }
}
