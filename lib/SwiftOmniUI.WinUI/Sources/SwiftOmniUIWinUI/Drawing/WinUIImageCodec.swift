// SPDX-License-Identifier: Apache-2.0
@_spi(Host) import SwiftOmniUICore
import CSwiftOmniUIWinUI

@MainActor enum WinUIImageCodec {
    static func decode(_ bytes: [UInt8]) -> PicturePixels? {
        var size: [Int32] = [0, 0]
        guard let image = bytes.withUnsafeBufferPointer({ swiftomniui_winui_decode_image($0.baseAddress, Int64($0.count), &size) }) else { return nil }
        defer { swiftomniui_winui_image_bytes_close(image) }
        guard size[0] > 0, size[1] > 0, size[0] <= 16384, size[1] <= 16384 else { return nil }
        var rgba = [UInt8](repeating: 0, count: Int(size[0]) * Int(size[1]) * 4)
        guard swiftomniui_winui_image_bytes(image, &rgba, Int64(rgba.count)) else { return nil }
        return PicturePixels(width: Int(size[0]), height: Int(size[1]), rgba: rgba)
    }
    static func encode(_ pixels: PicturePixels) -> [UInt8]? {
        guard pixels.width > 0, pixels.height > 0, pixels.width <= 16384, pixels.height <= 16384,
              pixels.rgba.count == pixels.width * pixels.height * 4 else { return nil }
        var count: Int64 = 0
        guard let image = pixels.rgba.withUnsafeBufferPointer({ swiftomniui_winui_encode_png($0.baseAddress,
            Int32(pixels.width), Int32(pixels.height), &count) }) else { return nil }
        defer { swiftomniui_winui_image_bytes_close(image) }
        guard count > 0, count <= Int64(Int.max) else { return nil }
        var bytes = [UInt8](repeating: 0, count: Int(count))
        return swiftomniui_winui_image_bytes(image, &bytes, count) ? bytes : nil
    }
}
