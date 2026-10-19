// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// A TextEditor: a WinUI `TextBox` of several lines, whose Enter starts a new one; growing with its words, or
/// keeping the height it is given and scrolling them.
/// Design: docs/design/platforms/winui/controls.md#an-editor
@MainActor
final class WinUITextEditorView: WinUIInputView {
    /// Whether the editor takes the height of its words.
    var growsWithText = false {
        didSet { if growsWithText != oldValue { invalidateMeasure() } }
    }

    init() {
        super.init { number in swiftomniui_winui_editor_make(number) }
    }

    /// Hides only the editor's canvas, leaving native editing and the words' look intact.
    func setContentBackground(_ visibility: Visibility?) {
        swiftomniui_winui_editor_set_background_hidden(handle, visibility == .hidden)
    }

    /// An allocated height belongs to the parent. Without one, a scrolling
    /// editor asks for one native line; a growing editor asks for all its words.
    override func measure(width: Double?, height: Double?) -> LayoutSize {
        let offeredHeight: Double?
        if !growsWithText, height?.isFinite != true {
            var lineHeight = Double.nan
            guard swiftomniui_winui_editor_intrinsic_height(handle, &lineHeight) else {
                preconditionFailure("WinUI could not measure the editor's intrinsic line")
            }
            offeredHeight = lineHeight
        } else {
            offeredHeight = height
        }
        return super.measure(width: width, height: offeredHeight)
    }
}
