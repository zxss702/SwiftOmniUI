// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// `GridRowContract` on a host: a grid's row stands its cells one to a column, where the grid's columns put them.
@_spi(Host) public enum GridRowTests: ConformanceFamily {
    public static let name = "GridRow"

    public static var cases: [ConformanceCase] {
        [
            ConformanceCase("aRowStandsItsCellsInTheGrid", proves: [
                Covered(member: nil, element: "GridRow", tier: nil),
            ]) { s in
                s.start { Specimens.page("GridRow") }
                s.settle { !s.elements(ofType: GridRowContract.nodeType).isEmpty }
                s.expect(s.elements(ofType: GridRowContract.nodeType).isEmpty, false,
                         "a row the grid mounts")
            },
        ]
    }
}
