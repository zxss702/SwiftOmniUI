// SPDX-License-Identifier: Apache-2.0
// Immutable, real image pixels. Logical dimensions are independent of raster scale.

public struct BitmapImage: Equatable, Sendable {
    public let pixels: PicturePixels
    public let scale: Double
    public let size: Size
    public func withLogicalSize(_ size: Size) -> BitmapImage {
        // Invalid proposals cannot corrupt an already decoded image.
        BitmapImage(pixels: pixels, scale: scale, size: size) ?? self
    }
    public init?(pixels: PicturePixels, scale: Double = 1, size: Size? = nil) {
        guard scale.isFinite, scale > 0, pixels.width > 0, pixels.height > 0,
              pixels.width <= Int.max / pixels.height / 4,
              pixels.rgba.count == pixels.width * pixels.height * 4 else { return nil }
        let logical = size ?? Size(Double(pixels.width) / scale, Double(pixels.height) / scale)
        guard logical.width.isFinite, logical.height.isFinite, logical.width > 0, logical.height > 0 else { return nil }
        self.pixels = pixels; self.scale = scale; self.size = logical
    }
    public static func render(size: Size, scale: Double, drawing: [DrawCommand]) -> BitmapImage? {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
              scale.isFinite, scale > 0, size.width * scale <= 16384, size.height * scale <= 16384,
              let pixels = rasterize?(size, scale, drawing.compactMap { DrawCommand(propValue: $0.propValue.resolvingColorScheme()) }) else { return nil }
        return BitmapImage(pixels: pixels, scale: scale, size: size)
    }
    public init?(encodedBytes: [UInt8]) {
        guard let pixels = Self.decode?(encodedBytes) else { return nil }
        self.init(pixels: pixels)
    }
    public func pngBytes() -> [UInt8]? { Self.encodePNG?(pixels) }
    @_spi(Host) public nonisolated(unsafe) static var decode: (([UInt8]) -> PicturePixels?)?
    @_spi(Host) public nonisolated(unsafe) static var encodePNG: ((PicturePixels) -> [UInt8]?)?
    @_spi(Host) public nonisolated(unsafe) static var rasterize: ((Size, Double, [DrawCommand]) -> PicturePixels?)?
}
