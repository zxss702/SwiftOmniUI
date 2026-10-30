// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// WinUI's `SplitView`: the sidebar page in its pane - beside the detail page where the window is wide, over it
/// where it is narrow - and a row across the top of the detail. WinUI chooses which, as it does for any Windows app.
/// Design: docs/design/platforms/winui/pages.md#a-split-view
@MainActor
final class WinUISidebarView: WinUIView {
    /// The width from which the pane stands beside the detail, in DIPs: where WinUI's navigation pane expands.
    static let expandsAt = 1008.0

    /// What the view does when its pane opens or closes of WinUI's accord.
    var onPresented: ((Bool) -> Void)?

    init(trailing: Bool = false) {
        super.init { number in swiftomniui_winui_split_make(number, trailing ? 0 : Self.expandsAt, trailing) }
    }

    /// The pane and content pages, their width constraints, and a row above the content.
    func set(sidebar: WinUIView?, detail: WinUIView?, row: WinUIView?, open: Bool,
             widths: SplitColumnWidth = SplitColumnWidth(nil), contentShown: Bool = true,
             contentWidths: SplitColumnWidth = SplitColumnWidth(nil)) {
        swiftomniui_winui_split_set(handle, sidebar?.presentationHandle, detail?.presentationHandle, row?.presentationHandle, open,
                                   widths.minimum, widths.ideal, widths.maximum,
                                   contentShown, contentWidths.minimum, contentWidths.maximum)
        invalidateMeasure()
    }

    func clear() { swiftomniui_winui_split_clear(handle) }
    func prepareFirstRoom(width: Double) { swiftomniui_winui_split_prepare_room(handle, width) }
    func remove(_ view: WinUIView) { swiftomniui_winui_split_remove(handle, view.presentationHandle) }
    var minimumRoom: Double { swiftomniui_winui_split_minimum_width(handle) }

    /// OpenPaneLength already dirties native layout. Forget Swift's cached
    /// proposals without scheduling another native pass through the same pages.
    /// Include native owners because the trailing split has no placingLayout.
    func paneWidthChanged() {
        discardMeasurementResults()
        var owner = placingLayout ?? nativeLayoutOwner
        while let layout = owner {
            layout.discardMeasurementResults()
            owner = layout.placingLayout ?? layout.nativeLayoutOwner
        }
    }

    override func presented(_ open: Bool) {
        guard !ProgramWrite.isWriting else { return }
        onPresented?(open)
    }

    override func detach() {
        super.detach()
        onPresented = nil
    }
}
