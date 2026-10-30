// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// `ControlSizeElementContract` on a host: a control draws at the size the tree gives it, and the size the tree
/// changes it to - on every element wearing the tier.
@_spi(Host) public enum ControlSizeElementTests: ConformanceFamily {
    public static let name = "ControlSizeElement"

    public static var cases: [ConformanceCase] {
        Aspects.holdsOnEveryWearer(ControlSizeElementContract.controlSize, .small, then: .large)
    }
}
