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
        super.init(allocation: { swiftomniui_winui_editor_allocation_make($0) }) {
            number in swiftomniui_winui_editor_make(number)
        }
    }

    /// Hides only the editor's canvas, leaving native editing and the words' look intact.
    func setContentBackground(_ visibility: Visibility?) {
        swiftomniui_winui_editor_set_background_hidden(handle, visibility == .hidden)
    }

    /// The retained TextBox's geometry inside its allocation boundary. Keep it
    /// distinct from the boundary so tests detect template clipping.
    var controlFrame: Rect {
        var frame = [0.0, 0.0, 0.0, 0.0]
        swiftomniui_winui_frame(handle, &frame)
        return Rect(frame[0], frame[1], frame[2], frame[3])
    }

    /// Arithmetic queries must not change the live TextBox's native Measure
    /// input. The native allocation boundary prepares that control for its
    /// final slot; Measure proposals and ideal queries do not select that slot.
    override func measure(width: Double?, height: Double?) -> LayoutSize {
        let offeredWidth = width.flatMap { $0.isFinite ? max(0, $0) : nil }
        let offeredHeight = height.flatMap { $0.isFinite ? max(0, $0) : nil }
        if let offeredWidth, let offeredHeight {
            return LayoutSize(width: offeredWidth, height: offeredHeight)
        }
        var natural = [0.0, 0.0]
        guard swiftomniui_winui_editor_content_size(handle, offeredWidth ?? .infinity, growsWithText, &natural) else {
            preconditionFailure("WinUI could not query the editor's content size")
        }
        return LayoutSize(width: offeredWidth ?? natural[0], height: offeredHeight ?? natural[1])
    }
}
