// SPDX-License-Identifier: Apache-2.0
@_spi(Host) import SwiftOmniUICore
import CSwiftOmniUIGTK

@MainActor enum GTKImageCodec {
    static func decode(_ data: [UInt8]) -> PicturePixels? {
        guard let bytes = data.withUnsafeBytes({ g_bytes_new($0.baseAddress, gsize($0.count)) }) else { return nil }
        defer { g_bytes_unref(bytes) }
        guard let texture = gdk_texture_new_from_bytes(bytes, nil) else { return nil }
        defer { g_object_unref(UnsafeMutableRawPointer(texture)) }
        let width = Int(gdk_texture_get_width(texture)), height = Int(gdk_texture_get_height(texture))
        guard width > 0, height > 0, width <= 16384, height <= 16384 else { return nil }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        gdk_texture_download(texture, &rgba, gsize(width * 4))
        // GDK's download format is Cairo ARGB32, native-endian and premultiplied.
        for index in stride(from: 0, to: rgba.count, by: 4) {
            #if _endian(little)
            rgba.swapAt(index, index + 2)
            #else
            let a = rgba[index]; rgba[index] = rgba[index + 1]
            rgba[index + 1] = rgba[index + 2]; rgba[index + 2] = rgba[index + 3]; rgba[index + 3] = a
            #endif
        }
        return PicturePixels(width: width, height: height, rgba: rgba)
    }
    static func encode(_ pixels: PicturePixels) -> [UInt8]? {
        guard let bitmap = BitmapImage(pixels: pixels), let texture = GTKMemoryImages.texture(bitmap) else { return nil }
        defer { g_object_unref(UnsafeMutableRawPointer(texture)) }
        guard let bytes = gdk_texture_save_to_png_bytes(texture) else { return nil }
        defer { g_bytes_unref(bytes) }
        var count: gsize = 0
        guard let data = g_bytes_get_data(bytes, &count) else { return nil }
        return Array(UnsafeRawBufferPointer(start: data, count: Int(count)))
    }
    static func copy(html: String, plainText: String) {
        guard let display = gdk_display_get_default(), let clipboard = gdk_display_get_clipboard(display) else { return }
        let formats = [("text/html", html), ("text/plain;charset=utf-8", plainText)]
        var providers: [UnsafeMutablePointer<GdkContentProvider>?] = formats.compactMap { mime, text in
            let data = Array(text.utf8)
            guard let bytes = data.withUnsafeBytes({ g_bytes_new($0.baseAddress, gsize($0.count)) }) else { return nil }
            defer { g_bytes_unref(bytes) }
            return gdk_content_provider_new_for_bytes(mime, bytes)
        }
        guard !providers.isEmpty, let provider = gdk_content_provider_new_union(&providers, gsize(providers.count)) else { return }
        // The union consumes the component providers; the clipboard retains the union.
        gdk_clipboard_set_content(clipboard, provider)
        g_object_unref(UnsafeMutableRawPointer(provider))
    }
}
