// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The facade's own half of `Fonts`: on platforms shipping SwiftUI the
// platform's own font registry takes the files; everywhere else the engine
// declares the same type and each host fills its add.

#if canImport(SwiftUI)
import CoreText
import Foundation

/// The application's fonts: files it carries, added to the platform's font
/// registry so `Font.custom` can name the families inside.
///
///     Fonts.register(path: Bundle.module.path(forResource: "Songti", ofType: "ttf")!)
public enum Fonts {
    /// Adds the font file at `path` to the fonts `Font.custom` can name, for
    /// this process - `CTFontManagerRegisterFontsForURL`'s process scope, as
    /// before.
    ///
    /// - Parameter path: the font file's path on disk.
    /// - Returns: whether the file was taken.
    @discardableResult
    public static func register(path: String) -> Bool {
        CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: path) as CFURL, .process, nil)
    }
}
#endif
