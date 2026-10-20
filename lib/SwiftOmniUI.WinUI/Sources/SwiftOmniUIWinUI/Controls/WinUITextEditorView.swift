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

    /// The parent selects an allocation before this leaf enters native
    /// Measure/Arrange. A finite Height tells TextBox that its size belongs to
    /// SOUI; Auto would start TextBox's own focused multiline height animation.
    override func prepareMeasure(width: Double, height: Double? = nil) {
        precondition(!isNativeArranging, "an arranging editor cannot measure itself")
        let allocation = height.flatMap { $0.isFinite ? max(0, $0) : nil }
            ?? measure(width: width.isFinite ? width : nil, height: nil).height
        let nativeHeight = Double(Float(allocation))
        swiftomniui_winui_editor_set_allocated_height(handle, nativeHeight)
        super.prepareMeasure(width: width, height: nativeHeight)
    }

    /// A parent can assign a different presentation slot than its Measure
    /// proposal. Prepare this leaf for that slot before its own Arrange, never
    /// remeasuring the enclosing panel or a native container's subtree.
    override func prepareAllocation(in bounds: Rect) {
        prepareMeasure(width: bounds.width, height: bounds.height)
    }

    /// Arithmetic queries must not change the live TextBox's native Measure
    /// input. The parent's prepareMeasure alone prepares that control for its
    /// allocation; Arrange may query ideal sizes again at different widths.
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
