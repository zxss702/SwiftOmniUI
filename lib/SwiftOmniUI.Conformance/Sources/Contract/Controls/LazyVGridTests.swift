// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// `LazyVGridContract` on a host: a lazy grid mounts the items it is told, spaced and flown as the tree says,
/// reporting the ones it realized.
@_spi(Host) public enum LazyVGridTests: ConformanceFamily {
    public static let name = "LazyVGrid"

    public static var cases: [ConformanceCase] {
        [
            Aspects.standsAlone("LazyVGrid"),
            Aspects.holds(LazyVGridContract.items, on: "LazyVGrid", ["a", "b"], then: ["a", "b", "c"]),
            Aspects.holds(LazyVGridContract.columnSpacing, on: "LazyVGrid", 4, then: 8),
            Aspects.holds(LazyVGridContract.rowSpacing, on: "LazyVGrid", 4, then: 8),
            Aspects.holds(LazyVGridContract.flowColumns, on: "LazyVGrid", [GridItem()], then: [GridItem(), GridItem()]),
            Realized.heard(on: "LazyVGrid", LazyVGridContract.realizedChanged),
        ]
    }
}
