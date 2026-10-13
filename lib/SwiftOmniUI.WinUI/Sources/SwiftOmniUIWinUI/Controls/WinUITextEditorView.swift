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

    /// Growing, the height its words take; not growing, one line's, whatever it holds.
    override func measure(width: Double?, height: Double?) -> LayoutSize {
        super.measure(width: width, height: growsWithText ? height : 0)
    }

    override func prepareNativeMeasure(width: Double?, height: Double?) {
        super.prepareNativeMeasure(width: width, height: growsWithText ? height : 0)
    }
}
