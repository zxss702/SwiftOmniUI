// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The facade's own half of `PicturePixels`: on platforms shipping SwiftUI the
// platform's own decoders read a picture's pixels; everywhere else the engine
// declares the same type and each host fills its reader.

#if canImport(SwiftUI)
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import CoreGraphics
import Foundation

/// A picture's pixels: `width` by `height`, four bytes a pixel - red, green, blue and alpha, every channel
/// premultiplied by the alpha - in rows from the top down.
///
///     let pixels = PicturePixels(named: "logo.png")
///
/// The name is the one `Image` takes: a file the application's resource bundles carry. A name no bundle holds,
/// or a picture the platform's decoder does not read, answers nil.
public struct PicturePixels: Equatable, Sendable {
    /// The picture's size, in pixels.
    public var width: Int
    public var height: Int

    /// `width * height * 4` bytes: every pixel's RGBA, premultiplied, in rows from the top down.
    public var rgba: [UInt8]

    /// Pixels read back.
    public init(width: Int, height: Int, rgba: [UInt8]) {
        self.width = width
        self.height = height
        self.rgba = rgba
    }

    /// The pixels of the picture `name` names: a resource the application's bundles hold, read in sRGB; nil where
    /// no bundle holds it, or the platform's decoder does not read it.
    public init?(named name: String) {
        guard let image = Self.image(named: name), let bytes = Self.rgba(of: image) else { return nil }
        width = image.width
        height = image.height
        rgba = bytes
    }

    /// The bundles a picture's name resolves in: the loaded ones first - a target's own resource bundle among
    /// them - then every `.bundle` the application carries and every one beside the executable.
    private static func bundles() -> [Bundle] {
        var bundles = Bundle.allBundles + Bundle.allFrameworks
        let manager = FileManager.default
        var roots = [Bundle.main.bundleURL.deletingLastPathComponent()]
        if let resources = Bundle.main.resourceURL { roots.append(resources) }
        for root in roots {
            guard let entries = try? manager.contentsOfDirectory(atPath: root.path) else { continue }
            for entry in entries where entry.hasSuffix(".bundle") {
                if let bundle = Bundle(url: root.appendingPathComponent(entry)), !bundles.contains(bundle) {
                    bundles.append(bundle)
                }
            }
        }
        return bundles
    }

    /// `image` drawn into an 8-bit sRGB bitmap: premultiplied RGBA bytes.
    private static func rgba(of image: CGImage) -> [UInt8]? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: image.width, height: image.height,
                  bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Array(UnsafeBufferPointer(
            start: data.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4))
    }

    /// The files `name` may stand for, in the order a host looks for them: the name, then - for a PNG - an SVG of
    /// the same name. A bare name, carrying no extension, stands for its `.png` and `.svg` too.
    private static func files(for name: String) -> [String] {
        if name.lowercased().hasSuffix(".png") {
            return [name, String(name.dropLast(4)) + ".svg"]
        }
        let bare = !(name.split(separator: "/").last ?? "").contains(".")
        return bare ? [name, name + ".png", name + ".svg"] : [name]
    }

    #if canImport(AppKit)
    /// The image `name` names in any of the application's bundles - what `Bundle.module.image(forResource:)`
    /// answers, asked of every bundle since this file cannot name the module's own.
    private static func image(named name: String) -> CGImage? {
        for bundle in bundles() {
            for file in files(for: name) {
                if let image = bundle.image(forResource: file),
                   let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    return cgImage
                }
            }
        }
        return nil
    }
    #elseif canImport(UIKit)
    /// The image `name` names in any of the application's bundles, found as a file wherever it is kept.
    private static func image(named name: String) -> CGImage? {
        let files = files(for: name)
        for bundle in bundles() {
            guard let root = bundle.resourceURL,
                  let entries = try? FileManager.default.subpathsOfDirectory(atPath: root.path) else { continue }
            for entry in entries where files.contains((entry as NSString).lastPathComponent) {
                if let image = UIImage(contentsOfFile: root.appendingPathComponent(entry).path)?.cgImage {
                    return image
                }
            }
        }
        return nil
    }
    #else
    private static func image(named name: String) -> CGImage? { nil }
    #endif
}
#endif
