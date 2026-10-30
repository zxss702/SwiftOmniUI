// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// `LazyVStackContract` on a host: a lazy stack mounts the items it is told, reporting the ones it realized.
@_spi(Host) public enum LazyVStackTests: ConformanceFamily {
    public static let name = "LazyVStack"

    public static var cases: [ConformanceCase] {
        [
            Aspects.standsAlone("LazyVStack"),
            Aspects.holds(LazyVStackContract.items, on: "LazyVStack", ["a", "b"], then: ["a", "b", "c"]),
            Realized.heard(on: "LazyVStack", LazyVStackContract.realizedChanged),
        ]
    }
}
