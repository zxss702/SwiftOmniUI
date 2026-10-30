// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIWinUI

/// This element's WinUI half, the way the tests reach it.
///
/// The host's `MountedElement` belongs to `SwiftOmniUIHost`, so the `winUI` the toolkit declares in an extension of
/// it stays inside that toolkit: `@testable` reaches what a module declares on a type of its own, never what it
/// declares on another module's - so the tests declare their own reach, and the toolkit's own sources keep theirs.
extension MountedElement {
    var winUI: WinUIElement { native as! WinUIElement }
}
