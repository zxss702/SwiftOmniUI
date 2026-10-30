// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// `ScrollContentElementContract` on a host: a scrollable's content stands on the background the tree gives it, and
/// the one the tree changes it to - on every element wearing the tier.
@_spi(Host) public enum ScrollContentElementTests: ConformanceFamily {
    public static let name = "ScrollContentElement"

    public static var cases: [ConformanceCase] {
        Aspects.holdsOnEveryWearer(ScrollContentElementContract.scrollContentBackground, .hidden, then: .visible)
    }
}
