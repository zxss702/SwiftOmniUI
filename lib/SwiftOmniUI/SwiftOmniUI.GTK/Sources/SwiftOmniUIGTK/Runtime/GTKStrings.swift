// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

#if os(Linux)
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// The GTK host's string tables: where a `LocalizedStringKey` is answered.
/// GTK keeps no strings of the application's own, so the application installs
/// them - `GTKStrings.lookup` answers a key's pattern with its translation
/// for the language the application is showing, or nil for the key's own
/// fallback:
///
///     GTKStrings.lookup = { pattern in tables[currentLanguage][pattern] }
public enum GTKStrings {
    /// Answers a lookup key's pattern with its translation; nil leaves the
    /// key's own fallback drawn. Written once at the application's start, the
    /// way the application itself is.
    nonisolated(unsafe) public static var lookup: (String) -> String? = { _ in nil }

    /// What `key` looks up through `lookup`, formatted with its arguments.
    static func resolve(_ key: LocalizedStringKey) -> String {
        HostLocalizedStrings.resolve(key, lookup: lookup)
    }
}
#endif
