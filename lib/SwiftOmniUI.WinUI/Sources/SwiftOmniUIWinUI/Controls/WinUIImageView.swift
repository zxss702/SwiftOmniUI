// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIWinUI

/// An Image: a WinUI `Image` showing a picture from the application's folder at its own size, filling the room
/// it is given as the aspect says.
/// Design: docs/design/platforms/winui/controls.md#pictures
@MainActor
final class WinUIImageView: WinUIView {
    override var reusesNativeMeasurements: Bool { true }
    /// The picture shown, by file name, and whether it was found.
    private(set) var file = ""
    private(set) var found = false

    /// How the picture fills its room.
    private var aspect = ContentMode.center

    /// The synchronously decoded bitmap size or SVG's intrinsic size, in DIPs.
    private var declared: LayoutSize?

    /// The size last assigned to the native picture inside its room.
    private var picturePlace: LayoutSize?

    private struct Load: Equatable {
        var source: ImageSource?
        var aspect: ContentMode
        var fontSize: Double
        var fontWeight: Double
        var textStyle: Int32
        var folder: UInt64
    }
    private var loaded: Load?

    init() {
        super.init { _ in swiftomniui_winui_image_make() }
    }

    /// Whether the current content is a platform symbol rather than a file.
    private var symbol = false

    /// Shows the picture `source` names, filling its room as `aspect` says. Its layout is told itself: WinUI hears
    /// nothing from a picture that asks it for no room. A source naming a symbol shows it as a Segoe Fluent Icons
    /// glyph - the platform's own symbol set, where the name is the glyph.
    func apply(source: ImageSource?, aspect: ContentMode, resizable: Bool = false, font: TextLook = TextLook()) {
        let aspect = resizable ? aspect : .center
        let symbol = source?.symbol != nil
        let load = Load(source: source, aspect: aspect,
                        fontSize: symbol ? font.size ?? 0 : 0,
                        fontWeight: symbol ? font.weight ?? (font.attributes.contains(.bold) ? 700 : 0) : 0,
                        textStyle: symbol ? font.textStyle?.rawValue ?? -1 : -1,
                        folder: symbol ? 0 : swiftomniui_winui_pictures_revision())
        // Inherited font changes do not reload a file image. A real source,
        // aspect or asset-folder change still takes effect synchronously.
        guard load != loaded || !found else { return }
        loaded = load
        self.symbol = symbol
        file = source?.file ?? ""
        self.aspect = aspect
        var size = [0.0, 0.0]
        if let name = source?.symbol {
            found = swiftomniui_winui_image_set_symbol(handle, name, aspect.rawValue, font.size ?? 0,
                font.weight ?? (font.attributes.contains(.bold) ? 700 : 0), font.textStyle?.rawValue ?? -1, &size)
            if !found { WinUIRenderer.log.error("no symbol \(name) the platform knows") }
        } else {
            let files = PictureArithmetic.files(for: file)
            found = WinUIStrings.withCStrings(files) { names in
                swiftomniui_winui_image_set(handle, names, Int32(files.count), aspect.rawValue, &size)
            }
            if !found { WinUIRenderer.log.error("no picture \(file) among the application's pictures") }
        }
        declared = size[0] > 0 && size[1] > 0 ? LayoutSize(width: size[0], height: size[1]) : nil
        picturePlace = nil
        invalidateMeasure()
        if let placed { draw(in: placed) }
        placingLayout?.invalidateMeasurements()
    }

    /// The picture's own size, whatever the room offered: an SVG's declared, a bitmap's once read - and a
    /// symbol's nominal glyph box. WinUI is asked for no room, so the picture is drawn in the place its layout
    /// gives it.
    /// Design: docs/design/platforms/winui/controls.md#pictures
    override func measure(width: Double?, height: Double?) -> LayoutSize {
        let intrinsic = intrinsicSize
        // Preparing a Viewbox/FontIcon at zero clips its native content even
        // though Swift's intrinsic result is nonzero. Prepare the same box
        // the arithmetic reports, before its first native arrangement.
        _ = super.measure(width: intrinsic.width, height: intrinsic.height)
        return intrinsic
    }

    override func prepareNativeMeasure(width: Double?, height: Double?) {
        let intrinsic = intrinsicSize
        super.prepareNativeMeasure(width: intrinsic.width, height: intrinsic.height)
    }

    private var intrinsicSize: LayoutSize {
        let intrinsic: LayoutSize
        if let declared { intrinsic = declared }
        else if symbol { intrinsic = LayoutSize(width: 16, height: 16) }
        else {
            var size = [0.0, 0.0]
            swiftomniui_winui_image_size(handle, &size)
            intrinsic = LayoutSize(width: size[0], height: size[1])
        }
        return intrinsic
    }

    override func layout(_ place: Rect) {
        super.layout(place)
        draw(in: place)
    }

    /// Places the picture and synchronously supplies any additional SVG pixels
    /// this size and the native DPI need. Ready rasters are shared across rows.
    private func draw(in room: Rect) {
        guard room.width > 0, room.height > 0 else { return }
        guard let declared else { return }

        let shown = PictureArithmetic.place(declared, in: LayoutSize(width: room.width, height: room.height), aspect: aspect)
        let size = LayoutSize(width: shown.width, height: shown.height)
        guard size.width > 0, size.height > 0 else { return }
        if picturePlace != size {
            swiftomniui_winui_image_place(handle, size.width, size.height)
            picturePlace = size
        }
        guard !symbol else { return }
        swiftomniui_winui_image_draw(handle, size.width, size.height)
    }
}
