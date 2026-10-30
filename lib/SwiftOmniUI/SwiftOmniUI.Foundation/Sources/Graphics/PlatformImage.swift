// SPDX-License-Identifier: Apache-2.0
// Desktop image storage for framework adapters: real pixels or a native symbol.
import Foundation
@_spi(Host) import SwiftOmniUICore

public final class PlatformImage: @unchecked Sendable, Hashable {
    public let source: ImageSource
    public let size: CGSize
    public init(cgImage: CGImage, size: CGSize) {
        self.source = ImageSource(bitmap: cgImage.bitmap.withLogicalSize(Size(Double(size.width), Double(size.height))))
        self.size = size
    }
    public init() {
        source = ImageSource(bitmap: BitmapImage(pixels: PicturePixels(width: 1, height: 1, rgba: [0, 0, 0, 0]))!)
        size = .zero
    }
    public convenience init?(data: Data) {
        guard let bitmap = BitmapImage(encodedBytes: Array(data)) else { return nil }
        self.init(source: ImageSource(bitmap: bitmap), size: CGSize(width: bitmap.size.width, height: bitmap.size.height))
    }
    public convenience init?(contentsOf url: URL) {
        guard url.isFileURL, let data = try? Data(contentsOf: url) else { return nil }
        self.init(data: data)
    }
    public init?(named name: String) {
        guard let pixels = PicturePixels(named: name), let bitmap = BitmapImage(pixels: pixels) else { return nil }
        source = ImageSource(bitmap: bitmap); size = CGSize(width: bitmap.size.width, height: bitmap.size.height)
    }
    public init(systemSymbolName name: String, size: CGFloat) {
        source = .symbol(name); self.size = CGSize(width: size, height: size)
    }
    private init(source: ImageSource, size: CGSize) { self.source = source; self.size = size }
    public func resized(to size: CGSize) -> PlatformImage {
        let source = source.bitmap.map { ImageSource(bitmap: $0.withLogicalSize(Size(Double(size.width), Double(size.height)))) } ?? source
        return PlatformImage(source: source, size: size)
    }
    public static func == (lhs: PlatformImage, rhs: PlatformImage) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}
public extension Image {
    init(platformImage: PlatformImage) {
        self.init(platformImage.source)
        if platformImage.source.symbol != nil, platformImage.size.height.isFinite, platformImage.size.height > 0 {
            node.write(FontElementContract.fontSize, Double(platformImage.size.height))
        }
    }
}
