// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

#if os(Windows) || os(Linux) || os(macOS)
import Foundation
@_spi(Host) import SwiftOmniUICore

/// AppStorage and non-UI model consumers share Foundation's standard defaults.
@_spi(Host) @MainActor public enum AppStorageDefaults {
    /// Imports older SOUI preferences only where standard defaults has no value.
    public static func restore(into core: CoreLink, legacy: KeptValuesText) {
        HostBoundary.usePersistentStore(read: read, write: write)
        var seen: Set<String> = []
        while true {
            let keys = core.persistentKeys.filter { seen.insert($0.name).inserted }
            guard !keys.isEmpty else { break }
            let previous = legacy.restored(for: keys)
            for key in keys {
                if key.name != "__swiftomniui.keys", UserDefaults.standard.object(forKey: key.name) == nil,
                   let value = previous[key.name] {
                    write(key, value)
                }
            }
            core.restorePersistent(previous)
        }
        _ = flush()
    }

    /// Corelibs defaults updates memory on set; synchronize commits it to disk.
    @discardableResult public static func flush() -> Bool { UserDefaults.standard.synchronize() }

    private nonisolated static func read(_ key: PersistentKey) -> PropValue? {
        let defaults = UserDefaults.standard
        guard let value = defaults.object(forKey: key.name) else { return nil }
        switch key.kind {
        case .boolean:
            guard value is NSNumber else { return nil }
            return .bool(defaults.bool(forKey: key.name))
        case .integer, .number:
            guard let number = value as? NSNumber else { return nil }
            return .number(number.doubleValue)
        case .text:
            guard let text = value as? String else { return nil }
            return .string(text)
        }
    }

    private nonisolated static func write(_ key: PersistentKey, _ value: PropValue) {
        let defaults = UserDefaults.standard
        switch value {
        case .bool(let flag): defaults.set(flag, forKey: key.name)
        case .number(let number): defaults.set(number, forKey: key.name)
        case .string(let text): defaults.set(text, forKey: key.name)
        default: break
        }
    }
}
#endif
