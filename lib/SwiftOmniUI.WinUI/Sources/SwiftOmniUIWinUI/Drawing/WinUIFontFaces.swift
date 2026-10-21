// SPDX-License-Identifier: Apache-2.0
@_spi(Host) import SwiftOmniUICore
import CSwiftOmniUIWinUI

@MainActor enum WinUIFontFaces {
    static func open(_ path: String) -> FontFace.Operations? {
        var units = 0.0
        guard let face = swiftomniui_winui_font_open(path, &units) else { return nil }
        return FontFace.Operations(unitsPerEm: units,
            glyph: { swiftomniui_winui_font_glyph(face, $0) },
            metrics: { glyph in
                var values = [Double](repeating: 0, count: 5)
                return swiftomniui_winui_font_metrics(face, glyph, &values) ? values : [0, 0, 0, 0, 0]
            }, outline: { glyph in
                let count = swiftomniui_winui_font_outline(face, glyph, nil, 0)
                guard count > 0 else { return "" }
                var bytes = [CChar](repeating: 0, count: Int(count) + 1)
                guard swiftomniui_winui_font_outline(face, glyph, &bytes, count + 1) == count else { return "" }
                return String(cString: bytes)
            }, table: { tag in
                let count = swiftomniui_winui_font_table(face, tag, nil, 0)
                guard count > 0 else { return [] }
                var bytes = [UInt8](repeating: 0, count: Int(count))
                guard swiftomniui_winui_font_table(face, tag, &bytes, count) == count else { return [] }
                return bytes
            }, shape: { text in
                guard text.count <= Int(Int32.max) else { return nil }
                let shape = text.withUnsafeBufferPointer {
                    swiftomniui_winui_font_shape(face, $0.baseAddress, Int32($0.count))
                }
                guard let shape else { return nil }
                defer { swiftomniui_winui_shaped_close(shape) }
                let count = Int(swiftomniui_winui_shaped_glyph_count(shape))
                let glyphs = UnsafeBufferPointer(start: swiftomniui_winui_shaped_glyphs(shape), count: count).map {
                    FontFace.ShapedGlyph(id: $0.glyph, position: Point($0.x, $0.y), advance: $0.advance,
                        cluster: Int($0.clusterStart)..<Int($0.clusterStart + $0.clusterLength), isVisible: $0.visible)
                }
                guard let nativeBreaks = swiftomniui_winui_shaped_breaks(shape) else { return nil }
                let breaks = text.indices.compactMap { index -> FontFace.LineBreak? in
                    let offset = index + 1
                    return nativeBreaks[offset] == 0 ? nil
                        : .init(offset: offset, mandatory: nativeBreaks[offset] == 2)
                }
                return .init(glyphs: glyphs, width: swiftomniui_winui_shaped_width(shape), lineBreaks: breaks)
            }, close: { swiftomniui_winui_font_close(face) })
    }
}
