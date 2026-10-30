// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// `LazyHGridContract` on a host: a lazy grid mounts the items it is told, spaced and flown as the tree says,
/// reporting the ones it realized.
@_spi(Host) public enum LazyHGridTests: ConformanceFamily {
    public static let name = "LazyHGrid"

    public static var cases: [ConformanceCase] {
        [
            Aspects.standsAlone("LazyHGrid"),
            Aspects.holds(LazyHGridContract.items, on: "LazyHGrid", ["a", "b"], then: ["a", "b", "c"]),
            Aspects.holds(LazyHGridContract.columnSpacing, on: "LazyHGrid", 4, then: 8),
            Aspects.holds(LazyHGridContract.rowSpacing, on: "LazyHGrid", 4, then: 8),
            Aspects.holds(LazyHGridContract.flowRows, on: "LazyHGrid", [GridItem()], then: [GridItem(), GridItem()]),
            Realized.heard(on: "LazyHGrid", LazyHGridContract.realizedChanged),
        ]
    }
}
