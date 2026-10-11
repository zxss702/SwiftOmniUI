// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// `MaskedContract` on a host: a masked element shows its content through the shape the tree gives it.
@_spi(Host) public enum MaskedTests: ConformanceFamily {
    public static let name = "Masked"

    public static var cases: [ConformanceCase] {
        [Aspects.standsAlone("Masked")]
    }
}
