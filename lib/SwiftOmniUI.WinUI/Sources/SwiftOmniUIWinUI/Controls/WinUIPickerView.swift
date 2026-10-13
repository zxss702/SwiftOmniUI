// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// A Picker: WinUI's `ComboBox`, its choices, the one chosen and its list, which the user opens and closes.
/// Design: docs/design/platforms/winui/controls.md#a-picker
@MainActor
final class WinUIPickerView: WinUIView {
    override var takesDirection: Bool { true }

    /// What the picker does as the user chooses, opens its list and closes it.
    var onChosen: ((Int) -> Void)?
    var onOpened: (() -> Void)?
    var onClosed: (() -> Void)?

    /// The choices and the choice as the tree last wrote them (`PickerChoices`).
    private var written = PickerChoices()

    /// Whose the list's opening and closing are.
    private var showing = WinUIShowing()

    private var closedSizes: [(width: Double?, height: Double?, size: LayoutSize)] = []

    override func measure(width: Double?, height: Double?) -> LayoutSize {
        let width = width.map { Double(Float($0)) }, height = height.map { Double(Float($0)) }
        if isOpen, let measured = closedSizes.last(where: { $0.width == width && $0.height == height }) {
            return measured.size
        }
        let size = super.measure(width: width, height: height)
        if !isOpen, WinUIView.arranging == 0 {
            closedSizes.removeAll { $0.width == width && $0.height == height }
            if closedSizes.count == 8 { closedSizes.removeFirst() }
            closedSizes.append((width, height, size))
        }
        return size
    }

    init() {
        super.init { number in swiftomniui_winui_picker_make(number) }
    }

    /// The choices, the one chosen - written only where `writeChosen` or the choices changed, so the user's choice
    /// is never argued with - and what the picker says while none is.
    func setChoices(_ choices: [String], chosen: Int, writeChosen: Bool, title: String) {
        let write = written.write(choices, chosen: chosen, choiceChanged: writeChosen)
        if let choices = write.choices {
            WinUIStrings.withCStrings(choices) { pointers in
                swiftomniui_winui_picker_set_options(handle, pointers, Int32(choices.count))
            }
        }
        swiftomniui_winui_picker_set(handle, Int32(clamping: write.chosen ?? -1), write.writesChoice, title)
    }

    /// Where the choices stand across the picker.
    func setAlignment(_ alignment: TextAlignment) {
        swiftomniui_winui_picker_set_alignment(handle, alignment.rawValue)
    }

    /// How the box presents: `.inline` chrome-less, the rest the platform's own.
    func setStyle(_ style: PickerStyleKind) {
        swiftomniui_winui_picker_set_style(handle, style.rawValue)
    }

    /// Opens or closes the list; neither is the user's, so neither is reported.
    func setOpen(_ open: Bool) {
        if showing.programAsks(open: open, shown: isOpen) { swiftomniui_winui_picker_set_open(handle, open) }
    }

    /// Whether the list shows.
    var isOpen: Bool { swiftomniui_winui_picker_is_open(handle) }

    /// The choice WinUI shows; -1 for none.
    var chosen: Int { Int(swiftomniui_winui_picker_selected(handle)) }

    func setEnabled(_ enabled: Bool) {
        swiftomniui_winui_set_enabled(handle, enabled)
    }

    override func chose(_ index: Int) {
        guard !ProgramWrite.isWriting, written.choices.indices.contains(index) else { return }
        onChosen?(index)
        invalidateChoiceMeasurements()
    }

    /// The list opened or closed: the user's, reported; the program's, not.
    override func presented(_ open: Bool) {
        if !open {
            closedSizes.removeAll(keepingCapacity: true)
            invalidateChoiceMeasurements()
        }
        guard showing.heard(open: open) else { return }
        if open { onOpened?() } else { onClosed?() }
    }

    private func invalidateChoiceMeasurements() {
        invalidateMeasure()
        var ancestor = placingLayout
        while let layout = ancestor {
            layout.invalidateMeasurements()
            ancestor = (layout as? WinUIScrollDocument)?.scrollView ?? layout.placingLayout
        }
    }

    override func detach() {
        super.detach()
        closedSizes.removeAll(keepingCapacity: true)
        onChosen = nil
        onOpened = nil
        onClosed = nil
    }
}
