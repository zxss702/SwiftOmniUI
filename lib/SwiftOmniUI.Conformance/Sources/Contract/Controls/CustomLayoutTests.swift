// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// `CustomLayoutContract` on a host: an application's own layout stands its children where its arithmetic puts them.
@_spi(Host) public enum CustomLayoutTests: ConformanceFamily {
    public static let name = "CustomLayout"

    public static var cases: [ConformanceCase] {
        [Aspects.standsAlone("CustomLayout")]
    }
}
