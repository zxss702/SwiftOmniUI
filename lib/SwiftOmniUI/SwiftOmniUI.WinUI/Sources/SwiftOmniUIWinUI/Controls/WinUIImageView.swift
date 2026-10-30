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
    override var cachesIntrinsicMeasurements: Bool { true }
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
    private var writtenTint: UInt32?
    private var hasWrittenTint = false

    init() {
        super.init(reportsAllocationFromArrange: true) { swiftomniui_winui_image_make($0) }
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
        if load == loaded && found {
            writeTint(font.color?.argb)
            return
        }
        loaded = load
        self.symbol = symbol
        file = source?.file ?? ""
        self.aspect = aspect
        var size = [0.0, 0.0]
        if let bitmap = source?.bitmap {
            found = swiftomniui_winui_image_set_pixels(handle, bitmap.pixels.rgba, Int32(bitmap.pixels.width),
                Int32(bitmap.pixels.height), bitmap.size.width, bitmap.size.height)
            size = [bitmap.size.width, bitmap.size.height]
        } else if let name = source?.symbol {
            found = swiftomniui_winui_image_set_symbol(handle, name, aspect.rawValue, font.size ?? 0,
                font.weight ?? (font.attributes.contains(.bold) ? 700 : 0), font.textStyle?.rawValue ?? -1, &size)
        } else {
            let files = PictureArithmetic.files(for: file)
            found = WinUIStrings.withCStrings(files) { names in
                swiftomniui_winui_image_set(handle, names, Int32(files.count), aspect.rawValue, &size)
            }
            if !found { WinUIRenderer.log.error("no picture \(file) among the application's pictures") }
        }
        declared = size[0] > 0 && size[1] > 0 ? LayoutSize(width: size[0], height: size[1]) : nil
        hasWrittenTint = false
        writeTint(font.color?.argb)
        picturePlace = nil
        discardMeasurementResults()
        if let committedFrame { draw(in: committedFrame) }
        placingLayout?.invalidateMeasurements()
    }

    private func writeTint(_ tint: UInt32?) {
        guard symbol, !hasWrittenTint || tint != writtenTint else { return }
        swiftomniui_winui_image_set_tint(handle, tint != nil, tint ?? 0)
        writtenTint = tint
        hasWrittenTint = true
    }

    /// The picture's own size, whatever the room offered: an SVG's declared, a bitmap's once read - and a
    /// symbol's nominal glyph box. WinUI is asked for no room, so the picture is drawn in the place its layout
    /// gives it.
    /// Design: docs/design/platforms/winui/controls.md#pictures
    override func measure(width: Double?, height: Double?) -> LayoutSize {
        let intrinsic: LayoutSize
        if let declared { intrinsic = declared }
        else if symbol { intrinsic = LayoutSize(width: 16, height: 16) }
        else {
            var size = [0.0, 0.0]
            swiftomniui_winui_image_size(handle, &size)
            intrinsic = LayoutSize(width: size[0], height: size[1])
        }
        // Bitmap/SVG dimensions and a symbol's nominal box are already known.
        // An arithmetic query must not replace a glyph's prepared native slot
        // or invalidate its ancestors just to discard XAML's size answer.
        // Native preparation still selects the real nonzero allocation before
        // Arrange; direct measurements retain their native Measure contract.
        if WinUILayoutView.queryingSize == 0 {
            _ = super.measure(width: intrinsic.width, height: intrinsic.height)
        }
        return intrinsic
    }

    override func commitGeometry(in place: Rect) {
        draw(in: place)
    }

    override func prepareMeasure(width: Double, height: Double? = nil) {
        if width.isFinite, let height, height.isFinite {
            // Supply final-size SVG pixels before native Measure. Replacing
            // Image.Source during Arrange dirties layout just like writing
            // a glyph's Width/Height there.
            draw(in: Rect(0, 0, width, height))
        }
        super.prepareMeasure(width: width, height: height)
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
