// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIGTK

/// The names `Image(systemName:)` writes are the platform's own: freedesktop
/// icon names, asked of the icon theme rather than a table, so whichever theme
/// the user runs answers them - the icons bundled beside the process's products
/// (`*.resources`/`*.bundle`'s `Icons`, laid out as an icon theme) standing in its search
/// paths, so the names a theme lacks still answer. A name nobody knows shows
/// the theme's missing-image icon.
@MainActor
enum GTKSymbols {
    /// Whether the bundled icons stand in the theme's search paths yet.
    private static var registered = false

    /// The theme's native symbolic paintable. The caller owns its reference.
    static func paintable(of name: String, size: Int32 = 32, scale: Int32 = 1) -> OpaquePointer? {
        guard let display = gdk_display_get_default() else { return nil }
        guard let theme = gtk_icon_theme_get_for_display(display) else { return nil }
        registerBundledIcons(in: theme)
        guard let icon = g_themed_icon_new(name) else { return nil }
        defer { g_object_unref(UnsafeMutableRawPointer(icon)) }
        return gtk_icon_theme_lookup_by_gicon(
            theme, icon, size, scale, GTK_TEXT_DIR_LTR, GTK_ICON_LOOKUP_FORCE_SYMBOLIC)
    }

    /// Whether the icon theme knows `name` - the bundled icons registered first.
    static func has(_ name: String) -> Bool {
        guard let display = gdk_display_get_default() else { return false }
        guard let theme = gtk_icon_theme_get_for_display(display) else { return false }
        registerBundledIcons(in: theme)
        return gtk_icon_theme_has_icon(theme, name) != 0
    }

    /// Adds every `*.resources/Icons` folder beside the executable to the theme's search paths - this package's
    /// bundled symbolic icons, and any an application bundles of its own.
    private static func registerBundledIcons(in theme: OpaquePointer) {
        guard !registered else { return }
        registered = true
        for folder in Self.iconFolders() {
            gtk_icon_theme_add_search_path(theme, folder)
        }
    }

    /// Every `Icons` folder under a `*.resources` or `*.bundle` directory beside the executable - the resource
    /// bundles SwiftPM names one or the other.
    private static func iconFolders() -> [String] {
        guard let link = g_file_read_link("/proc/self/exe", nil) else { return [] }
        defer { g_free(link) }
        guard let folder = g_path_get_dirname(link) else { return [] }
        defer { g_free(folder) }
        let root = String(cString: folder)
        guard let entries = g_dir_open(root, 0, nil) else { return [] }
        defer { g_dir_close(entries) }

        var folders: [String] = []
        while let entry = g_dir_read_name(entries) {
            let name = String(cString: entry)
            guard name.hasSuffix(".resources") || name.hasSuffix(".bundle") else { continue }
            let icons = root + "/" + name + "/Icons"
            if g_file_test(icons, G_FILE_TEST_IS_DIR) != 0 { folders.append(icons) }
        }
        return folders
    }
}
