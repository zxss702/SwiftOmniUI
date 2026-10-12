// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIGTK

/// The application's pictures: the files of the `Images` folder beside the executable, found by the name the tree
/// gives them.
/// Design: docs/design/platforms/gtk/drawing.md#the-applications-pictures
@MainActor
enum GTKPictures {
    /// The folders pictures are read from: `Images` beside the executable, and
    /// each resource bundle beside it - a package's own assets land at its root.
    static var folders = besideExecutable()

    /// The pixels of the picture `name` names: premultiplied RGBA rows as `PicturePixels` hands back; nil for no
    /// picture, or one the platform's loaders do not read - an SVG with no loader installed. A pixbuf's bytes
    /// are RGB, plus a straight alpha where it has one; the readback premultiplies.
    static func pixels(of name: String) -> PicturePixels? {
        guard let path = path(of: name), let pixbuf = gdk_pixbuf_new_from_file(path, nil) else { return nil }
        defer { g_object_unref(UnsafeMutableRawPointer(pixbuf)) }
        let width = Int(gdk_pixbuf_get_width(pixbuf)), height = Int(gdk_pixbuf_get_height(pixbuf)),
            channels = Int(gdk_pixbuf_get_n_channels(pixbuf)), stride = Int(gdk_pixbuf_get_rowstride(pixbuf))
        guard width > 0, height > 0, channels >= 3, let data = gdk_pixbuf_get_pixels(pixbuf)
        else { return nil }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let source = y * stride + x * channels, at = (y * width + x) * 4
                let alpha = channels == 4 ? Int(data[source + 3]) : 255
                rgba[at] = UInt8(Int(data[source]) * alpha / 255)
                rgba[at + 1] = UInt8(Int(data[source + 1]) * alpha / 255)
                rgba[at + 2] = UInt8(Int(data[source + 2]) * alpha / 255)
                rgba[at + 3] = UInt8(alpha)
            }
        }
        return PicturePixels(width: width, height: height, rgba: rgba)
    }

    /// The file `name` names (`PictureArithmetic.files`): a PNG the folder holds as an SVG is the SVG. Nil for none.
    static func path(of name: String) -> String? {
        let files = PictureArithmetic.files(for: name)
        return folders.lazy.flatMap { folder in files.map { folder + "/" + $0 } }
            .first { g_file_test($0, G_FILE_TEST_IS_REGULAR) != 0 }
    }

    /// An image showing `name` as an icon `size` logical pixels across, which GTK draws at the display's scale:
    /// the icon theme's icon for a name it knows, else the file `name` names; nil where there is neither.
    static func icon(named name: String, size: Int32) -> GTKWidget? {
        if GTKSymbols.has(name) {
            let image = gtk_image_new_from_icon_name(name)
            if let image { gtk_image_set_pixel_size(image.opaque, size) }
            return image
        }
        guard let path = path(of: name), let file = g_file_new_for_path(path) else { return nil }
        let icon = g_file_icon_new(file)
        let image = gtk_image_new_from_gicon(icon)
        g_object_unref(UnsafeMutableRawPointer(icon))
        g_object_unref(UnsafeMutableRawPointer(file))
        if let image { gtk_image_set_pixel_size(image.opaque, size) }
        return image
    }

    private static func besideExecutable() -> [String] {
        guard let link = g_file_read_link("/proc/self/exe", nil) else { return ["Images"] }
        defer { g_free(link) }
        guard let bin = g_path_get_dirname(link) else { return ["Images"] }
        defer { g_free(bin) }
        let root = String(cString: bin)
        var folders = [root + "/Images"]
        guard let entries = g_dir_open(root, 0, nil) else { return folders }
        defer { g_dir_close(entries) }
        while let entry = g_dir_read_name(entries) {
            let name = String(cString: entry)
            if name.hasSuffix(".bundle") { folders.append(root + "/" + name) }
        }
        return folders
    }
}
