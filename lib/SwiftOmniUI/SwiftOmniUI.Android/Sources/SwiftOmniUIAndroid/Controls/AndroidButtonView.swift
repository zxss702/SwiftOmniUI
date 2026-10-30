// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIAndroid

/// A Button: an `android.widget.Button` whose click reaches Swift through its `SwiftOmniUIListener`.
@MainActor
final class AndroidButtonView: AndroidTextView {
    /// What the button does when it is clicked.
    var onClicked: (() -> Void)?

    /// What the button does as a finger takes hold of it.
    var onPressed: (() -> Void)?

    /// What the button does as the finger lets go, whether or not it clicked.
    var onReleased: (() -> Void)?

    /// What a staying-pressed button reports when a tap flips it - `isOn`
    /// worn on the element at all makes it one. The kept state is the view's
    /// `selected` state, which a theme's drawables answer.
    var onToggled: ((Bool) -> Void)?

    /// Whether a tap keeps its pressed look - `isOn` worn at all.
    private var toggleable = false

    /// Whether the press keeps, read back when a click flips it.
    private var on = false

    /// What the button draws itself with: a fill, an outline and its corners, in points.
    private var look = Look()

    /// The icon, where it stands, how it fills the room, and the picture held for it.
    private var icon = Icon()

    /// Whether the button has words: without them its icon stands alone in the middle.
    private var hasWords = false

    /// What the icon was last shown as, so an unchanged one is not sent again.
    private var shownIcon: Icon.Shown?

    init() {
        super.init { _ in Java.new(JavaAPI.button, JavaAPI.newButton, .object(AndroidRenderer.context)) }
        Java.call(reference, JavaAPI.setAllCaps, .bool(false))
        setLeastSize(width: 0, height: 0)

        listen(JavaAPI.setOnClickListener, JavaAPI.setOnTouchListener)
    }

    /// The least pixels the button takes, in place of its color scheme's: a button is its words and its padding.
    /// Design: docs/design/platforms/android/controls.md#a-buttons-size
    func setLeastSize(width: Int32, height: Int32) {
        Java.call(reference, JavaAPI.setMinWidth, .int(width))
        Java.call(reference, JavaAPI.setMinimumWidth, .int(width))
        Java.call(reference, JavaAPI.setMinHeight, .int(height))
        Java.call(reference, JavaAPI.setMinimumHeight, .int(height))
    }

    /// The staying-pressed look, or none: `nil` for a button that only
    /// flashes under the touch.
    func setOn(_ on: Bool?) {
        toggleable = on != nil
        self.on = on ?? false
        Java.call(reference, JavaAPI.setSelected, .bool(self.on))
    }

    /// A click is the button's own event, and a tap as any view's.
    override func clicked() {
        onClicked?()
        super.clicked()
        guard toggleable else { return }
        on.toggle()
        Java.call(reference, JavaAPI.setSelected, .bool(on))
        onToggled?(on)
    }

    override func held(_ holding: Bool) {
        (holding ? onPressed : onReleased)?()
    }

    // MARK: - Its look

    /// The logical style: plain and borderless draw nothing under the ripple,
    /// and the rest the color scheme's own button look.
    func setStyle(_ style: ButtonStyleKind?) {
        switch style ?? .automatic {
        case .plain, .borderless, .link:
            look.fill = Color.transparent.propValue
            drawLook()
        default:
            break
        }
    }

    /// The button's fill: its look is drawn again with it.
    override func setBackground(_ value: HostValue?) {
        look.fill = value
        drawLook()
    }

    /// The button's outline and shape, the width in points and one where none is said; no outline, a plain
    /// rectangle and no fill keep the color scheme's look.
    func setOutline(stroke: HostValue?, width: Double?, shape: HostValue?) {
        look.stroke = stroke
        look.strokeWidth = width
        look.shape = AndroidShapeDrawable.Shape(container: shape)
        drawLook()
    }

    /// The shape its look is drawn in, and the one its pressed ripple is kept within; none while the color scheme's
    /// look shows.
    private var drawn: (shape: AndroidShapeDrawable, mask: AndroidShapeDrawable)?

    /// One shape under the platform's pressed ripple, or the color scheme's background where nothing is said.
    /// Design: docs/design/platforms/android/controls.md#a-buttons-look
    private func drawLook() {
        guard look.fill != nil || look.stroke != nil || look.shape != .rectangle else {
            drawn = nil
            return showBackground(nil)
        }

        let corners = look.shape
        let shape = AndroidShapeDrawable()
        shape.setStroke(look.stroke, width: look.strokeWidth, density: density)
        shape.setShape(corners, density: density)
        shape.setFill(look.fill)
        let mask = AndroidShapeDrawable()
        mask.setShape(corners, density: density)
        mask.setFill(Color("#000000").propValue)
        drawn = (shape, mask)
        if let size = placedSize { sized(width: size.width, height: size.height) }

        let pressable = withExtendedLifetime((shape, mask)) {
            Java.callStaticObject(
                JavaAPI.views, JavaAPI.pressable,
                .object(AndroidRenderer.context), .object(shape.reference), .object(mask.reference))
        }
        showBackground(pressable.map(JavaObject.init))
    }

    // MARK: - Its icon

    /// The picture beside the words `spacing` points away - the platform's gap for nil - or alone where
    /// there are none, filling its room as `aspect` says.
    func setIcon(_ source: ImageSource?, position: IconPosition, spacing: Double?, aspect: ContentMode) {
        let file = source?.file ?? ""
        if file != icon.file {
            letGoOfIcon()
            icon.file = file
            icon.picture = file.isEmpty ? nil : AndroidPictures.take(named: file, sample: 1)
        }
        icon.position = position
        icon.spacing = spacing
        icon.aspect = aspect
        showIcon(room: placedSize)
    }

    /// The words decide where the icon goes: beside them, or alone in the middle.
    override func setText(_ text: String) {
        super.setText(text)
        hasWords = !text.isEmpty
        showIcon(room: placedSize)
    }

    /// An icon standing alone is sized to the room the button is placed in, before it is placed there; a
    /// button only moving keeps it.
    override func layout(_ place: Rect) {
        let room = (width: pixels(place.width), height: pixels(place.height))
        if !hasWords, placedSize.map({ $0 != room }) ?? true { showIcon(room: room) }
        super.layout(place)
    }

    override func sized(width: Int32, height: Int32) {
        drawn?.shape.fit(width: width, height: height)
        drawn?.mask.fit(width: width, height: height)
    }

    /// The padding is the icon's room too.
    override func setPadding(_ insets: EdgeInsets?) {
        super.setPadding(insets)
        showIcon(room: placedSize)
    }

    override func detach() {
        super.detach()
        onClicked = nil
        onPressed = nil
        onReleased = nil
        letGoOfIcon()
    }

    /// Puts the icon on the button when what shows changed: beside its words at its own size, or alone,
    /// sized to the room inside the padding as its aspect says.
    private func showIcon(room: (width: Int32, height: Int32)?) {
        let alone = hasWords ? (width: Int32(0), height: Int32(0)) : iconSizeAlone(in: room)
        let shown = Icon.Shown(
            file: icon.file, position: icon.position, spacing: icon.spacing, words: hasWords,
            width: alone.width, height: alone.height)
        guard shown != shownIcon else { return }
        shownIcon = shown

        let position: Int32 = switch icon.position {
        case .leading: 0
        case .trailing: 1
        case .top: 2
        case .bottom: 3
        }
        withExtendedLifetime(icon.picture) {
            Java.callStatic(
                JavaAPI.views, JavaAPI.setIcon, .object(reference), .object(icon.picture?.reference),
                .int(position), .int(icon.spacing.map(pixels) ?? -1), .int(alone.width), .int(alone.height))
        }
    }

    /// The icon's size shown alone: the room inside the padding, filled as the aspect says.
    private func iconSizeAlone(in room: (width: Int32, height: Int32)?) -> (width: Int32, height: Int32) {
        guard let room, !icon.file.isEmpty, let size = AndroidPictures.size(named: icon.file),
              size.width > 0, size.height > 0
        else { return (0, 0) }

        let inside = (
            width: Double(room.width - Java.callInt(reference, JavaAPI.getPaddingLeft)
                - Java.callInt(reference, JavaAPI.getPaddingRight)),
            height: Double(room.height - Java.callInt(reference, JavaAPI.getPaddingTop)
                - Java.callInt(reference, JavaAPI.getPaddingBottom)))

        switch icon.aspect {
        case .center:
            return size
        case .stretch:
            return (Int32(max(inside.width, 0)), Int32(max(inside.height, 0)))
        case .fit, .fill:
            let scale = max(0, min(inside.width / Double(size.width), inside.height / Double(size.height)))
            return (Int32((Double(size.width) * scale).rounded()), Int32((Double(size.height) * scale).rounded()))
        }
    }

    /// Lets go of the icon's picture.
    private func letGoOfIcon() {
        if icon.picture != nil { AndroidPictures.letGo(named: icon.file, sample: 1) }
        icon.picture = nil
    }

    /// What a button draws itself with.
    private struct Look {
        var fill: HostValue?
        var stroke: HostValue?
        var strokeWidth: Double?
        var shape = AndroidShapeDrawable.Shape.rectangle
    }

    /// A button's icon.
    private struct Icon {
        var file = ""
        var position: IconPosition = .leading
        var spacing: Double?
        var aspect: ContentMode = .fit
        var picture: JavaObject?

        /// What an icon shows as: its picture, where, and its size alone in pixels.
        struct Shown: Equatable {
            let file: String
            let position: IconPosition
            let spacing: Double?
            let words: Bool
            let width: Int32
            let height: Int32
        }
    }
}
