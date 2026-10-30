// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// `ToolbarSpacerContract` on a host: a toolbar's spacer takes the room its variant says, placed among the bar's
/// groups where the tree puts it.
@_spi(Host) public enum ToolbarSpacerTests: ConformanceFamily {
    public static let name = "ToolbarSpacer"

    public static var cases: [ConformanceCase] {
        [
            ConformanceCase("aSpacerStandsOnTheBar", proves: [
                Covered(member: nil, element: "ToolbarSpacer", tier: nil),
            ]) { s in
                s.start { Specimens.page("ToolbarSpacer") }
                s.settle { !s.elements(ofType: ToolbarSpacerContract.nodeType).isEmpty }
                s.expect(s.elements(ofType: ToolbarSpacerContract.nodeType).isEmpty, false,
                         "standing on the page's bar")
            },
            Aspects.holds(ToolbarSpacerContract.placement, on: "ToolbarSpacer", .overflow, then: .primaryAction),
            Aspects.holds(ToolbarSpacerContract.variant, on: "ToolbarSpacer", .fixed, then: .flexible),
        ]
    }
}
