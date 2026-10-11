// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// `LazyHStackContract` on a host: a lazy stack mounts the items it is told, reporting the ones it realized.
@_spi(Host) public enum LazyHStackTests: ConformanceFamily {
    public static let name = "LazyHStack"

    public static var cases: [ConformanceCase] {
        [
            Aspects.standsAlone("LazyHStack"),
            Aspects.holds(LazyHStackContract.items, on: "LazyHStack", ["a", "b"], then: ["a", "b", "c"]),
            Realized.heard(on: "LazyHStack", LazyHStackContract.realizedChanged),
        ]
    }
}
