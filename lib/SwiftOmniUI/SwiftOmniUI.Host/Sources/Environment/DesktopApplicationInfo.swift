// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

#if os(Windows) || os(Linux) || os(macOS)
import Foundation

/// Desktop package metadata, prepared beside the executable by run/deploy.
/// Application display identity is independent of each scene's navigation title.
@_spi(Host) public enum DesktopApplicationInfo {
    private struct Metadata: Decodable { let displayName: String }

    public static let displayName: String? = {
        let url = Bundle.main.bundleURL.appendingPathComponent("app-info.json")
        guard let bytes = try? Data(contentsOf: url),
              let metadata = try? JSONDecoder().decode(Metadata.self, from: bytes),
              !metadata.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return metadata.displayName
    }()
}
#endif
