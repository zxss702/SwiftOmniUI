// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore

/// One entry a window's chrome holds for the arrangement it shows - an action, a spacer, or the view a
/// `ToolbarItem` carries.
@MainActor
struct WinUIToolbarAction {
    let title: String
    let isEnabled: Bool
    var identifier: String?
    /// The files its picture may stand in, in order (`PictureArithmetic.files`); none for words alone.
    var icon: [String] = []
    /// The platform symbol it shows instead - a Segoe Fluent glyph - where its picture is one; nil for none.
    var symbol: String?
    let perform: () -> Void
    var view: WinUIView?
    var spacer: ToolbarSpacerVariant?

    /// Whether two actions draw the same button. What an action performs is taken again on every composition.
    func draws(like other: WinUIToolbarAction) -> Bool {
        title == other.title && isEnabled == other.isEnabled && identifier == other.identifier && icon == other.icon
            && symbol == other.symbol && view === other.view && spacer == other.spacer
    }
}
