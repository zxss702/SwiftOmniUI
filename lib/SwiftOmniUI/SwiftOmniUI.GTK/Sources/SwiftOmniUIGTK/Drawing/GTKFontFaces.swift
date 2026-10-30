// SPDX-License-Identifier: Apache-2.0
@_spi(Host) import SwiftOmniUICore
import CFreeType
import CNativeFontShaping

@MainActor enum GTKFontFaces {
    static func open(_ path: String) -> FontFace.Operations? {
        var units = 0.0
        guard let face = soui_font_open(path, &units) else { return nil }
        guard let shaping = soui_shaping_font_open(path, Int32(units)) else {
            soui_font_close(face)
            return nil
        }
        return FontFace.Operations(unitsPerEm: units,
            glyph: { soui_font_glyph(face, $0) },
            metrics: { glyph in
                var values = [Double](repeating: 0, count: 5)
                return soui_font_metrics(face, glyph, &values) != 0 ? values : [0, 0, 0, 0, 0]
            }, outline: { glyph in
                let count = soui_font_outline(face, glyph, nil, 0)
                guard count > 0 else { return "" }
                var bytes = [CChar](repeating: 0, count: Int(count) + 1)
                guard soui_font_outline(face, glyph, &bytes, count + 1) == count else { return "" }
                return String(cString: bytes)
            }, table: { tag in
                let count = soui_font_table(face, tag, nil, 0)
                guard count > 0 else { return [] }
                var bytes = [UInt8](repeating: 0, count: Int(count))
                guard soui_font_table(face, tag, &bytes, count) == count else { return [] }
                return bytes
            }, shape: { text in
                guard text.count <= Int(Int32.max) else { return nil }
                let native = text.withUnsafeBufferPointer { soui_font_shape(shaping, $0.baseAddress, Int32($0.count)) }
                guard let native else { return nil }
                defer { soui_shaped_text_close(native) }
                let glyphs = UnsafeBufferPointer(start: native.pointee.glyphs, count: Int(native.pointee.count)).map {
                    FontFace.ShapedGlyph(id: $0.glyph, position: Point($0.x, $0.y), advance: $0.advance,
                        cluster: Int($0.clusterStart)..<Int($0.clusterStart + $0.clusterLength))
                }
                let breaks = text.indices.compactMap { index -> FontFace.LineBreak? in
                    let offset = index + 1
                    guard native.pointee.breaks[offset] != 0 else { return nil }
                    return .init(offset: offset, mandatory: native.pointee.breaks[offset] == 2)
                }
                return .init(glyphs: glyphs, width: native.pointee.width, lineBreaks: breaks)
            }, close: { soui_shaping_font_close(shaping); soui_font_close(face) })
    }
}
