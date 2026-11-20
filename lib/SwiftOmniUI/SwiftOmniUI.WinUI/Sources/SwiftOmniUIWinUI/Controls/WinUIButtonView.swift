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
    private weak var labelRoot: WinUIView?
    private var destinationWidth: Double?
    override var controlStateOpacity: Double { hasViewLabel && !enabled ? 0.5 : 1 }

    var remainingLabelWidthChange: Double? {
        guard let destinationWidth else { return nil }
        let minimum = desiredSize.width
        return max(destinationWidth, minimum) - max(placedFrame.width, minimum)
    }

    /// A custom SwiftUI label owns its intrinsic size. The native image panel
    /// intentionally reports no desired size because Swift places it itself,
    /// so asking WinUI's Button to measure that panel would make an image-only
    /// label collapse to zero. Measure the label through SOUI's layout model
    /// whenever this button owns the label directly.
    override func measure(width: Double?, height: Double?) -> LayoutSize {
        guard hasViewLabel, let labelRoot else {
            return super.measure(width: width, height: height)
        }
        let native = super.measure(width: width, height: height)
        let label: LayoutSize
        if let layout = labelRoot as? WinUILayoutView {
            let proposal = ProposedViewSize(width: width, height: height)
            label = height == nil
                ? layout.naturalSize(width: width)
                : layout.naturalSize(proposal: proposal)
        } else {
            label = labelRoot.measure(width: width, height: height)
        }
        return LayoutSize(width: max(native.width, label.width), height: max(native.height, label.height))
    }

    override func travels(to destination: Rect?) {
        destinationWidth = destination?.width
    }

    override func firstTextBaseline(in size: LayoutSize) -> Double? {
        guard hasViewLabel, let labelRoot else { return nil }
        if let layout = labelRoot as? WinUILayoutView {
            let content = layout.naturalSize(proposal: ProposedViewSize(width: size.width, height: size.height))
            let inner = LayoutSize(width: min(size.width, content.width), height: min(size.height, content.height))
            guard let baseline = layout.firstTextBaseline(in: inner) else { return nil }
            return max(0, (size.height - inner.height) / 2) + baseline
        }
        return labelRoot.firstTextBaseline(in: size)
    }

    /// An arbitrary label may paint its own foreground/background. Native
    /// ForegroundDisabled alone cannot affect those explicitly drawn colors.
    func setFace(_ face: WinUIView?) {
        guard face != nil || hasViewLabel else { return }
        if labelRoot !== face {
            if labelRoot?.nativeContentOwner === self { labelRoot?.nativeContentOwner = nil }
            labelRoot = face
            face?.nativeContentOwner = self
            invalidateMeasure()
        }
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
    func setIcon(_ picture: ImageSource?, width: Double?, height: Double?) {
        guard isToolbarControl else { return }
        let files = picture.map(\.file).flatMap { $0.isEmpty ? nil : PictureArithmetic.files(for: $0) } ?? []
        swiftomniui_winui_toolbar_button_set_icon(
            handle, picture?.symbol ?? "", files.map { $0 + "\n" }.joined(), width ?? -1, height ?? -1)
    }

    /// The caption the button shows now, read back from WinUI.
    var text: String {
        WinUIView.words(of: handle)
    }

    /// What fills and outlines the button; nil for the platform's own.
    func setLook(background: HostValue?, stroke: HostValue?, strokeWidth: Double?) {
        let (fill, outline) = (WinUIBrush(background), WinUIBrush(stroke))
        let width = BoxArithmetic.outlineWidth(stroke: stroke, width: strokeWidth)
        paint("look", followsSize: fill.followsSize || outline.followsSize) { [weak self, handle] size in
            // The bar's button keeps WinUI's own look.
            if self?.isToolbarControl == true { return }
            fill.withRelayBrush(over: size) { fill in
                outline.withRelayBrush(over: size) { outline in
                    swiftomniui_winui_button_set_look(
                        handle, fill, outline, width, PressedFill.underPointer, PressedFill.pressed)
                }
            }
        }
    }

    func setCornerRadius(shape: HostValue?, style: ButtonStyleKind?) {
        guard !isToolbarControl else { return }
        let radius: Double = switch shape.map(BoxArithmetic.outline) {
        case .roundedRectangle(let radius)?: radius
        case .unevenRoundedRectangle(let cornerRadius)?: BoxArithmetic.clockwise(cornerRadius).max() ?? 0
        case .ellipse?, .capsule?, .circle?: .greatestFiniteMagnitude
        case .rectangle?: 0
        // WinUI's rounded presenter clips the whole label, including
        // backgrounds travelling between plain buttons via matched geometry.
        case nil: style == .plain ? 0 : -1
        }
        swiftomniui_winui_button_set_corner_radius(handle, radius)
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
        if labelRoot?.nativeContentOwner === self { labelRoot?.nativeContentOwner = nil }
        labelRoot = nil
        setShortcut(nil)
        super.detach()
        onClicked = nil
        onPressed = nil
        onReleased = nil
        onToggled = nil
    }
}
