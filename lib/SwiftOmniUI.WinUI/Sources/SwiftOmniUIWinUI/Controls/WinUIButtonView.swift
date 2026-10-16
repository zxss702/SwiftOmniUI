// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// A WinUI `Button`: its caption, its look, whether it takes a press, and the click it raises.
@MainActor
final class WinUIButtonView: WinUIView {
    override var takesDirection: Bool { true }

    private var hasViewLabel = false
    private var caption = ""
    override var controlStateOpacity: Double { hasViewLabel && !enabled ? 0.5 : 1 }

    /// An arbitrary label may paint its own foreground/background. Native
    /// ForegroundDisabled alone cannot affect those explicitly drawn colors.
    func setFace(_ face: WinUIView?) {
        guard face != nil || hasViewLabel else { return }
        hasViewLabel = face != nil
        if let face {
            swiftomniui_winui_button_set_face(handle, face.presentationHandle)
        } else {
            swiftomniui_winui_set_caption(handle, caption)
        }
        setOpacity(opacity)
    }

    /// What the button does when the user clicks it, holds it down and lets it go.
    var onClicked: (() -> Void)?
    var onPressed: (() -> Void)?
    var onReleased: (() -> Void)?

    /// What a staying-pressed button reports when a press flips it - `isOn`
    /// worn on the element at all makes it one.
    var onToggled: ((Bool) -> Void)?

    /// The platform's button, or - `toolbar` - the bar's own, whose icon slot and label WinUI draws.
    init(toolbar: Bool = false) {
        super.init { number in toolbar ? swiftomniui_winui_toolbar_button_make(number) : swiftomniui_winui_button_make(number) }
        isToolbarControl = toolbar
    }

    /// The caption.
    func setText(_ text: String) {
        caption = text
        guard !hasViewLabel else { return }
        swiftomniui_winui_set_caption(handle, text)
    }

    /// The picture in the bar's button's icon slot - a Fluent glyph or a picture's file; its words move to its
    /// tip. The platform's own button draws no picture.
    func setIcon(_ picture: ImageSource?) {
        guard isToolbarControl else { return }
        let files = picture.map(\.file).flatMap { $0.isEmpty ? nil : PictureArithmetic.files(for: $0) } ?? []
        swiftomniui_winui_toolbar_button_set_icon(handle, picture?.symbol ?? "", files.map { $0 + "\n" }.joined())
    }

    /// The caption the button shows now, read back from WinUI.
    var text: String {
        WinUIView.words(of: handle)
    }

    /// What fills the button, its outline and its shape; nil for the platform's own.
    func setLook(background: HostValue?, stroke: HostValue?, strokeWidth: Double?, shape: HostValue?) {
        let radius: Double = switch shape.map(BoxArithmetic.outline) {
        case .roundedRectangle(let radius)?: radius
        case .unevenRoundedRectangle(let cornerRadius)?: BoxArithmetic.clockwise(cornerRadius).max() ?? 0
        case .ellipse?, .capsule?, .circle?: .greatestFiniteMagnitude
        case .rectangle?: 0
        case nil: -1
        }
        let (fill, outline) = (WinUIBrush(background), WinUIBrush(stroke))
        let width = BoxArithmetic.outlineWidth(stroke: stroke, width: strokeWidth)
        paint("look", followsSize: fill.followsSize || outline.followsSize) { [weak self, handle] size in
            // The bar's button keeps WinUI's own look.
            if self?.isToolbarControl == true { return }
            fill.withRelayBrush(over: size) { fill in
                outline.withRelayBrush(over: size) { outline in
                    swiftomniui_winui_button_set_look(
                        handle, fill, outline, width, radius, PressedFill.underPointer, PressedFill.pressed)
                }
            }
        }
    }

    /// The logical style, mapped to the theme style WinUI names for it.
    func setStyle(_ style: ButtonStyleKind?) {
        if isToolbarControl { return }
        swiftomniui_winui_button_set_style(handle, (style ?? .automatic).rawValue)
    }

    /// The keyboard shortcut, as the `VirtualKey` and `VirtualKeyModifiers`
    /// numbers C++ hands straight to the accelerator.
    func setShortcut(_ shortcut: KeyboardShortcut?) {
        let (key, modifiers) = shortcut.map(WinUIKeyboardShortcut.numbers) ?? (0, 0)
        swiftomniui_winui_button_set_shortcut(handle, number, key, modifiers)
    }

    /// The staying-pressed look, or none: `nil` makes the button momentary
    /// again; worn at all the press keeps, and the user's flips come back
    /// through `onToggled`.
    func setOn(_ on: Bool?) {
        swiftomniui_winui_button_set_on(handle, on != nil ? 1 : 0, (on ?? false) ? 1 : 0)
    }

    override func toggled(_ on: Bool) {
        onToggled?(on)
    }

    override func clicked() {
        onClicked?()
    }

    override func held(_ holding: Bool) {
        (holding ? onPressed : onReleased)?()
    }

    override func detach() {
        setShortcut(nil)
        super.detach()
        onClicked = nil
        onPressed = nil
        onReleased = nil
        onToggled = nil
    }
}
