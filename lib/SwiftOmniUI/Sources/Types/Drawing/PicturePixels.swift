// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// A picture's own pixels, read back - for code that works on the picture
// itself, an average or a dominant colour.

/// A picture's pixels: `width` by `height`, four bytes a pixel - red, green, blue and alpha, every channel
/// premultiplied by the alpha - in rows from the top down.
///
///     let pixels = PicturePixels(named: "logo.png")
///
/// The name is the one `Image` takes: a file the application carries, found where the host looks for its
/// pictures. A symbol's name, or a picture the platform's decoder does not read - an SVG where it reads only
/// bitmaps - answers nil.
public struct PicturePixels: Equatable, Sendable {
    /// The picture's size, in pixels.
    public var width: Int
    public var height: Int

    /// `width * height * 4` bytes: every pixel's RGBA, premultiplied, in rows from the top down.
    public var rgba: [UInt8]

    /// Pixels read back, as a host hands them.
    public init(width: Int, height: Int, rgba: [UInt8]) {
        self.width = width
        self.height = height
        self.rgba = rgba
    }

    /// The pixels of the picture `name` names where `Image` finds it; nil where the host reads none back, or the
    /// name stands for no picture the platform's decoder knows.
    public init?(named name: String) {
        guard let read = Self.read, let pixels = read(name) else { return nil }
        self = pixels
    }

    /// The reader a host binds: a picture's name, as `Image` takes it, to its pixels; nil where a host reads none
    /// back. Bound once as the host starts, and called on the UI thread.
    @_spi(Host) public nonisolated(unsafe) static var read: ((String) -> PicturePixels?)?
}
