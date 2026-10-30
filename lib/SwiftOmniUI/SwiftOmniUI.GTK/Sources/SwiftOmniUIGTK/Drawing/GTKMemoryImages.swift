// SPDX-License-Identifier: Apache-2.0
@_spi(Host) import SwiftOmniUICore
import CSwiftOmniUIGTK

@MainActor enum GTKMemoryImages {
    static func texture(_ bitmap: BitmapImage) -> OpaquePointer? {
        let pixels = bitmap.pixels
        guard pixels.width > 0, pixels.height > 0,
              pixels.width <= Int(Int32.max), pixels.height <= Int(Int32.max),
              pixels.width <= Int.max / pixels.height / 4,
              pixels.rgba.count == pixels.width * pixels.height * 4 else { return nil }
        let bytes = pixels.rgba.withUnsafeBytes { g_bytes_new($0.baseAddress, gsize($0.count)) }
        guard let bytes else { return nil }
        defer { g_bytes_unref(bytes) }
        return gdk_memory_texture_new(Int32(pixels.width), Int32(pixels.height), GDK_MEMORY_R8G8B8A8_PREMULTIPLIED,
                                      bytes, gsize(pixels.width * 4))
    }
}
